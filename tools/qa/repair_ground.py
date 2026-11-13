#!/usr/bin/env python3
"""Migration ciblée TGR1->TGR2, récupération des deltas et correction des anomalies MNT littorales.
Conserve les triangles, matériaux, décalques, ponts et niveaux d'eau. Référence : RGE ALTI IGN.
Usage : repair_ground.py [grenoble lehavre nantes nice]. Rejouable sans changer un TGR2 existant.
"""
import sys,json,struct,math,os
from pathlib import Path
import brotli,numpy as np
from scipy.spatial import cKDTree
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'tools/import'),str(ROOT/'tools/qa')]
import terrain_mesh as TM
from audit_ground import decode

def repair(city):
 path=ROOT/f'data/scenes/{city}_ground.bin';data=path.read_bytes()
 if data[:4]==b'TGR2':return {'city':city,'already_migrated':True}
 assert data[:4]==b'TGR1'
 meta_path=ROOT/f'data/scenes/{city}_terrain.json';meta=json.loads(meta_path.read_text());alt0=meta['alt0']
 frame=TM.T.Frame(*json.loads((ROOT/f'data/scenes/{city}.json').read_text())['origin'])
 dem=TM.T.Dem(frame,str(ROOT/'.cache/ground-dem'),city)
 tp,ty,*_=TM.free_tracks(city,frame)
 cache=Path(os.environ.get('TRAMSIM_IGN_CACHE',str(ROOT/'.cache/geography/ign_cache')))
 water=TM.T.water_surfaces(frame,str(cache),(-90,-180,90,180)) if cache.is_dir() else []
 height=TM.Height(dem,alt0,(tp,ty),water)
 records=[];bad_points=[];unwrapped=0
 n=struct.unpack_from('<I',data,12)[0]
 for i in range(n):
  x,z,off,cs,size,ymin=struct.unpack_from('<iiIIIf',data,40+i*24)
  raw=brotli.decompress(data[off:off+cs]);base,nv,nt=struct.unpack_from('<fII',raw);v,t=decode(raw)
  delta=np.frombuffer(raw,dtype='<i2',count=nv,offset=12+nv*4).astype(np.int64).cumsum()
  world=v[:,[0,2]]+np.array([x,z])*400
  if delta.min()<0 or delta.max()>65535:
   v[:,1]=base+np.mod(delta,65536)/100
   if city=='grenoble':
    reference=height(world[:,0],world[:,1])
    v[:,1]+=np.round((reference-v[:,1])/655.36)*655.36
   unwrapped+=1
  invalid=v[:,1]+alt0 < -20
  if invalid.any():bad_points.extend(world[invalid].tolist())
  records.append({'key':(x,z),'v':v,'raw':raw,'nv':nv,'old_y':v[:,1].copy()})
 tree=cKDTree(bad_points) if bad_points else None
 def corrected(xz,old):
  if tree is None:return old.copy()
  distance,_=tree.query(xz);mask=distance<40
  out=old.copy()
  if mask.any():
   w=np.clip((40-distance[mask])/20,0,1);w=w*w*(3-2*w)
   ref=height(xz[mask,0],xz[mask,1]);out[mask]=old[mask]*(1-w)+ref*w
  return out
 blobs=[];changed=0;vertices_changed=0
 for record in records:
  x,z=record['key'];v=record['v'];raw=record['raw'];nv=record['nv'];old=record['old_y']
  world=v[:,[0,2]]+np.array([x,z])*400
  new=corrected(world,old)
  # Même profil canonique tous les 10 m dans les deux tuiles voisines, y compris les sommets intermédiaires.
  if tree is not None:
   for axis,value in [(0,0),(0,400),(2,0),(2,400)]:
    ids=np.flatnonzero(abs(v[:,axis]-value)<.001)
    if not len(ids):continue
    other=2 if axis==0 else 0;ids=ids[np.argsort(v[ids,other])];ts=np.arange(0,400.001,10)
    points=np.zeros((len(ts),2));points[:,axis//2]=[x,z][axis//2]*400+value;points[:,other//2]=[x,z][other//2]*400+ts
    original=np.interp(ts,v[ids,other],old[ids]);profile=corrected(points,original)
    new[ids]=np.interp(v[ids,other],ts,profile)
  vertices_changed+=int(np.count_nonzero(abs(new-old)>.02));changed+=int(np.any(abs(new-old)>.02))
  base=math.floor(float(new.min())*100)/100;yq=np.round((new-base)*100).astype(np.int64);dy=np.diff(np.r_[0,yq])
  assert np.max(np.abs(dy))<2**31
  newraw=struct.pack('<fII',base,nv,struct.unpack_from('<I',raw,8)[0])+raw[12:12+4*nv]+dy.astype('<i4').tobytes()+raw[12+6*nv:]
  blobs.append((record['key'],brotli.compress(newraw,quality=10),len(newraw),base+yq.min()/100))
 far_off,far_cs,far_raw,meta_off,meta_cs,meta_raw=struct.unpack_from('<IIIIII',data,16)
 far=bytearray(brotli.decompress(data[far_off:far_off+far_cs]));far_h=np.frombuffer(far,dtype='<i2',offset=16).copy();bad=far_h/10+alt0 < -20;far_h[bad]=round(-alt0*10);far[16:]=far_h.tobytes();far_z=brotli.compress(bytes(far),quality=10)
 meta_z=data[meta_off:meta_off+meta_cs];head_len=40+24*n;fo=head_len;mo=fo+len(far_z);off=mo+len(meta_z)
 header=b'TGR2'+struct.pack('<IfIIIIIII',2,400,n,fo,len(far_z),len(far),mo,len(meta_z),meta_raw);table=bytearray()
 for key,compressed,size,ymin in blobs:
  table+=struct.pack('<iiIIIf',*key,off,len(compressed),size,ymin);off+=len(compressed)
 path.write_bytes(header+table+far_z+meta_z+b''.join(b for _,b,_,_ in blobs))
 report={'city':city,'unwrapped_tiles':unwrapped,'nodata_points':len(bad_points),'resampled_tiles':changed,'resampled_vertices':vertices_changed,'far_nodata_points':int(bad.sum()),'format':'TGR2','source':'IGN RGE ALTI WMS, surface terrestre, valeurs littorales < -20 m traitées comme NODATA','source_date':'2026-11-13'}
 meta['terrain_format']='TGR2';meta['height_encoding']='deltas signés 32 bits, centimètres';meta['repair']=report;meta_path.write_text(json.dumps(meta,ensure_ascii=False,separators=(',',':'))+'\n')
 print(json.dumps(report,ensure_ascii=False),flush=True);return report
if __name__=='__main__':
 result=[repair(c) for c in (sys.argv[1:] or ['grenoble','lehavre','nantes','nice','brest'])]
 (ROOT/'.cache/ground-repairs.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
