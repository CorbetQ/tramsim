from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json,sys
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'docs/rolling-stock-rebuild';DEST=ROOT/'.cache/stock-sheets';DEST.mkdir(exist_ok=True)
font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',15)
for e in json.load(open(ROOT/'data/rolling_stock/variants/index.json'))['entries']:
 if e['fictional'] or len(sys.argv)>1 and e['id'] not in sys.argv[1:]:continue
 if not e.get('references'):continue
 sheet=Image.new('RGB',(1280,920),'#15232c');d=ImageDraw.Draw(sheet);d.text((12,8),e['id']+' · '+e['name'],font=font,fill='white')
 for i,r in enumerate(e['references'][:4]):
  x=(i%2)*640;y=40+(i//2)*440;path=OUT/r['local_image']
  if not path.exists():continue
  img=Image.open(path).convert('RGB');img.thumbnail((628,370));sheet.paste(img,(x+(640-img.width)//2,y+(370-img.height)//2))
  d.text((x+8,y+375),str(i)+' · '+r['title'][5:74],font=font,fill='#d0e9ef')
  d.text((x+8,y+396),r.get('date','')[:25]+' · '+r.get('license',''),font=font,fill='#9cb7c5')
 sheet.save(DEST/(e['id']+'.jpg'),quality=90)
