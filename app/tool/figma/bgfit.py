# Fit a tile background as: base fill + N blurred ellipses composited src-over.
# Each blob: centre (cx,cy), radii (rx,ry), rotation th, softness w (in units of
# the normalised radius), peak alpha a, colour rgb. Coverage profile
#   alpha(d) = a * 0.5*erfc((d-1)/(sqrt(2)*w)),  d = elliptical normalised distance
# which is exactly what the Dart painter renders from generated gradient stops.
import numpy as np, json, sys, math, time
from PIL import Image
W="C:/Users/Armaan khan/Desktop/Hobbies/fitness-tracker/app/Widget"
def erfc(x):
    # Abramowitz-Stegun 7.1.26 on |x|, max abs err 1.5e-7
    z=np.abs(x); t=1/(1+0.3275911*z)
    y=t*(0.254829592+t*(-0.284496736+t*(1.421413741+t*(-1.453152027+t*1.061405429))))*np.exp(-z*z)
    return np.where(x>=0, y, 2-y)
def sig(x): return 1/(1+np.exp(-x))
def logit(p): p=min(max(p,1e-4),1-1e-4); return math.log(p/(1-p))
NB=10
def unpack(v,nb):
    base=sig(v[0:3]); blobs=[]
    for i in range(nb):
        q=v[3+i*NB:3+(i+1)*NB]
        blobs.append(dict(cx=q[0],cy=q[1],rx=math.exp(min(max(q[2],0),7)),ry=math.exp(min(max(q[3],0),7)),th=q[4],w=math.exp(min(max(q[5],-5),2)),a=sig(q[6]),c=sig(q[7:10])))
    return base,blobs
def pack(base,blobs):
    v=[logit(x) for x in base]
    for b in blobs:
        v+= [b['cx'],b['cy'],math.log(b['rx']),math.log(b['ry']),b['th'],math.log(b['w']),logit(b['a'])]+[logit(x) for x in b['c']]
    return np.array(v,float)
def render(v,nb,X,Y):
    base,blobs=unpack(v,nb)
    out=np.empty(X.shape+(3,)); out[:]=base
    for b in blobs:
        dx=X-b['cx']; dy=Y-b['cy']; c,s=math.cos(b['th']),math.sin(b['th'])
        u=( c*dx+s*dy)/b['rx']; w=(-s*dx+c*dy)/b['ry']
        d=np.sqrt(u*u+w*w)
        al=b['a']*0.5*erfc((d-1)/(math.sqrt(2)*b['w']))
        out=out*(1-al[...,None])+b['c']*al[...,None]
    return out
def boxblur(a,r):
    # separable box blur via cumsum, edge-padded
    p=np.pad(a,((r,r),(r,r),(0,0)),mode='edge')
    c=np.cumsum(p,axis=0); c=np.concatenate([np.zeros((1,)+c.shape[1:]),c],0)
    a1=(c[2*r+1:]-c[:-2*r-1])/(2*r+1)
    c=np.cumsum(a1,axis=1); c=np.concatenate([np.zeros((c.shape[0],1,c.shape[2])),c],1)
    return (c[:,2*r+1:]-c[:,:-2*r-1])/(2*r+1)
def dilate(m,r):
    if r<=0: return m
    p=np.pad(m,r); out=np.zeros_like(m)
    for dy in range(-r,r+1):
        for dx in range(-r,r+1):
            out|=p[r+dy:r+dy+m.shape[0], r+dx:r+dx+m.shape[1]]
    return out
def load(name,cfg):
    im=np.array(Image.open(f'{W}/{name}.png').convert('RGBA')).astype(float)/255
    rgb=im[...,:3]; al=im[...,3]
    hp=np.abs(rgb-boxblur(rgb,4)).max(axis=2)
    fg=hp>cfg.get('hp',0.035)
    fg=dilate(fg,cfg.get('dil',3))
    for (x0,y0,x1,y1) in cfg.get('rects',[]): fg[y0:y1,x0:x1]=True
    H,Wd=al.shape; YY,XX=np.mgrid[0:H,0:Wd]+.5
    for (cx,cy,r0,r1,ymax) in cfg.get('rings',[]):
        rr=np.hypot(XX-cx,YY-cy); fg|=(rr>=r0)&(rr<=r1)&(YY<=ymax)
    extra=cfg.get('_extra')
    if extra is not None: fg|=extra
    valid=(al>0.999)&(~fg)
    # also exclude a 2px band near the edge (anti-aliased corners)
    return rgb,valid
def fit(name,cfg,nblobs=5,log=print,init=None):
    rgb,valid=load(name,cfg)
    H,Wd=valid.shape
    def level(k):
        h,w=H//k,Wd//k
        r=rgb[:h*k,:w*k].reshape(h,k,w,k,3).mean(axis=(1,3))
        m=valid[:h*k,:w*k].reshape(h,k,w,k).all(axis=(1,3))
        Y,X=np.mgrid[0:h,0:w].astype(float); X=(X+.5)*k; Y=(Y+.5)*k
        return r,m,X,Y
    lv=[level(4),level(2)]
    def resid(v,nb,L):
        r,m,X,Y=L
        return (render(v,nb,X[m],Y[m])-r[m]).ravel()
    def lm(v,nb,L,iters):
        lam=1e-2; res=resid(v,nb,L); cost=(res**2).sum()
        for it in range(iters):
            J=np.empty((res.size,v.size)); eps=1e-4
            for j in range(v.size):
                v2=v.copy(); v2[j]+=eps; J[:,j]=(resid(v2,nb,L)-res)/eps
            A=J.T@J; g=J.T@res
            improved=False
            for _ in range(8):
                try: d=np.linalg.solve(A+lam*np.diag(np.diag(A)+1e-9),-g)
                except np.linalg.LinAlgError: lam*=10; continue
                # cap the step: log/logit params move <= 1.5, positions <= 40 px
                sc=1.0
                for j in range(v.size):
                    lim=40.0 if (j>=3 and (j-3)%NB in (0,1)) else 1.5
                    if abs(d[j])*sc>lim: sc=lim/abs(d[j])
                v2=v+d*sc; r2=resid(v2,nb,L); c2=(r2**2).sum()
                if c2<cost:
                    v,res,cost=v2,r2,c2; lam=max(lam/3,1e-7); improved=True; break
                lam*=4
            if not improved or np.abs(d).max()<1e-6: break
        return v,cost
    r,m,X,Y=lv[0]
    base0=np.median(r[m],axis=0)
    blobs=[]
    v=pack(base0,blobs)
    if init is not None:
        v=init
        v,c=lm(v,nblobs,lv[0],60)
        v,c=lm(v,nblobs,lv[1],40)
        r2,m2,X2,Y2=lv[1]
        rms=math.sqrt(c/(m2.sum()*3)); log(f'  {name}: refit half-res rms {rms*255:.2f}/255')
        return v,nblobs,rms
    for nb in range(1,nblobs+1):
        # new blob where the smoothed residual is largest
        cur=render(v,nb-1,X,Y); diff=(r-cur); diff[~m]=0
        sm=boxblur(diff,3); mag=np.abs(sm).sum(axis=2)
        iy,ix=np.unravel_index(np.argmax(mag),mag.shape)
        col=np.clip(r[iy,ix],0.01,0.99)
        cands=[]
        for rad in (0.18,0.35,0.6):
            b=dict(cx=X[iy,ix],cy=Y[iy,ix],rx=rad*Wd,ry=rad*H,th=0.0,w=0.35,a=0.85,c=col)
            base,bl=unpack(v,nb-1)
            vv=pack(base,bl+[b]); vv,c=lm(vv,nb,lv[0],25); cands.append((c,vv))
        cands.sort(key=lambda t:t[0]); v=cands[0][1]
        log(f'  {name}: {nb} blobs cost {cands[0][0]:.3f}')
    v,c=lm(v,nblobs,lv[0],80)
    v,c=lm(v,nblobs,lv[1],40)
    r2,m2,X2,Y2=lv[1]
    rms=math.sqrt(c/(m2.sum()*3))
    log(f'  {name}: final half-res rms {rms*255:.2f}/255')
    return v,nblobs,rms
def to_json(v,nb):
    base,blobs=unpack(v,nb)
    return dict(base=[float(x) for x in base],blobs=[dict(cx=float(b['cx']),cy=float(b['cy']),rx=float(b['rx']),ry=float(b['ry']),th=float(b['th']),w=float(b['w']),a=float(b['a']),c=[float(x) for x in b['c']]) for b in blobs])
def preview(name,cfg,v,nb,out):
    rgb,valid=load(name,cfg)
    H,Wd=valid.shape
    Y,X=np.mgrid[0:H,0:Wd].astype(float)+.5
    ren=render(v,nb,X,Y)
    diff=np.abs(ren-rgb).max(axis=2)
    dimg=np.clip(diff*4,0,1)
    vis=np.concatenate([rgb,ren,np.stack([dimg,dimg*0.3,valid*0.25],2)],1)
    Image.fromarray((vis*255).astype(np.uint8)).resize((vis.shape[1]*2,vis.shape[0]*2),Image.NEAREST).save(out)
    d=diff[valid]
    return float((d>10/255).mean()), float(d.mean()*255)
if __name__=='__main__':
    cfgs=json.load(open('bgcfg.json'))
    names=sys.argv[1:] or list(cfgs)
    out={}
    for n in names:
        cfg=cfgs[n]; t0=time.time()
        v,nb,rms=fit(n,cfg,cfg.get('n',5))
        for rep in range(cfg.get('robust',2)):
            rgb,_=load(n,cfg); H,Wd=rgb.shape[:2]
            Y,X=np.mgrid[0:H,0:Wd].astype(float)+.5
            res=np.abs(render(v,nb,X,Y)-rgb).max(axis=2)
            cfg=dict(cfg); prev=cfg.get('_extra'); ex=dilate(res>cfg.get('rob_t',0.06),2)
            cfg['_extra']=ex if prev is None else (prev|ex)
            v,nb,rms=fit(n,cfg,nb,init=v)
        out[n]=to_json(v,nb); out[n]['rms']=rms*255
        frac,mae=preview(n,cfg,v,nb,f'bg_{n.replace("/","_")}.png')
        out[n]['bgdiff']=frac; out[n]['mae']=mae
        print(f'{n}: rms {rms*255:.2f} bg px>10: {frac*100:.2f}% mae {mae:.2f} ({time.time()-t0:.0f}s)',flush=True)
        json.dump({n:out[n]},open(f'bgfit_{n.replace("/","_")}.json','w'),indent=1)
