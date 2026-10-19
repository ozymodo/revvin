"""Top-down map of the course with clearance checks.
   python3 tools/plot_track.py track.csv out.png"""
import sys, math
from PIL import Image, ImageDraw

RESERVED = [(-20,-290,40,310),(-72,-190,24,115),(-34,-50,18,20),(56,-224,48,82),(30,-168,20,118),
    (180,-390,40,262),(-234,-184,68,68),(-180,-162,44,24),(-130,48,180,34),(136,25,30,135),
    (216,25,30,215),(282,-132,46,172),(-312,140,282,125),(-362,283,335,34),(-137,-317,34,34)]
FEATURE_H = 22.0
AV = [-300,-150,0,150,300]

rows=[]; cps=[]; hoops=[]
for line in open(sys.argv[1]):
    if line.startswith('x,'): continue
    if line.startswith('#cp'): cps=[int(v) for v in line.strip().split(',')[1:] if v]; continue
    if line.startswith('#hoop'): hoops=[int(v) for v in line.strip().split(',')[1:] if v]; continue
    v=line.strip().split(',')
    rows.append(dict(x=float(v[0]),y=float(v[1]),z=float(v[2]),uy=float(v[4]),w=float(v[6]),f=int(v[7]),g=int(v[8]),d=float(v[9])))

S=1.4; O=410
def px(x,z): return ((x+O)*S,(z+O)*S)
im=Image.new('RGB',(int(820*S),int(820*S)),(30,34,30)); d=ImageDraw.Draw(im)
for a in AV:
    d.rectangle([px(a-14,-400),px(a+14,400)],fill=(55,55,58)); d.rectangle([px(-400,a-14),px(400,a+14)],fill=(55,55,58))
for r in RESERVED: d.rectangle([px(r[0],r[1]),px(r[0]+r[2],r[1]+r[3])],outline=(200,60,60),width=2)
d.rectangle([px(-400,-400),px(400,400)],outline=(200,200,200),width=2)
def col(y):
    t=max(0,min(1,y/45)); return (int(40+215*t),int(200-120*t),int(255-200*t))
for a,b in zip(rows,rows[1:]):
    if a['g']!=b['g']: continue
    d.line([px(a['x'],a['z']),px(b['x'],b['z'])],fill=col(a['y']),width=max(1,int(a['w']*S*0.8)))
# clearance
bad=0
n=len(rows)
for i in range(0,n,2):
    a=rows[i]
    for j in range(i+2,n,2):
        b=rows[j]
        if abs(a['d']-b['d'])<30 and a['g']==b['g']: continue
        if abs(i-j) < 40 or (i < 60 and j > n-60): continue
        h=math.hypot(a['x']-b['x'],a['z']-b['z'])
        if h < (a['w']+b['w'])/2+3 and abs(a['y']-b['y'])<9 and a['uy']>0.5 and b['uy']>0.5:
            bad+=1; d.ellipse([px(a['x']-3,a['z']-3),px(a['x']+3,a['z']+3)],outline=(255,255,0),width=2)
            if bad<12: print("CLEARANCE %d(%.0f,%.0f,%.0f) vs %d(%.0f,%.0f,%.0f)"%(i,a['x'],a['y'],a['z'],j,b['x'],b['y'],b['z']))
feat=0
for i,a in enumerate(rows):
    if a['y']>FEATURE_H: continue
    for r in RESERVED[:-2]:
        if r[0]-a['w']/2<a['x']<r[0]+r[2]+a['w']/2 and r[1]-a['w']/2<a['z']<r[1]+r[3]+a['w']/2:
            feat+=1
            if feat<8: print("FEATURE overlap at",i,round(a['x']),round(a['y']),round(a['z']),r)
            d.ellipse([px(a['x']-2,a['z']-2),px(a['x']+2,a['z']+2)],fill=(255,0,0))
for i,a in enumerate(rows):
    if 60<i<n-120 and a['y']<6.5 and any(abs(a['x']-v)<15 or abs(a['z']-v)<15 for v in AV):
        print("LOW over avenue",i,round(a['x']),round(a['y']),round(a['z'])); break
oob=[i for i,a in enumerate(rows) if abs(a['x'])+a['w']/2>392 or abs(a['z'])+a['w']/2>392]
if oob: print("OUT OF BOUNDS samples", oob[0], "...", len(oob))
for k,c in enumerate(cps):
    a=rows[c]; d.text(px(a['x']+6,a['z']),"CP%d"%k,fill=(255,255,255))
for h in hoops:
    a=rows[h]; d.ellipse([px(a['x']-4,a['z']-4),px(a['x']+4,a['z']+4)],outline=(80,255,120),width=2)
for k in range(0,n,100):
    a=rows[k]; d.text(px(a['x']+5,a['z']+5),"%d:%.0fm"%(int(a['d']),a['y']),fill=(230,230,140))
im.save(sys.argv[2])
print("clearance hits",bad,"feature hits",feat,"len",rows[-1]['d'],"min y",min(r['y'] for r in rows),"max y",max(r['y'] for r in rows))
