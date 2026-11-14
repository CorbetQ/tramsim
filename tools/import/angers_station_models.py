#!/usr/bin/env python3
"""Compile the individually reviewed Angers station survey into game geometry.
Input: public OSM shelter survey, existing physical platforms, IGN aerials (reference cache).
No photographs are baked onto scenery. Geometry remains metric and source-attributed.
"""
from pathlib import Path
import json, math, re, unicodedata, gzip, argparse
import numpy as np
import struct, brotli
from PIL import Image
from shapely.geometry import Polygon, Point, LineString
from shapely.ops import unary_union, triangulate
from shapely.strtree import STRtree
from shapely import constrained_delaunay_triangles
ROOT=Path(__file__).resolve().parents[2]
R=6371008.8

def norm(s):
 s=re.sub('[^a-z0-9]+',' ',unicodedata.normalize('NFKD',s).encode('ascii','ignore').decode().lower()).strip()
 s=re.sub(r'\bst\b','saint',s)
 return s

def frame(points):
 p=np.array(points,float);center=np.asarray(Polygon(p).centroid.coords[0]);val,vec=np.linalg.eigh(np.cov((p-center).T));t=vec[:,np.argmax(val)]
 if t[1]>0:t=-t
 n=np.array([-t[1],t[0]]);u=(p-center)@t;v=(p-center)@n
 return center,t,n,np.ptp(u),np.ptp(v)

# Reviewed per-site observations, not random style variants. Ground plans use IGN BD ORTHO.
OBSERVATIONS={
'Acacias': ['Place commerciale pavée à l’est ; carrefour au sud des quais','Résidences claires à balcons et stationnement organisé'],
'Allonneau-Dunant':['Boulevard nord-sud, long terre-plein engazonné','Quais au nord du carrefour, alignements d’arbres et garde-corps'],
'Avrillé-Ardenne':['Terminus et parking relais à l’est','Haies, traversées piétonnes et quais dissymétriques'],
'Bamako':['Boulevard en diagonale et pelouse entre les voies','Grandes résidences à balcons au nord-ouest'],
'Bascule':['Rue étroite, maisons basses et courbe progressive','Quais décalés ; absence de large esplanade'],
'Beaussier':['Courbe à angle droit au nord des quais','Bâtiments universitaires, stationnements et larges trottoirs'],
'Belle-Beille Campus':['Terminus du campus, voies de retournement et plusieurs faces de quai','Bâtiment à lames de bois et volumes universitaires étagés'],
'Berges de Maine':['Patinoire IceParc, escalier monumental et parvis','Promenade de Maine et garde-corps blancs'],
'Bois du Roy':['Quais au nord-ouest du giratoire','Résidences blanches, haies et venelles plantées'],
'Brisepotière':['Carrefour en Y au nord des quais','Verrières alignées, garde-corps et petits immeubles à pans coupés'],
'CHU-Hôpital':['Quais en bord de Maine au nord du pont','Grand bâtiment hospitalier, promenade arborée et accès latéraux'],
'Capucins':['Giratoire au sud, plateforme engazonnée','Logements blancs à panneaux brun-roux'],
'Centre de Congrès':['Palais des congrès à couverture polygonale','Jardin des plantes, mur de pierre et parvis minéral'],
'Conservatoire':['Conservatoire et parvis planté en triangle','Boulevard oblique et deux quais entourés de garde-corps'],
'Deux-Croix':['Barres de logements et cimetière à proximité','Deux quais au nord du carrefour, mobilier très allongé'],
'Doutre-Maine':['Façades anciennes en tuffeau, angles de rues et ardoises','Station insérée dans une rue dense, petits arbres taillés'],
'Europe':['Esplanade très minérale et équipements de quartier','Alignements d’arbres et grands volumes résidentiels'],
'Farcy':['Station courbe et grand îlot végétalisé','Cheminements en biais, longues banquettes et talus plantés'],
'Foch-Haras':['Boulevard arboré et grands alignements de façades','Quais longilignes en dalles et garde-corps anthracite'],
'Foch-Maison Bleue':['Boulevard Foch et Maison Bleue en mosaïque au nord','Double rangée d’arbres ; station de transition LAC/APS'],
'Hauts de St-Aubin':['Quartier récent et vastes cheminements clairs','Alternance de façades blanches et d’éléments de bois'],
'Hôtel de Ville':['Parvis civique, grand carrefour et immeubles anciens','Quais sur boulevard, garde-corps et arbres d’alignement'],
'Jean Moulin':['Gymnase à façade colorée et résidence d’angle','Giratoire au nord, plateau piéton au sud'],
'Jean Vilar':['Parvis du centre Jean-Vilar et plantations en îlots','Centre de quartier à bandeau rouge et larges stationnements'],
'Jean XXIII':['Place de quartier arborée et commerces','Grandes façades résidentielles et cheminements en dalles'],
'La Barre':['Quais au droit du carrefour et talus résidentiel au nord','Tours et grands conifères derrière la station'],
'La Fayette':['Rue étroite, façades anciennes et petits commerces','Mobilier modulaire documenté par la charte municipale'],
'Le Quai':['Courbe des rails, talus planté et grande place à l’est','Cheminements arborés à l’approche du pont des Arts-et-Métiers'],
'Les Gares':['Station sur pont au-dessus des voies SNCF','Auvents dissymétriques de 40 et 20 m, parking Marengo et garde-corps'],
'Molière':['Quais à proximité du triangle de voies et de la Maine','Parvis, cercles de schiste rappelant l’ancien cirque-théâtre et alignements de peupliers'],
'Monplaisir':['Terminus au bord du centre commercial','Barres résidentielles longues, placettes et carrefour au nord'],
'Montaigne':['Boulevard en diagonale, maison d’angle ancienne','Parvis du centre commercial, alignements d’arbres et quais clairs'],
'Patton':['Plateforme engazonnée au centre d’un boulevard est-ouest','Grands arbres au nord et longs immeubles au sud'],
'Plateau Mayenne':['Courbe engazonnée et parking relais au nord-est','Terrain ouvert à l’est, cheminement et rangées d’arbres'],
'Ralliement':['Deux auvents vitrés asymétriques et accès au parking souterrain','Grand Théâtre, calepinage de pierre et terrasses de café'],
'Roseraie':['Terminus à deux quais, parking relais et haies','Bâtiment commercial bas au sud, logements au nord'],
'St-Gilles':['Pavillon à clocher de cuivre et auvent adossé','Église à toiture pyramidale octogonale et place piétonne'],
'St-Serge Université':['Implantation actuelle boulevard Ayrault, et non l’ancienne station','Façades du campus et bâtiment à grand arc vitré'],
'Strasbourg':['Rue étroite de faubourg et angles commerciaux','Quais de part et d’autre du boulevard, façades enduites'],
'Terra Botanica':['Grand carrefour et stationnement relais','Place plantée, résidences contemporaines et plateforme engazonnée'],
'Verneau':['Large esplanade au nord avec fosses d’arbres circulaires','Bâtiments bas au sud et quais très ouverts'],
'Élysée':['Quais entre maisons de faubourg et logements récents','Plateforme engazonnée et grandes traversées piétonnes']}

# Aerially traced paving patches. Normalised coordinates in the 170 m IGN frame, north up.
# Only visible pedestrian areas are traced; existing road/rail geometry is preserved.
APRON={
'Acacias':[(.55,.27),(.76,.29),(.76,.44),(.66,.59),(.55,.55)],
'Avrillé-Ardenne':[(.37,.45),(.48,.36),(.65,.51),(.56,.62)],
'Bascule':[(.38,.47),(.46,.51),(.43,.60),(.32,.57)],
'Beaussier':[(.61,.40),(.70,.42),(.70,.62),(.65,.69),(.61,.64)],
'Belle-Beille Campus':[(.14,.57),(.44,.57),(.49,.64),(.14,.65)],
'Berges de Maine':[(.36,.27),(.53,.42),(.68,.48),(.76,.37),(.58,.27)],
'Brisepotière':[(.25,.25),(.38,.31),(.36,.42),(.25,.40)],
'Centre de Congrès':[(.19,.35),(.36,.44),(.45,.50),(.42,.56),(.24,.45)],
'Conservatoire':[(.35,.23),(.50,.16),(.56,.26),(.47,.29)],
'Deux-Croix':[(.22,.12),(.38,.14),(.45,.25),(.39,.33),(.23,.26)],
'Europe':[(.13,.34),(.43,.34),(.43,.47),(.27,.47),(.27,.56),(.13,.56)],
'Farcy':[(.26,.25),(.48,.28),(.63,.51),(.57,.57),(.39,.35),(.24,.32)],
'Foch-Haras':[(.28,.57),(.40,.62),(.56,.45),(.47,.39)],
'Foch-Maison Bleue':[(.25,.52),(.43,.31),(.46,.34),(.28,.57)],
'Hauts de St-Aubin':[(.46,.56),(.61,.56),(.62,.62),(.53,.71),(.46,.67)],
'Hôtel de Ville':[(.21,.25),(.29,.31),(.39,.18),(.34,.12)],
'Jean Moulin':[(.46,.29),(.58,.25),(.59,.40),(.48,.42)],
'Jean Vilar':[(.13,.37),(.24,.29),(.31,.33),(.34,.45),(.25,.50),(.14,.47)],
'Jean XXIII':[(.17,.28),(.35,.23),(.42,.33),(.30,.47),(.15,.40)],
'Le Quai':[(.41,.38),(.53,.27),(.67,.20),(.72,.26),(.55,.37),(.46,.47)],
'Molière':[(.46,.38),(.58,.33),(.72,.45),(.61,.55),(.54,.64),(.47,.60)],
'Monplaisir':[(.57,.22),(.81,.22),(.82,.33),(.61,.36),(.57,.32)],
'Montaigne':[(.15,.26),(.39,.39),(.35,.46),(.12,.33)],
'Plateau Mayenne':[(.47,.18),(.59,.11),(.68,.17),(.54,.26)],
'Ralliement':[(.22,.39),(.44,.22),(.69,.45),(.68,.67),(.52,.82),(.28,.60)],
'Roseraie':[(.16,.54),(.34,.54),(.34,.61),(.18,.65)],
'St-Gilles':[(.22,.41),(.32,.35),(.46,.56),(.36,.63)],
'St-Serge Université':[(.20,.35),(.39,.38),(.51,.51),(.47,.55),(.28,.45)],
'Terra Botanica':[(.25,.27),(.43,.26),(.56,.43),(.48,.50),(.30,.43)],
'Verneau':[(.13,.05),(.70,.05),(.70,.16),(.90,.16),(.90,.58),(.15,.58)],
'Élysée':[(.31,.56),(.59,.56),(.60,.65),(.34,.65)]}

# Explicit observed landscape objects / site furniture in the same north-up aerial frame.
# [type, x, y, width/diameter, length, heading_degrees]. No random placement.
ITEMS={
'Acacias':[['planter',.61,.43,2.0,6,0],['planter',.71,.37,2,5,0]],
'Allonneau-Dunant':[['rail_fence',.61,.43,1,34,0]],
'Avrillé-Ardenne':[['parkride',.66,.30,1,1,-45]],
'Bamako':[['rail_fence',.55,.46,1,30,-40]],
'Bascule':[['bench',.39,.56,0.6,2.0,-45]],
'Beaussier':[['cycle_stands',.68,.60,1,5,0]],
'Belle-Beille Campus':[['cycle_stands',.23,.61,1,9,90]],
'Berges de Maine':[['planter',.38,.43,2,8,-45],['planter',.46,.49,2,8,-45],['rail_fence',.68,.65,1,24,-45]],
'Bois du Roy':[['planter',.60,.56,2,5,45]],
'Brisepotière':[['cycle_stands',.31,.36,1,4,-20]],
'CHU-Hôpital':[['rail_fence',.68,.45,1,38,25]],
'Capucins':[['planter',.34,.60,2,5,45]],
'Centre de Congrès':[['cycle_stands',.32,.45,1,6,-55]],
'Conservatoire':[['planter',.43,.26,3,7,-60]],
'Deux-Croix':[['cycle_stands',.33,.25,1,5,0]],
'Doutre-Maine':[['planter',.60,.47,1.6,4,-45]],
'Europe':[['planter',.25,.40,2,7,90],['planter',.40,.35,2,5,90]],
'Farcy':[['bench',.52,.43,.7,7,-35],['planter',.49,.41,2.7,11,-35]],
'Foch-Haras':[['rail_fence',.43,.54,1,38,-40]],
'Foch-Maison Bleue':[['rail_fence',.54,.48,1,37,-40]],
'Hauts de St-Aubin':[['cycle_stands',.54,.62,1,7,90]],
'Hôtel de Ville':[['cycle_stands',.31,.27,1,6,-35]],
'Jean Moulin':[['cycle_stands',.52,.36,1,7,0]],
'Jean Vilar':[['planter',.21,.41,4.5,7,0],['bench',.25,.47,.7,4,90]],
'Jean XXIII':[['planter',.29,.33,3,7,-40]],
'La Barre':[['cycle_stands',.54,.32,1,5,90]],
'La Fayette':[['rail_fence',.58,.48,1,27,-7]],
'Le Quai':[['planter',.49,.41,2.8,7,35]],
'Les Gares':[['rail_fence',.42,.45,1,35,0]],
'Molière':[['history_ring',.60,.49,9,9,0],['bench',.56,.54,.6,4,-45]],
'Monplaisir':[['cycle_stands',.62,.31,1,6,0]],
'Montaigne':[['cycle_stands',.31,.38,1,5,-60]],
'Patton':[['rail_fence',.51,.53,1,34,90]],
'Plateau Mayenne':[['parkride',.63,.20,1,1,-30]],
'Ralliement':[['cafe',.74,.44,4,16,-45],['cafe',.69,.58,4,12,-45]],
'Roseraie':[['parkride',.56,.71,1,1,90]],
'St-Gilles':[['bench',.29,.49,.6,4,-35]],
'St-Serge Université':[['cycle_stands',.39,.42,1,8,-50]],
'Strasbourg':[['rail_fence',.59,.47,1,28,-10]],
'Terra Botanica':[['cycle_stands',.39,.37,1,8,-45]],
'Verneau':[['tree_pit',.25,.09,5,5,0],['tree_pit',.39,.10,5,5,0],['tree_pit',.30,.18,5,5,0],['tree_pit',.65,.33,4,4,0],['tree_pit',.64,.47,4,4,0]],
'Élysée':[['cycle_stands',.43,.61,1,5,90]]}

REFERENCES=json.loads((ROOT/'tools/import/angers_station_references.json').read_text())

def compile_refs(cache,name):
 return REFERENCES['stations'].get(name,{}).get('street',[])

def ensure_aerials(cache, fetch):
 import urllib.request, concurrent.futures as cf
 def download(pair):
  name,record=pair
  import unicodedata
  slug=re.sub(r'[^a-z0-9]+','-',unicodedata.normalize('NFKD',name).encode('ascii','ignore').decode().lower()).strip('-')
  path=cache/'aerial'/(slug+'-170.jpg')
  if path.exists():return
  if not fetch:raise FileNotFoundError(str(path)+' missing. Re-run with --fetch-aerials to retrieve public IGN references.')
  source=next(r for r in record['aerial'] if r['span_m']==170)
  req=urllib.request.Request(source['url'],headers={'User-Agent':'TramSimFrance station study https://github.com/CorbetQ/tramsim'})
  b=urllib.request.urlopen(req,timeout=45).read()
  if not b.startswith(b'\xff\xd8'):raise ValueError('IGN returned an invalid image for '+name)
  path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b)
 with cf.ThreadPoolExecutor(max_workers=3) as pool:list(pool.map(download,REFERENCES['stations'].items()))

def scene_blockers():
 """Read the same metric road/building footprints as the renderer, to avoid paving over traffic lanes."""
 b=(ROOT/'data/scenes/angers.bin').read_bytes();out=[]
 for tile in range(struct.unpack_from('<I',b,4)[0]):
  tx,tz,off,cs,us=struct.unpack_from('<iiIII',b,8+tile*20);q=brotli.decompress(b[off:off+cs]);o=2
  def pts(n,at):return [(tx*400+struct.unpack_from('<h',q,at+j*4)[0]*.1,tz*400+struct.unpack_from('<h',q,at+j*4+2)[0]*.1) for j in range(n)]
  for j in range(struct.unpack_from('<H',q,0)[0]):
   nv=q[o];o+=5;poly=Polygon(pts(nv,o));o+=nv*4;nt=q[o];o+=1+nt*3
   if poly.is_valid:out.append(poly.buffer(.15))
  np=struct.unpack_from('<H',q,o)[0];o+=2
  for j in range(np):
   nv,nt=struct.unpack_from('<HH',q,o+1);o+=5+nv*4+nt*6
  nl=struct.unpack_from('<H',q,o)[0];o+=2
  for j in range(nl):
   cls,w,n=struct.unpack_from('<BBH',q,o);o+=4;line=LineString(pts(n,o));o+=n*4
   if cls in [0,1,2,10] and not line.is_empty:out.append(line.buffer(w/10+.20))
 return out

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--references',type=Path,default=ROOT/'.cache/station-references');parser.add_argument('--fetch-aerials',action='store_true');a=parser.parse_args();cache=a.references
 ensure_aerials(cache,a.fetch_aerials)
 d=json.loads((ROOT/'data/free/angers.json').read_text());stations=json.loads((ROOT/'data/stations/angers.json').read_text())['stations'];origin=d['origin'];cos=math.cos(math.radians(origin[0]))
 local=lambda lat,lon:np.array([math.radians(lon-origin[1])*R*cos,-math.radians(lat-origin[0])*R])
 geo=lambda p:[round(origin[0]-math.degrees(p[1]/R),8),round(origin[1]+math.degrees(p[0]/(R*cos)),8)]
 raw=cache/'osm-shelters.json';rawgz=ROOT/'data/geography/osm/angers_shelters.json.gz'
 if raw.exists():
  rawgz.write_bytes(gzip.compress(raw.read_bytes(),mtime=0))
 else:raw=rawgz
 elements=json.loads(gzip.decompress(raw.read_bytes()) if raw.suffix=='.gz' else raw.read_bytes())['elements']
 blockers=scene_blockers();blocker_index=STRtree(blockers)
 authored=json.loads((ROOT/'data/station_models/angers_landmarks.source.json').read_text())
 pfs=[(p,Polygon(p['pts'])) for p in d['platforms']];lookup={norm(s['name']):s for s in stations};roofs={norm(s['name']):[] for s in stations}
 for e in elements:
  if len(e.get('geometry',[]))<4 or e.get('tags',{}).get('amenity')=='bicycle_parking':continue
  poly=Polygon([local(p['lat'],p['lon']) for p in e['geometry']]);
  if not poly.is_valid or poly.area<2:continue
  distance,p=min(((poly.distance(q),p) for p,q in pfs),key=lambda x:x[0])
  key=norm(p['name'])
  if key not in roofs or distance>1.5:continue
  pts=list(poly.exterior.coords)[:-1];center,t,n,L,W=frame(pts)
  if not 3<L<65 or W>18:continue
  if any(poly.intersection(Polygon(r['local'])).area / min(poly.area,Polygon(r['local']).area)>.72 for r in roofs[key]):continue
  roofs[key].append({'source_osm_way':e['id'],'platform_way':p['osm_way'],'footprint':[geo(q) for q in pts],'local':pts,'length_m':round(L,2),'width_m':round(W,2),'source':'OSM footprint; compared to IGN BD ORTHO'})
 results=[]
 for s in stations:
  key=norm(s['name']);s_pfs=[p for p,q in pfs if norm(p['name'])==key];center=local(s['lat'],s['lon']);profile={'id':key.replace(' ','-'),'name':s['name'],'lat':s['lat'],'lon':s['lon'],'platform_ways':[p['osm_way'] for p in s_pfs],'observations':OBSERVATIONS[s['name']],'roof_family':'glass' if s['name'] in ['Ralliement','Les Gares','St-Gilles'] else 'irigo_modular','capture_span_m':{'Foch-Maison Bleue':220,'Berges de Maine':320,'Centre de Congrès':190,'Les Gares':190,'St-Gilles':175,'Verneau':185}.get(s['name'],145),'canopies':[],'surfaces':[],'furniture':[],'references':compile_refs(cache,s['name'])}
  rs=roofs[key]
  for p in s_pfs:
   if any(r['platform_way']==p['osm_way'] for r in rs) or not p.get('shelter',False):continue
   # Small contiguous fragments at Les Gares belong to the two long canopies, not extra shelters.
   if s['name']=='Les Gares' and p['osm_way'] not in [197501765,835015304]:continue
   pts=p['pts'];c,t,n,L,W=frame(pts)
   if L<10:continue
   length=40.0 if s['name']=='Les Gares' else min(8.4,L*.6)
   width=3.4 if s['name']=='Les Gares' else (2.65 if any(l in p.get('lines',[]) for l in ['B','C']) or s['name'] in ['Allonneau-Dunant','Beaussier','Belle-Beille Campus','Brisepotière','Conservatoire','Deux-Croix','Doutre-Maine','Europe','Farcy','La Barre','Le Quai','Molière','Monplaisir','Montaigne','Patton','Élysée'] else 1.7)
   # Move the measured standard module along the actual platform to the dark rectangular roof in the aerial.
   import PIL.Image
   slug=key.replace('saint ','st ').replace(' ','-');fp=cache/'aerial'/(re.sub(r'[^a-z0-9]+','-',unicodedata.normalize('NFKD',s['name']).encode('ascii','ignore').decode().lower()).strip('-')+'-170.jpg')
   image=np.asarray(Image.open(fp).convert('RGB'));polygon=Polygon(pts);best=(-1e9,c)
   for z in np.arange(-max(0,(L-length)*.45),max(.1,(L-length)*.45),.7):
    for x in np.arange(-max(.01,(W-width)*.45),max(.02,(W-width)*.45),.35):
     at=c+t*z+n*x;corners=[at+t*aa*length/2+n*bb*width/2 for aa,bb in [(-1,-1),(1,-1),(1,1),(-1,1)]]
     if not polygon.buffer(.5).covers(Polygon(corners)):continue
     grid=np.array([at+t*aa*length/2+n*bb*width/2 for aa in np.linspace(-1,1,18) for bb in np.linspace(-1,1,6)])
     pix=((grid-center)*1024/170+512).astype(int);pix=np.clip(pix,0,1023);rgb=image[pix[:,1],pix[:,0]].astype(float)
     grey=rgb.mean(1);green=np.maximum(0,rgb[:,1]-(rgb[:,0]+rgb[:,2])/2)
     score=130-grey.mean()-green.mean()*2-grey.std()*.15
     if score>best[0]:best=(score,at)
   c=best[1]
   if s['name']=='Les Gares':c=np.asarray(polygon.centroid.coords[0])+t*2.5
   ring=[c+t*aa*length/2+n*bb*width/2 for aa,bb in [(-1,-1),(1,-1),(1,1),(-1,1)]]
   rs.append({'platform_way':p['osm_way'],'footprint':[geo(q) for q in ring],'local':[list(q) for q in ring],'length_m':round(length,2),'width_m':round(width,2),'source':'Individual roof placement from IGN aerial; standard module dimensions from municipal charter','measured_from_aerial':True})
  for r in rs:
   r.pop('local',None);profile['canopies'].append(r)
  if s['name'] in APRON:
   profile['surfaces'].append({'type':'paving','footprint':[geo(center+np.array([u-.5,v-.5])*170) for u,v in APRON[s['name']]],'source':'Manually traced pedestrian area from IGN aerial, 170 m north-up frame'})
  for kind,u,v,w,L,heading in ITEMS[s['name']]:profile['furniture'].append({'type':kind,'position':geo(center+np.array([u-.5,v-.5])*170),'width_m':w,'length_m':L,'heading_deg':heading,'source':'Individual IGN aerial placement / Panoramax street reference'})
  # Clip hand-traced pedestrian patches against real road / building geometry.
  near=[blockers[i] for i in blocker_index.query(Point(center).buffer(130))]
  mask=unary_union(near)
  for surf in profile['surfaces']:
   shape=Polygon([local(*p) for p in surf['footprint']]).difference(mask)
   surf['triangles']=[[geo(q) for q in list(t.exterior.coords)[:3]] for t in constrained_delaunay_triangles(shape).geoms if t.area>.02]
  profile['landmarks']=authored['stations'].get(s['name'],[])
  profile['aerial_references']=REFERENCES['stations'][s['name']]['aerial']
  profile['shared_architecture_reference']='https://cpu.angers.fr/product/abri-tramway'
  profile['survey_limitations']='Facade ornaments and furniture reconstructed stylistically; aerial image capture date not supplied by IGN service.'
  results.append(profile)
 out={'schema':1,'city':'angers','units':'metres; geographic points [latitude,longitude] WGS84','source':'Individual visual survey, IGN BD ORTHO, OSM platform/shelter footprints, Angers urban furniture charter, CMR construction photographs, Panoramax','accessed':'2026-11-14','reference_date_policy':'Current relocated stations checked against post-2023 imagery; older views labelled in reference metadata','stations':results,'depot':{'id':'raymond-perron','name':'Centre technique des transports Raymond-Perron','lat':47.49513,'lon':-.56879,'capture_span_m':460,'references':compile_refs(cache,'Dépôt Raymond-Perron')}}
 out['depot'].update(authored['depot'])
 # Pretriangulate the workshop roof with its true courtyard void, so runtime cannot fill it.
 workshop=d['depots'][0]['buildings'][0]
 outer=Polygon(workshop['pts']);hole=Polygon([local(*p) for p in authored['depot']['workshop_void']]);shape=outer.difference(hole)
 out['depot']['workshop_roof_triangles']=[[geo(q) for q in list(t.exterior.coords)[:3]] for t in constrained_delaunay_triangles(shape).geoms]
 dst=ROOT/'data/station_models/angers.json';dst.parent.mkdir(exist_ok=True);dst.write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps({'stations':len(results),'platforms':sum(len(s['platform_ways']) for s in results),'canopies':sum(len(s['canopies']) for s in results),'surfaces':sum(len(s['surfaces']) for s in results),'individual_furniture':sum(len(s['furniture']) for s in results)},indent=2))
if __name__=='__main__':main()
