# Draws the installer window artwork: Resources/dmg/background.png and background@2x.png.
# Run from the repository root: python3 scripts/dmg-background.py  (needs Pillow and the Inter font)
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math
S=2; W,H=640,420; w,h=W*S,H*S
ICON=(170,205); APPS=(470,205)

# Navy gradient, like the logo tile
top=(12,24,43); bot=(23,37,62)
img=Image.new("RGB",(w,h)); px=img.load()
for y in range(h):
    t=y/(h-1); c=tuple(int(top[i]+(bot[i]-top[i])*t) for i in range(3))
    for x in range(w): px[x,y]=c

def layer(): return Image.new("RGBA",(w,h),(0,0,0,0))
cx,cy=ICON[0]*S,ICON[1]*S

# Soft cyan glow behind TESS
g=layer(); d=ImageDraw.Draw(g)
d.ellipse([cx-150*S,cy-150*S,cx+150*S,cy+150*S],fill=(70,215,255,70))
g=g.filter(ImageFilter.GaussianBlur(70*S)); img.paste(g,(0,0),g)

# HUD rings and ticks around the TESS icon, as in the logo
r=layer(); d=ImageDraw.Draw(r)
def arc(rad,a0,a1,col,wid):
    d.arc([cx-rad*S,cy-rad*S,cx+rad*S,cy+rad*S],a0,a1,fill=col,width=int(wid*S))
arc(92,0,360,(70,215,255,28),1)
arc(92,200,300,(70,215,255,110),2.5)
arc(92,20,95,(70,215,255,90),2.5)
arc(122,0,360,(70,215,255,18),1)
arc(122,240,330,(70,215,255,70),2)
arc(122,60,140,(70,215,255,55),2)
for i in range(72):
    a=math.radians(i*5); long=i%6==0
    r0=130 if long else 133; r1=140
    col=(70,215,255,70 if long else 38)
    d.line([(cx+math.cos(a)*r0*S,cy+math.sin(a)*r0*S),(cx+math.cos(a)*r1*S,cy+math.sin(a)*r1*S)],fill=col,width=int((1.6 if long else 1.1)*S))
# Fade the rings out towards the title and the footer text
fade=Image.new("L",(w,h),255); fp=fade.load()
for yy in range(h):
    yv=yy/S
    k=min(1.0,max(0.0,(yv-98)/40))*min(1.0,max(0.0,(336-yv)/30))
    for xx in range(w): fp[xx,yy]=int(255*k)
alpha=r.getchannel("A"); from PIL import ImageChops
r.putalpha(ImageChops.multiply(alpha,fade))
img.paste(r,(0,0),r)

# Faint ring behind Applications too, for balance
r=layer(); d=ImageDraw.Draw(r); ax,ay=APPS[0]*S,APPS[1]*S
d.ellipse([ax-92*S,ay-92*S,ax+92*S,ay+92*S],outline=(70,215,255,22),width=int(1*S))
img.paste(r,(0,0),r)

# Arrow: three glowing chevrons that brighten towards Applications, HUD-style
a=layer(); d=ImageDraw.Draw(a)
y=205*S
for cxv,op in [(310,0.30),(336,0.62),(362,1.0)]:
    cxp=cxv*S; hgt=15*S; wid=10*S
    col=(70,215,255,int(255*op))
    pts=[(cxp-wid,y-hgt),(cxp,y),(cxp-wid,y+hgt)]
    d.line(pts,fill=col,width=int(3.6*S),joint="curve")
    for px_,py_ in pts:
        r_=1.8*S; d.ellipse([px_-r_,py_-r_,px_+r_,py_+r_],fill=col)
glow=a.filter(ImageFilter.GaussianBlur(6*S))
img.paste(glow,(0,0),glow); img.paste(glow,(0,0),glow); img.paste(a,(0,0),a)

# Name pills: dark, so Finder (which judges the brightness right under each name) draws both names in white.
p_=layer(); pd=ImageDraw.Draw(p_)
# Centres measured from Finder on macOS 27: 13-point names sit 74 points below the icon centre
# (and half a point left). Widths = text width + 16 points each side.
for (cx_,cy_),wd in [((169.0,279.0),62),((469.0,279.0),106)]:
    pd.rounded_rectangle([(cx_-wd/2)*S,(cy_-11)*S,(cx_+wd/2)*S,(cy_+11)*S],radius=11*S,
                         fill=(7,14,27,235),outline=(70,215,255,70),width=S)
img.paste(p_,(0,0),p_)

d=ImageDraw.Draw(img)
import os
F=os.environ.get("INTER_DIR","/usr/share/fonts/opentype/inter/")
title=ImageFont.truetype(F+"Inter-SemiBold.otf",26*S)
sub=ImageFont.truetype(F+"Inter-Regular.otf",14*S)
small=ImageFont.truetype(F+"Inter-Regular.otf",11.5*S)
smallb=ImageFont.truetype(F+"Inter-SemiBold.otf",11.5*S)
def center(t,f,y,fill):
    tw=d.textlength(t,font=f); d.text(((w-tw)/2,y),t,font=f,fill=fill)
center("Install TESS",title,40*S,(240,248,255))
center("Drag TESS onto the Applications folder",sub,80*S,(150,180,205))
y=350*S
center("First launch: if macOS says it can’t verify TESS, open",small,y,(120,145,170))
parts=[("System Settings › Privacy & Security",smallb),(" and click ",small),("Open Anyway",smallb)]
tw=sum(d.textlength(t,font=f) for t,f in parts); x=(w-tw)/2
for t,f in parts:
    d.text((x,y+17*S),t,font=f,fill=(185,210,230) if f==smallb else (120,145,170)); x+=d.textlength(t,font=f)

out="Resources/dmg/"
img.save(out+"background@2x.png"); img.resize((W,H),Image.LANCZOS).save(out+"background.png")

