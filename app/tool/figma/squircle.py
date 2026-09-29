import numpy as np, math
from PIL import Image, ImageDraw
W="C:/Users/Armaan khan/Desktop/Hobbies/fitness-tracker/app/Widget"
def params(R, s, budget):
    p=(1+s)*R
    maxs=budget/R-1; s=min(s,maxs); p=min(p,budget)
    arc=90*(1-s)
    arcLen=math.sin(math.radians(arc/2))*R*math.sqrt(2)
    alpha=(90-arc)/2
    p34=R*math.tan(math.radians(alpha/2))
    beta=45*s
    c=p34*math.cos(math.radians(beta))
    d=c*math.tan(math.radians(beta))
    b=(p-arcLen-c-d)/3
    a=2*b
    return a,b,c,d,p,arcLen
def bez(p0,p1,p2,p3,n=40):
    t=np.linspace(0,1,n)[:,None]
    return ((1-t)**3)*p0+3*((1-t)**2)*t*p1+3*(1-t)*t*t*p2+t**3*p3
def corner_pts(R,s,budget):
    # top-right corner in local coords, origin at top-right corner (x leftwards negative), y down
    a,b,c,d,p,arcLen=params(R,s,budget)
    # start at (-p,0)
    P0=np.array([-p,0.]); 
    c1=P0+[a,0]; c2=P0+[a+b,0]; e=P0+[a+b+c,d]
    pts=[bez(P0,c1,c2,e)]
    # arc from e to e+(arcLen,arcLen), radius R, sweep clockwise
    s1=e; s2=e+np.array([arcLen,arcLen])
    # find circle center: arc of radius R between s1 and s2, center to the lower-left
    mid=(s1+s2)/2; dvec=s2-s1; L=np.linalg.norm(dvec); h=math.sqrt(max(R*R-(L/2)**2,0))
    perp=np.array([-dvec[1],dvec[0]])/L  # rotate +90
    cen=mid+perp*h
    # choose center such that it's at lower-left (x smaller, y larger)
    if cen[1]<mid[1]: cen=mid-perp*h
    a1=math.atan2(s1[1]-cen[1],s1[0]-cen[0]); a2=math.atan2(s2[1]-cen[1],s2[0]-cen[0])
    ang=np.linspace(a1,a2,40)
    pts.append(np.stack([cen[0]+R*np.cos(ang),cen[1]+R*np.sin(ang)],1))
    # last bezier: from s2, c d, (b+c) d?  in figma-squircle: c ${d} ${c} ${d} ${b + c} ${d} ${a + b + c} relative -> ctrl1 (d,c) ctrl2 (d,b+c) end (d,a+b+c)
    P=s2; pts.append(bez(P,P+[d,c],P+[d,b+c],P+[d,a+b+c]))
    return np.concatenate(pts)
def raster(R,s,w,h,ss=8):
    # full rect mask with 4 corners, ss supersampling
    pts=corner_pts(R,s,min(w,h)/2)  # top-right corner relative (0,0)=top-right
    TR=[(w+x,y) for x,y in pts]
    # build by mirroring TR: corner curve monotone from (w-p,0) to (w,p)
    TRc=TR
    BRc=[(X, h-Y) for X,Y in reversed(TRc)]
    BLc=[(w-X, h-Y) for X,Y in TRc]
    TLc=[(w-X, Y) for X,Y in reversed(TRc)]
    poly=TRc+BRc+BLc+TLc
    img=Image.new('L',(w*ss,h*ss),0)
    ImageDraw.Draw(img).polygon([(x*ss,y*ss) for x,y in poly],fill=255)
    a=np.array(img).astype(float)/255
    return a.reshape(h,ss,w,ss).mean(axis=(1,3))
if __name__=='__main__':
    tgt=np.array(Image.open(f'{W}/Small/8.png').convert('RGBA')).astype(float)[:,:,3]/255
    h,w=tgt.shape
    best=[]
    for R in np.arange(18,34.01,0.5):
        for s in np.arange(0,1.001,0.05):
            m=raster(R,s,w,h,ss=4)
            e=np.abs(m-tgt)[:48,:48].sum()
            best.append((e,R,s))
    best.sort(); print(best[:8])
    e,R,s=best[0]
    # refine
    b2=[]
    for R2 in np.arange(R-0.5,R+0.51,0.1):
        for s2 in np.arange(max(0,s-0.05),min(1,s+0.05)+1e-9,0.01):
            m=raster(R2,s2,w,h,ss=8)
            b2.append((np.abs(m-tgt)[:48,:48].sum(),round(R2,2),round(s2,3)))
    b2.sort(); print(b2[:5])
    e,R,s=b2[0]
    m=raster(R,s,w,h,ss=8)
    print('max abs err', np.abs(m-tgt).max(), 'sum', np.abs(m-tgt).sum())
    for f in ['Large/5.png','Medium/5.png','Small/11.png']:
        t=np.array(Image.open(f'{W}/{f}').convert('RGBA')).astype(float)[:,:,3]/255
        hh,ww=t.shape; mm=raster(R,s,ww,hh,ss=8)
        print(f, 'sum err', np.abs(mm-t).sum(), 'max', np.abs(mm-t).max())
