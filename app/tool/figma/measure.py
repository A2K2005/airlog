# Fit text elements of a Figma PNG: font size, weight, letter spacing and the
# pen origin (x, baseline y) in tile pixels.  Usage: measure.py SPECNAME...
import numpy as np, sys, json, time
from PIL import Image, ImageFont, ImageDraw
W="C:/Users/Armaan khan/Desktop/Hobbies/fitness-tracker/app/Widget"
S=4
FONT={'dm':'fonts/DMSans.ttf','dot':'fonts/SubwayTickerGrid.ttf'}
_cache={}
def font(kind,w,size):
    k=(kind,w,round(size,3))
    if k in _cache: return _cache[k]
    f=ImageFont.truetype(FONT[kind], size*S)
    if kind=='dm':
        vals=[]
        for a in f.get_variation_axes():
            n=a.get('name'); n=n.decode() if isinstance(n,bytes) else str(n)
            vals.append(w if 'eight' in n else (max(9,min(40,size)) if 'ptical' in n else a['default']))
        f.set_variation_by_axes(vals)
    _cache[k]=f; return f
def coverage(img,rect,ink=None):
    x0,y0,x1,y1=rect; c=img[y0:y1,x0:x1,:3]
    lum=c.max(axis=2)
    border=np.concatenate([lum[0],lum[-1],lum[:,0],lum[:,-1]])
    bg=np.median(border); hi=ink if ink is not None else np.percentile(lum,99.7)
    return np.clip((lum-bg)/(hi-bg),0,1), bg, hi
def ink_bbox(cov,t=0.35):
    r=np.nonzero(cov.max(axis=1)>t)[0]; c=np.nonzero(cov.max(axis=0)>t)[0]
    return r.min(),r.max(),c.min(),c.max()
def render(kind,w,size,ls,text):
    f=font(kind,w,size)
    asc,desc=f.getmetrics()
    wpx=f.getlength(text)+ls*S*max(len(text)-1,0)
    PAD=6*S
    img=Image.new('L',(int(wpx)+2*PAD, asc+desc+2*PAD),0); d=ImageDraw.Draw(img)
    ox,oy=PAD, PAD+asc
    if ls==0: d.text((ox,oy),text,font=f,fill=255,anchor='ls')
    else:
        for i,ch in enumerate(text):
            d.text((ox+f.getlength(text[:i])+i*ls*S,oy),ch,font=f,fill=255,anchor='ls')
    return np.array(img).astype(float)/255, ox, oy, wpx/S
def best_place(r4,ox4,oy4,cov):
    h,w=cov.shape; H,Wd=r4.shape; best=(1e9,0,0)
    for py in range(S):
        for px in range(S):
            sub=r4[py:py+((H-py)//S)*S, px:px+((Wd-px)//S)*S]
            ds=sub.reshape(sub.shape[0]//S,S,sub.shape[1]//S,S).mean(axis=(1,3))
            # only search offsets that put the ink roughly on the crop ink
            for oy in range(0, ds.shape[0]-h+1):
                for oxx in range(0, ds.shape[1]-w+1):
                    e=np.abs(ds[oy:oy+h,oxx:oxx+w]-cov).sum()
                    if e<best[0]: best=(e,(ox4-px)/S-oxx,(oy4-py)/S-oy)
    return best
def fit(img,el):
    rect=el['rect']; text=el['text']; kind=el.get('font','dm')
    cov,bg,hi=coverage(img,rect)
    r0,r1,c0,c1=ink_bbox(cov)
    m=1
    y0c,x0c=max(r0-m,0),max(c0-m,0)
    cov=cov[y0c:r1+m+1, x0c:c1+m+1]
    inkw=c1-c0+1; norm=cov.sum()
    weights=el.get('w',[400,450,500,550,600]) if kind=='dm' else [400]
    sizes=el.get('sizes') or (list(np.arange(7,24.01,0.5)) if kind=='dm' else list(np.arange(20,80.01,1)))
    lsf=el.get('ls',[-0.02,-0.01,0]) if kind=='dm' else [0]
    best=(1e9,)
    for w in weights:
        for size in sizes:
            f=font(kind,w,size)
            for lf in lsf:
                ls=lf*size
                wpx=(f.getlength(text)+ls*S*max(len(text)-1,0))/S
                # ink width is advance minus side bearings: allow slack
                if not (inkw-4 <= wpx <= inkw+6 + (2 if kind=='dm' else 0.3*size)): continue
                r4,ox4,oy4,_=render(kind,w,size,ls,text)
                e,x,y=best_place(r4,ox4,oy4,cov)
                e/=norm
                if e<best[0]: best=(e,w,float(size),round(lf,3),x+rect[0]+x0c,y+rect[1]+y0c)
    e,w,size,ls,x,y=best
    col=img[rect[1]:rect[3],rect[0]:rect[2],:3]
    # ink colour: mean of pixels with coverage>0.9
    cv,_,_=coverage(img,rect)
    sel=cv>0.9
    ink=(col[sel].mean(axis=0) if sel.any() else col.reshape(-1,3).max(axis=0))
    return dict(text=text,font=kind,err=round(e,3),weight=w,size=size,ls=ls,x=round(x,2),baseline=round(y,2),ink=[int(v) for v in ink],bg=round(float(bg)),inkbox=[int(rect[0]+c0),int(rect[1]+r0),int(rect[0]+c1),int(rect[1]+r1)])
if __name__=='__main__':
    specs=json.load(open('textspec.json'))
    out={}
    for name in sys.argv[1:]:
        img=np.array(Image.open(f'{W}/{name}.png').convert('RGBA')).astype(float)
        t0=time.time(); res=[]
        for el in specs[name]:
            r=fit(img,el); res.append(r)
            print(f"{name} {r['text']!r:24} {r['font']:3} err {r['err']:.3f} w{r['weight']} {r['size']:.2f}px ls {r['ls']:+.1f} x {r['x']:.2f} base {r['baseline']:.2f} ink {r['ink']}",flush=True)
        out[name]=res
        json.dump({name:res},open(f'text_{name.replace("/","_")}.json','w'),indent=1)
        print(f'  ({time.time()-t0:.0f}s)')
