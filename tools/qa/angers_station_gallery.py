#!/usr/bin/env python3
"""Package real-engine captures with source links and same-scale north-up IGN comparisons."""
from pathlib import Path
import json, math, html, urllib.request, urllib.parse, argparse
from PIL import Image, ImageDraw, ImageFont, ImageOps
ROOT=Path(__file__).resolve().parents[2]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--directory',type=Path,default=ROOT/'docs/angers-stations');a=ap.parse_args();out=a.directory;cache=ROOT/'.cache/station-references';models=json.loads((ROOT/'data/station_models/angers.json').read_text());network=json.loads((ROOT/'data/free/angers.json').read_text());origin=network['origin']
 manifest=json.loads((out/'after/manifest.json').read_text());before=json.loads((out/'before/manifest.json').read_text());assert len(manifest)==43 and len(before)==43,'Capture all sites before packaging'
 lookup={s['name']:s for s in models['stations']};lookup['Dépôt Raymond-Perron']=models['depot'];cards=[]
 def encode(path):
  target=path.with_suffix('.webp')
  if target.exists() and target.stat().st_mtime>=path.stat().st_mtime:return str(target.relative_to(out))
  Image.open(path).convert('RGB').save(target,'WEBP',quality=92,method=5)
  return str(target.relative_to(out))
 for directory in ['after','before','oblique']:
  for path in (out/directory).glob('*.png'):encode(path)
 def local(lat,lon):return (math.radians(lon-origin[1])*6371008.8*math.cos(math.radians(origin[0])),-math.radians(lat-origin[0])*6371008.8)
 (out/'ign').mkdir(exist_ok=True)
 for shot,old in zip(manifest,before):
  assert shot['name']==old['name'] and shot['center']==old['center'] and shot['camera_size']==old['camera_size'], 'Before/after camera poses differ: '+shot['name']
  name=shot['name'];profile=lookup[name];span=720 if name=='Dépôt Raymond-Perron' else 360
  if span==720:
   lat,lon=profile['lat'],profile['lon'];x=lon*20037508.342789244/180;y=math.log(math.tan(math.pi/4+math.radians(lat)/2))*6378137;d=span/2/math.cos(math.radians(lat))
   url='https://data.geopf.fr/wms-r/wms?'+urllib.parse.urlencode({'SERVICE':'WMS','VERSION':'1.3.0','REQUEST':'GetMap','LAYERS':'ORTHOIMAGERY.ORTHOPHOTOS','STYLES':'','CRS':'EPSG:3857','BBOX':','.join(map(str,[x-d,y-d,x+d,y+d])),'WIDTH':1024,'HEIGHT':1024,'FORMAT':'image/jpeg'})
   src=cache/'aerial/depot-720.jpg'
  else:
   ref=next(r for r in profile['aerial_references'] if r['span_m']==span);url=ref['url'];src=cache/'aerial'/(profile['id'].replace('saint-','st-',1)+'-360.jpg')
   # Canonical filename accents and Saint normalization are independent of internal model ids.
   import re,unicodedata
   slug=re.sub('[^a-z0-9]+','-',unicodedata.normalize('NFKD',name).encode('ascii','ignore').decode().lower()).strip('-');src=cache/'aerial'/(slug+'-360.jpg')
  if not src.exists():src.parent.mkdir(parents=True,exist_ok=True);src.write_bytes(urllib.request.urlopen(url,timeout=45).read())
  im=Image.open(src).convert('RGB');cx,cz=local(profile['lat'],profile['lon']);px=im.width*.5+(shot['center'][0]-cx)*im.width/span;pz=im.height*.5+(shot['center'][2]-cz)*im.height/span
  h=shot['camera_size']*im.height/span;w=h*4/3
  im=im.crop((round(px-w/2),round(pz-h/2),round(px+w/2),round(pz+h/2))).resize((1280,960),Image.Resampling.LANCZOS)
  draw=ImageDraw.Draw(im);draw.rectangle((0,916,1280,960),fill='#15202b');draw.text((16,929),'IGN BD ORTHO · Licence Ouverte 2.0 · consultation 14/11/2026 · date de prise de vue non fournie',fill='white',font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',15))
  ref_file='ign/'+Path(shot['file']).with_suffix('.webp').name;im.save(out/ref_file,'WEBP',quality=90,method=5)
  stem=Path(shot['file']).with_suffix('.webp').name;oblique='oblique/'+stem
  refs=profile.get('references',[])
  cards.append({'name':name,'after':'after/'+stem,'before':'before/'+stem,'ign':ref_file,'oblique':oblique if (out/oblique).exists() else None,'observations':profile.get('observations',[]),'references':refs,'ign_url':url})
 # Contact sheets: all 43 sites, one site per tile; no synthetic or retouched scenery.
 font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',24)
 for page in range(4):
  subset=cards[page*12:(page+1)*12];rows=math.ceil(len(subset)/3);sheet=Image.new('RGB',(1440,rows*400+90),'#14202b');draw=ImageDraw.Draw(sheet);draw.text((24,20),f'ANGERS · ARRÊTS ET DÉPÔT · {page+1}/4',font=font,fill='white')
  for i,card in enumerate(subset):
   x=i%3*480;y=i//3*400+75;im=Image.open(out/card['after']).resize((464,348),Image.Resampling.LANCZOS);sheet.paste(im,(x+8,y));draw.text((x+12,y+355),card['name'],font=font,fill='white')
  sheet.save(out/f'apercu-{page+1}.jpg',quality=92)
 gallery=[];md=['# Angers : 42 arrêts et dépôt Raymond-Perron','', '[Méthode et limites](README.md) · [Galerie interactive hors ligne](index.html)','', 'Captures réelles du jeu, vues verticales nord en haut. Les photographies de référence sont liées, les orthophotos IGN sont comparées à la même échelle.','']
 for i,card in enumerate(cards):
  esc=lambda s:html.escape(str(s),quote=True)
  refs=[]
  for j,ref in enumerate(card['references']):
   if isinstance(ref,str):refs.append(f'<a href="{esc(ref)}" target="_blank" rel="noopener">Référence {j+1}</a>');continue
   refs.append(f'<a href="{esc(ref["page"])}" target="_blank" rel="noopener">Photo {j+1} · {esc(str(ref.get("date",""))[:10])} · {esc(ref.get("author",""))}</a>')
  buttons=''.join(f'<button type="button" data-src="{esc(card[k])}">{label}</button>' for k,label in [('after','Après'),('before','Avant'),('ign','IGN')] )
  if card['oblique']:buttons+=f'<button type="button" data-src="{esc(card["oblique"])}">Vue oblique</button>'
  gallery.append(f'<article><h2>{i+1:02d} · {esc(card["name"])}</h2><nav>{buttons}</nav><a class="full" href="{esc(card["after"])}"><img loading="lazy" width="1280" height="960" src="{esc(card["after"])}" alt="{esc(card["name"])} : capture aérienne du jeu"></a><p>{" · ".join(esc(v) for v in card["observations"])}</p><details><summary>Références et dates</summary><p>{"<br>".join(refs)}</p><a href="{esc(card["ign_url"])}">Orthophoto IGN originale</a></details></article>')
  md+=['## '+card['name'],'',f'![{card["name"]} — après]({card["after"]})','',f'[Avant]({card["before"]}) · [Orthophoto IGN, même échelle]({card["ign"]})'+(f' · [Vue aérienne oblique]({card["oblique"]})' if card['oblique'] else ''),'']
 (out/'GALLERY.md').write_text('\n'.join(md)+'\n')
 (out/'index.html').write_text('''<!doctype html><html lang="fr"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Angers — 42 arrêts et dépôt</title><style>body{margin:0;background:#101a23;color:#e6e9df;font:16px/1.5 system-ui,sans-serif}header{padding:24px;max-width:900px;margin:auto}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,540px),1fr));gap:20px;padding:16px;max-width:1600px;margin:auto}article{background:#1b2b36;border:1px solid #384c56;border-radius:16px;overflow:hidden}h1{font-size:clamp(1.7rem,4vw,2.8rem)}h2,p,details,nav{margin:12px 18px}img{display:block;width:100%;height:auto}a{color:#9bdcce}nav{display:flex;flex-wrap:wrap;gap:8px}button{padding:12px 18px;min-height:46px;border:1px solid #57737e;background:#29444d;color:white;border-radius:9px;font:inherit;touch-action:pan-y;cursor:pointer}button[aria-pressed=true]{background:#437a75}summary{cursor:pointer;padding:8px 0}details{padding-bottom:12px}</style><header><h1>Angers, arrêt par arrêt.</h1><p>42 arrêts et le dépôt Raymond-Perron. Captures du moteur Godot : comparez l’ancien décor, les nouveaux modèles et les orthophotos IGN.</p><p>Reconstruction stylisée, empreintes documentées. Les détails de façade sont simplifiés. Bascule : une seule vue de rue spécifique vérifiée (2012) ; Saint-Gilles : références de 2021. Les dates des photos sont indiquées par site. La date de prise de vue des orthophotos n’est pas fournie par le WMS.</p><a href="README.md">Méthode, sources et limites</a></header><main>'''+''.join(gallery)+'''</main><script>document.querySelectorAll('article').forEach(a=>{a.querySelector('button').setAttribute('aria-pressed','true');a.querySelectorAll('button').forEach(b=>b.addEventListener('click',()=>{a.querySelector('img').src=b.dataset.src;a.querySelector('.full').href=b.dataset.src;a.querySelectorAll('button').forEach(x=>x.setAttribute('aria-pressed',String(x===b)));}));});</script></html>''')
 (out/'gallery-manifest.json').write_text(json.dumps(cards,ensure_ascii=False,indent=2)+'\n')
 print(f'{len(cards)} sites, 4 planches, {sum(c["oblique"] is not None for c in cards)} vues obliques')
if __name__=='__main__':main()
