#!/usr/bin/env python3
"""Galerie de contrôle, crédits photographiques et vignettes du catalogue.
Les captures sont réencodées sans perte ; aucune retouche du rendu.
"""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json,html,hashlib,shutil
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'docs/rolling-stock-rebuild';THUMBS=ROOT/'data/rolling_stock/thumbs/variants'
def esc(value):return html.escape(str(value),quote=True)
def compact(phase):
 path=OUT/phase/'captures.json';shots=json.loads(path.read_text())
 for shot in shots:
  image=OUT/shot['image'];target=image.with_suffix('.webp')
  if image.suffix=='.png':
   original=Image.open(image).convert('RGBA');original.save(target,lossless=True,method=4)
   assert Image.open(target).convert('RGBA').tobytes()==original.tobytes()
   shot['pixel_sha256']=hashlib.sha256(original.tobytes()).hexdigest();shot['resolution']=list(original.size);image.unlink()
  shot['image']=str(target.relative_to(OUT));shot['encoding']='WebP sans perte ; pixels identiques à la capture PNG'
 path.write_text(json.dumps(shots,ensure_ascii=False,indent=2)+'\n')
 return {s['id']+'-'+s['angle']:s for s in shots}
def main():
 data=json.load(open(ROOT/'data/rolling_stock/variants/index.json'));entries=data['entries'];reviews=json.load(open(OUT/'reference-review.json'));patches=json.load(open(ROOT/'data/rolling_stock/variants/technical_overrides.json'))
 before=compact('before');after=compact('after');THUMBS.mkdir(exist_ok=True,parents=True)
 for e in entries:
  patch=patches.get(e['id'],{})
  for key in ['technical','geometry']:e[key].update(patch.get(key,{}))
  for key in patch.get('technical',{}):
   if key in e['estimated']:e['estimated'].remove(key)
  e['before']={a:before.get(e['id']+'-'+a,{}).get('image') for a in ['front','threequarter']}
  e['after']={a:after[e['id']+'-'+a]['image'] for a in ['front','threequarter']}
  index=0 if e['fictional'] else reviews[e['id']]['selected'];e['reference']=e['references'][index]
  e['reference_note']=e.get('fiction_note','Inspiration réelle — concept fictif.') if e['fictional'] else reviews[e['id']]['note']
  e['reference_image']=e['reference'].get('local_image') or e['reference']['image_url']
  e['triangles']=after[e['id']+'-front']['triangles']
  im=Image.open(OUT/e['after']['threequarter']).convert('RGB');im.resize((512,288),Image.Resampling.LANCZOS).save(THUMBS/(e['id']+'.png'),optimize=True)
 # Crédits de chaque photographie redistribuée, y compris les références complémentaires.
 credits={}
 for e in entries:
  for ref in e['references']:
   key=ref.get('local_image')
   if key:credits[key]=ref
 text=['# Crédits des photographies','', 'Miniatures documentaires redimensionnées depuis les fichiers des auteurs. Les captures du jeu sont distinctes des photographies. Les trois références externes restent hébergées sur leurs sites sources.','']
 for path,ref in sorted(credits.items()):
  text+=['- ['+ref['title']+']('+ref['url']+') — '+ref['author']+' — ['+ref['license']+']('+ref.get('license_url','https://commons.wikimedia.org/wiki/Commons:Licensing')+') ; fichier `'+path+'`.']
 (OUT/'PHOTO-CREDITS.md').write_text('\n'.join(text)+'\n')
 dataset={'entries':entries,'baseline':'9889556578c62f89ef77246a6f2c030e093c4e01','method':'Anciennes coques conservées ; variantes, faces avant et livrées corrigées. Géométries et motifs stylisés, certaines caractéristiques estimées.','real_count':sum(not e['fictional'] for e in entries),'concept_count':sum(e['fictional'] for e in entries),'city_count':len(set(e['network'] for e in entries)),'compared':sum(bool(e['before']['front']) for e in entries),'max_triangles':max(e['triangles'] for e in entries)}
 (OUT/'gallery-data.json').write_text(json.dumps(dataset,ensure_ascii=False,indent=2)+'\n')
 payload=json.dumps(dataset,ensure_ascii=False).replace('<','\\u003c')
 page=Path(__file__).with_name('gallery_template.html').read_text().replace('__DATA__',payload)
 (OUT/'index.html').write_text(page)
 md=['# Rames : base historique, variantes et livrées','',f"**{dataset['real_count']} entrées réelles et {dataset['concept_count']} concepts**, {dataset['city_count']} villes d’origine, y compris les réseaux transfrontaliers. Ce nombre décrit le catalogue, pas le nombre de cartes disponibles.",'','Les carrosseries, articulations et animations précédentes sont conservées. Les corrections portent sur les profils de cabine, les optiques, les girouettes, les livrées et les variantes de caisses. Les motifs complexes et plusieurs caractéristiques physiques restent estimés : aucune fidélité industrielle parfaite n’est revendiquée.','','[Galerie interactive : face avant et rame entière](index.html) · [Crédits photographiques](PHOTO-CREDITS.md) · [Recherche de modèles 3D](ASSET-ACQUISITION.md)','','Le mode libre conserve la livrée d’origine et filtre le guidage et les alimentations embarquées. L’APS n’est jamais ajouté automatiquement à un véhicule. Les rames identiques affectées à plusieurs lignes sont regroupées ; leurs anciens identifiants restent reconnus.','','Les concepts sont **Citadis 405 Irigo**, **Citadis 405 Divia** et **Citadis 305 Naolib**, réservés au choix libre.','','Une captation CC0 du Mans complète les banques existantes. Les sons des modèles apparentés sont identifiés comme tels ; plusieurs familles gardent un son de remplacement.','','## Comparaisons','',f"{dataset['compared']} variantes disposent d’une capture de référence avant modification. Pour les autres, l’absence de capture avant est indiquée. Captures sous éclairage de studio, sans retouche ; encodage WebP sans perte. Les changements généraux d’éclairage apportés par la version des cartes de Claude peuvent également influencer les couleurs.",'']
 for e in entries:
  ref=e['reference'];b=e['before']['front'];a=e['after']['front'];image=e['reference_image']
  md+=['<details>','<summary>'+esc(e['city']+' · '+e['name'])+'</summary>','',f"{e['length']:.2f} × {e['width']:.2f} m · {e['module_count']} caisses · "+' + '.join({'overhead':'LAC','aps':'APS','battery':'autonomie embarquée'}.get(x,x) for x in e['electric_modes']), '']
  if e['fictional']:md+=['**Concept fictif : la photographie illustre uniquement son inspiration.**','']
  md+=['| Avant | Après | '+('Inspiration réelle' if e['fictional'] else 'Référence réelle')+' |','|---|---|---|', '| '+('![Avant]('+b+')' if b else 'Capture avant indisponible pour cette variante.')+' | ![Après]('+a+') | ![Référence]('+image+') |','', '[Voir la rame entière après modification]('+e['after']['threequarter']+') · ['+ref['title']+']('+ref['url']+') — '+ref['author']+' · '+ref['license'], '', e['reference_note'],'','</details>','']
 (OUT/'README.md').write_text('\n'.join(md)+'\n')
 # Exemple directement partageable : vue de face de l'Irigo 302, avec une photo réelle créditée.
 e=next(e for e in entries if e['id']=='angers__citadis_302');canvas=Image.new('RGB',(1440,570),'#14222c');d=ImageDraw.Draw(canvas);font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',22);small=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',14)
 for i,(title,path) in enumerate([('AVANT · modèle précédent',e['before']['front']),('APRÈS · base conservée et affinée',e['after']['front']),('RÉFÉRENCE · Citadis 302 Irigo',e['reference_image'])]):
  d.text((i*480+15,15),title,font=font,fill='white');im=Image.open(OUT/path).convert('RGB');im.thumbnail((466,420));canvas.paste(im,(i*480+(480-im.width)//2,62+(420-im.height)//2))
 ref=e['reference'];d.text((15,506),'Photo : '+ref['author']+' · '+ref['license']+' · miniature redimensionnée. Sources et crédits complets dans la galerie.',font=small,fill='#c3d9e3');d.text((15,536),'Captures du jeu sans retouche · géométrie stylisée · comparaison de la face avant et des optiques.',font=small,fill='#c3d9e3');canvas.save(OUT/'comparison-irigo.jpg',quality=92)
 print({k:v for k,v in dataset.items() if k not in ['entries','method']})
if __name__=='__main__':main()
