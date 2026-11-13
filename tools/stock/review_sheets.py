from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'docs/rolling-stock-rebuild';CACHE=ROOT/'.cache/stock-sheets'
selected={'angers__citadis_x05':2,'bordeaux__citadis_302':1,'montpellier__citadis_x01':1,'montpellier__citadis_402__3':1,'montpellier__urbos__5':2,'lyon__citadis_402':2,'lyon__citadis_402_2020':1,'lyon__citadis_dualis':2,'saintetienne__vevey_ste1':1,'idf__tfs__t1':1,'idf__translohr__t6':2,'annemasse__cityrunner_tpg':1,'leymen__tango_blt':1}
font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',14)
entries=[e for e in json.load(open(ROOT/'data/rolling_stock/variants/index.json'))['entries'] if not e['fictional']]
records={}
for e in entries:
 i=selected.get(e['id'],0);records[e['id']]={'selected':min(i,max(0,len(e['references'])-1)),'status':'pending_visual_review','note':''}
for k in range(0,len(entries),9):
 sheet=Image.new('RGB',(1500,1020),'#11202a');d=ImageDraw.Draw(sheet)
 for i,e in enumerate(entries[k:k+9]):
  x=i%3*500;y=i//3*340;r=e['references'][records[e['id']]['selected']] if e['references'] else {};p=OUT/r.get('local_image','no-image')
  if r.get('external_only'):p=ROOT/'.cache/stock-primary'/({'lille__citadis_x05':'lille-real.jpg','lemans__citadis_402':'lemans-real.jpg','toulouse__citadis_305':'toulouse-real.jpg'}.get(e['id'],'no-image'))
  if p.exists():
   im=Image.open(p);im.thumbnail((490,275));sheet.paste(im,(x+(500-im.width)//2,y+(280-im.height)//2))
  d.text((x+6,y+285),e['id'],fill='white',font=font);d.text((x+6,y+307),r.get('title','PHOTO ABSENTE')[5:64],fill='#b8d4df',font=font)
 sheet.save(CACHE/f'review-{k//9}.jpg',quality=88)
if not (OUT/'reference-review.json').exists():(OUT/'reference-review.json').write_text(json.dumps(records,ensure_ascii=False,indent=2)+'\n')
