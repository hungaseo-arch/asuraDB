import sys,re,io,base64,html
import xml.etree.ElementTree as ET
from PIL import Image
SRC,OUT=sys.argv[1],sys.argv[2]
NOPHOTO = '--no-photo' in sys.argv
DATE = sys.argv[3] if len(sys.argv)>3 and not sys.argv[3].startswith('--') else '2026.10.09'
r=ET.parse(SRC).getroot()
ROOT='dNxyNK7c78bLwvsdeMH5-11'
SKIP={'FPA1dWAOuhWkTVOTVO7y-88','L3x8Y9yKqyoCHXXfjp1h-11','L3x8Y9yKqyoCHXXfjp1h-18',
      'FPA1dWAOuhWkTVOTVO7y-121','L3x8Y9yKqyoCHXXfjp1h-12','L3x8Y9yKqyoCHXXfjp1h-19'}
cells={};order=[]
for el in r.iter():
    if el.tag in('object','UserObject'):
        c=el.find('mxCell'); cid=el.get('id'); attrs=dict(el.attrib)
    elif el.tag=='mxCell' and el.get('id'):
        if el.get('id') in cells: continue
        c=el; cid=el.get('id'); attrs={'value':el.get('value','')}
    else: continue
    g=c.find('mxGeometry')
    geo={k:float(g.get(k) or 0) for k in('x','y','width','height')} if g is not None else {}
    pts={}
    if g is not None:
        arr=g.find('Array'); pts['points']=[(float(p.get('x')),float(p.get('y'))) for p in arr] if arr is not None else []
        for p in g.findall('mxPoint'): pts[p.get('as')]=(float(p.get('x') or 0),float(p.get('y') or 0))
    cells[cid]=dict(id=cid,parent=c.get('parent'),style=c.get('style') or '',attrs=attrs,geo=geo,pts=pts,
                    v=c.get('vertex')=='1',e=c.get('edge')=='1',src=c.get('source'),tgt=c.get('target'))
    order.append(cid)
def off(cid):
    x=y=0;cur=cells[cid]['parent']
    while cur and cur!=ROOT and cur in cells:
        g=cells[cur]['geo'];x+=g.get('x',0);y+=g.get('y',0);cur=cells[cur]['parent']
    return x,y
def box(cid):
    ox,oy=off(cid);g=cells[cid]['geo'];return ox+g['x'],oy+g['y'],g['width'],g['height']
def sty(st,k):
    m=re.search(r'(?:^|;)'+k+r'=([^;]*)',st);return m.group(1) if m else None
def esc(s): return html.escape(s,quote=True)
def totext(s):
    s=re.sub(r'<br\s*/?>|</?div[^>]*>|</p>','\n',s); s=re.sub(r'<[^>]+>','',s); s=html.unescape(s).replace('\xa0',' ')
    return [l.strip() for l in s.split('\n') if l.strip()]

PAD=30
els_shapes=[];els_imgs=[];els_edges=[];els_text=[]
# ---- people cards
NAMEFIX={'DTalTDUhhLwPt7BSDAFs-2':('COO','KIM JH / 김재헌'),'PaNGceYCdUrdy6z3NK1T-49':('Marketing','Kevin'),
         'L3x8Y9yKqyoCHXXfjp1h-21':('Sales Planning','Lisa'),'dNxyNK7c78bLwvsdeMH5-14':('SALES','Eri')}
KOR={'LpsiYqBvEntWObQJSyo5-7':' / 송주영','Sl_ssonm7MfwAosNdEt_-3':' / 김용덕'}
COUNT={}
for cid in order:
    d=cells[cid]
    if not d['v'] or cid in SKIP: continue
    st=d['style']
    if st.startswith('label;'):
        x,y,w,h=box(cid)
        lab=d['attrs'].get('label','')
        lab=lab.replace('%position%',d['attrs'].get('position','')).replace('%name%',d['attrs'].get('name',''))
        lines_=totext(lab)
        cnt=next((l for l in lines_ if re.fullmatch(r'\d+인',l)),None)
        rest=[l for l in lines_ if l!=cnt]
        pos,name=(rest+['',''])[:2]
        fill=sty(st,'fillColor') or '#FFFFFF'; fill='#FFFFFF' if fill in('default','none') else fill
        stroke=sty(st,'strokeColor') or '#000000'
        shadow=sty(st,'shadow')=='1' or (cells.get(d['parent'],{}).get('style','').find('shadow=1')>=0)
        els_shapes.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}" stroke="{stroke}" stroke-width="1"{" filter=\"url(#sh)\"" if shadow else ""}/>')
        # text area right of photo
        tx=x+75+(w-75)/2
        lines=[(pos,'pos'),(name,'name')]+([(cnt,'cnt')] if cnt else [])
        lh=16; y0=y+h/2-(len(lines)-1)*lh/2
        t=[f'<tspan x="{tx}" y="{y0+i*lh}" class="{c}">{esc(s)}</tspan>' for i,(s,c) in enumerate(lines)]
        els_text.append(f'<text text-anchor="middle" dominant-baseline="middle">{"".join(t)}</text>')
        COUNT[cid]=dict(x=x,y=y,w=w,h=h,name=name)
# ---- images
def photo_uri(st,target_w,target_h):
    m=re.search(r'image=data:image/([a-z]+),([^;]+)',st)
    im=Image.open(io.BytesIO(base64.b64decode(m.group(2)+'=='))).convert('RGB')
    im=im.resize((int(target_w*3),int(target_h*3)),Image.LANCZOS)
    b=io.BytesIO(); im.save(b,'JPEG',quality=82); return 'data:image/jpeg;base64,'+base64.b64encode(b.getvalue()).decode()
clips=[];has_img=set()
for cid in order:
    d=cells[cid]
    if not d['v'] or cid in SKIP or 'image=data' not in d['style']: continue
    x,y,w,h=box(cid); st=d['style']
    ins=sty(st,'clipPath')
    if 'O7y-73' in cid: ins='inset(8% 22% 22% 10% round 50%)'
    if ins:
        v=[float(a.strip('%'))/100 for a in re.findall(r'[\d.]+%',ins)[:4]]
        t,rt,b,l=v
    else: t=rt=b=l=0.0
    cx=x+w*(l+(1-l-rt)/2); cy=y+h*(t+(1-t-b)/2); rx=w*(1-l-rt)/2; ry=h*(1-t-b)/2
    if not ins: rx=ry=min(w,h)/2
    k=f'c{len(clips)}'; clips.append(f'<clipPath id="{k}"><ellipse cx="{cx:.2f}" cy="{cy:.2f}" rx="{rx:.2f}" ry="{ry:.2f}"/></clipPath>')
    if NOPHOTO: continue
    els_imgs.append(f'<image href="{photo_uri(st,w,h)}" x="{x:.2f}" y="{y:.2f}" width="{w:.2f}" height="{h:.2f}" preserveAspectRatio="none" clip-path="url(#{k})"/>')
    for pid,p in COUNT.items():
        if p['x']<=x+w/2<=p['x']+p['w'] and p['y']<=y+h/2<=p['y']+p['h']: has_img.add(pid)
# avatar placeholder for cards without photo
for pid,p in COUNT.items():
    if pid in has_img: continue
    cx,cy,rr=p['x']+39,p['y']+p['h']/2,29
    els_imgs.append(f'<g class="avatar"><circle cx="{cx}" cy="{cy}" r="{rr}" fill="#CFD8DC"/><circle cx="{cx}" cy="{cy-7}" r="10" fill="#FFFFFF"/><path d="M{cx-17} {cy+19} a17 14 0 0 1 34 0z" fill="#FFFFFF"/></g>')
# ---- edges
def center_bottom(cid):
    x,y,w,h=box(cid); return x+w/2,y+h
def center_top(cid):
    x,y,w,h=box(cid); return x+w/2,y
for cid in order:
    d=cells[cid]
    if not d['e']: continue
    ox,oy=off(cid); pts=d['pts']
    S=center_bottom(d['src']) if d['src'] and d['src'] in cells else (pts.get('sourcePoint') and (ox+pts['sourcePoint'][0],oy+pts['sourcePoint'][1]))
    T=center_top(d['tgt']) if d['tgt'] and d['tgt'] in cells else (pts.get('targetPoint') and (ox+pts['targetPoint'][0],oy+pts['targetPoint'][1]))
    if not S or not T: continue
    mids=[(ox+a,oy+b) for a,b in pts.get('points',[])]
    if abs(S[0]-T[0])<5: path=[S,(S[0],T[1])]
    elif mids and len(mids)>=2: path=[S]+[(S[0],mids[0][1])]+[(T[0],mids[-1][1])]+[T]
    else:
        my=mids[0][1] if mids else (S[1]+T[1])/2
        if not (min(S[1],T[1])<my<max(S[1],T[1])): my=(S[1]+T[1])/2
        path=[S,(S[0],my),(T[0],my),T]
    dstr='M'+' L'.join(f'{a:.1f} {b:.1f}' for a,b in path)
    els_edges.append(f'<path d="{dstr}" class="edge" marker-end="url(#arr)"/>')
# ---- 인원수 / 범례
x,y,w,h=box('hGdr-jcP9na1rva3o8ef-31')
sl=totext(cells['hGdr-jcP9na1rva3o8ef-31']['attrs'].get('label') or cells['hGdr-jcP9na1rva3o8ef-31']['attrs'].get('value',''))
SUMMARY=sl
def kv(line):
    k,_,v=line.partition(':'); return f'<tspan font-weight="700">{esc(k)}:</tspan> <tspan font-style="italic">{esc(v.strip())}</tspan>'
ys=[66,90,126]
body=''.join(f'<text x="{x+20}" y="{y+yy}" class="sum">{kv(l)}</text>' for l,yy in zip(sl[1:],ys))
els_text.append(f'<g class="summary"><text x="{x+20}" y="{y+30}" class="sum-h">{esc(sl[0])}</text>{body}</g>')
lx,ly,_,_=box('hGdr-jcP9na1rva3o8ef-40')
leg=f'''<g class="legend" transform="translate({lx},{ly})">
<text x="0" y="20" class="leg-h">범례:</text>
<rect x="0" y="55" width="69.5" height="33" fill="#d5e8d4" stroke="#82b366"/><text x="81" y="77" class="leg">과장</text>
<rect x="0" y="118" width="69.5" height="33" fill="#fff2cc" stroke="#d6b656"/><text x="81" y="140" class="leg">팀장</text>
<rect x="0" y="186" width="69.5" height="33" fill="#fff2cc" stroke="#d6b656"/><text x="35" y="208" text-anchor="middle" class="leg">X인</text>
<text x="81" y="208" class="leg">각 팀장이 담당하는 인원수</text></g>'''
W,H=cells[ROOT]['geo']['width'],cells[ROOT]['geo']['height']
svg=f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="{-PAD} {-PAD} {W+2*PAD} {H+2*PAD}" id="org" role="img" aria-label="PT ASCENDO 조직도 2026">
<defs>
<filter id="sh" x="-10%" y="-10%" width="130%" height="140%"><feDropShadow dx="2" dy="3" stdDeviation="1.5" flood-color="#000" flood-opacity="0.25"/></filter>
<marker id="arr" viewBox="0 0 10 10" refX="10" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 1 L10 5 L0 9z" fill="#000"/></marker>
{''.join(clips)}
</defs>
<rect x="0" y="0" width="{W}" height="{H}" fill="#FFFFFF" stroke="#000" stroke-width="1"/>
<rect x="0" y="0" width="{W}" height="20" fill="#FFFFFF" stroke="#000" stroke-width="1"/>
<text x="{W/2}" y="11" text-anchor="middle" dominant-baseline="middle" class="lane">조직도</text>
<g transform="translate(0,0)">{''.join(els_edges)}{''.join(els_shapes)}{''.join(els_imgs)}{''.join(els_text)}{leg}</g>
</svg>'''
import re as _re
def _n(pat):
    m=_re.search(pat,' '.join(SUMMARY)); return m.group(1) if m else '?'
META="총 "+_n(r"총 인원수: *(\d+)")+"인(한국인 "+_n(r"한국인[^:]*: *(\d+)")+"인 · 현지인 "+_n(r"현지[^:]*: *(\d+)")+"인)"
page=f'''<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>아센도 조직도 · 2026</title>
<style>
  :root{{ --bg:#F0F0F0; --card:#FFFFFF; --soft-blue:#E3F2FD; --ink:#37474F; --ink2:#546E7A; --border:#CFD8DC; }}
  *{{box-sizing:border-box;}}
  html,body{{margin:0; background:var(--bg); color:var(--ink);
    font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","Malgun Gothic","Apple SD Gothic Neo",sans-serif;}}
  .bar{{display:flex; flex-wrap:wrap; gap:10px 16px; align-items:center; justify-content:space-between;
    padding:14px 18px; background:var(--soft-blue); border-bottom:1px solid #C5E1F7;}}
  .bar h1{{margin:0; font-size:18px; font-weight:750;}}
  .bar .meta{{font-size:12px; color:var(--ink2);}}
  .zoom{{display:flex; gap:6px;}}
  .zoom button{{font:inherit; font-size:12px; padding:5px 10px; border:1px solid var(--border); background:#fff;
    color:var(--ink); border-radius:6px; cursor:pointer;}}
  .zoom button:hover{{background:#ECEFF1;}}
  .stage{{overflow:auto; padding:16px;}}
  #org{{display:block; background:#fff; height:auto; max-width:none;}}
  #org text{{font-family:Helvetica,Arial,"Malgun Gothic","Apple SD Gothic Neo",sans-serif; font-size:12px; fill:#000;}}
  #org .pos{{font-style:italic; fill:#808080;}}
  #org .name{{fill:#1A1A1A;}}
  #org .cnt{{fill:#1A1A1A; font-style:italic;}}
  #org .lane{{font-weight:700;}}
  #org .edge{{fill:none; stroke:#000; stroke-width:1;}}
  #org .sum-h{{font-size:34px; font-weight:700;}}
  #org .sum{{font-size:20px;}}
  #org .leg-h,#org .leg{{font-size:12px;}}
  @media print{{ .bar .zoom{{display:none;}} .stage{{overflow:visible; padding:0;}} #org{{width:100% !important;}} }}
</style>
</head>
<body>
<div class="bar">
  <div><h1>PT ASCENDO INTERNASIONAL 조직도 · 2026</h1>
  <div class="meta">기준일 {DATE} · {META} · 원본 : 조직도_아센도_20261009.drawio</div></div>
  <div class="zoom"><button data-z="fit">화면 맞춤</button><button data-z="0.75">75%</button><button data-z="1">100%</button></div>
</div>
<div class="stage">{svg}</div>
<script>
(function(){{
  var svg=document.getElementById('org'), stage=svg.parentNode, VW={W+2*PAD}, mode='fit';
  function apply(){{
    var avail=stage.clientWidth-32;
    var w = mode==='fit' ? Math.max(avail, 900) : VW*mode;
    svg.style.width=w+'px';
  }}
  document.querySelectorAll('.zoom button').forEach(function(b){{
    b.addEventListener('click',function(){{ mode = b.dataset.z==='fit' ? 'fit' : parseFloat(b.dataset.z); apply(); }});
  }});
  window.addEventListener('resize',function(){{ if(mode==='fit') apply(); }});
  apply();
}})();
</script>
</body>
</html>'''
open(OUT,'w',encoding='utf-8').write(page)
print(OUT, len(page), SUMMARY)
