#!/usr/bin/env python3
"""Vérifie les tuiles TGR1 livrées : indices, finitude, couverture surfacique et raccords en altitude."""
import json,struct,sys
from pathlib import Path
import brotli,numpy as np
ROOT=Path(__file__).resolve().parents[2]
def decode(data, wide=False):
 base,nv,nt=struct.unpack_from('<fII',data)
 xz=np.frombuffer(data,dtype='<i2',count=nv*2,offset=12).reshape(2,nv).astype(np.int64).cumsum(axis=1)
 y=np.frombuffer(data,dtype='<i4' if wide else '<i2',count=nv,offset=12+nv*4).astype(np.int64).cumsum()
 v=np.column_stack((xz[0]/64,base+y/100,xz[1]/64))
 t=np.frombuffer(data,dtype='<i2',count=nt*3,offset=12+nv*(8 if wide else 6)).reshape(3,nt).astype(np.int64)
 t[0]=t[0].cumsum();t[1]+=t[0];t[2]+=t[1]
 return v,t.T

def audit(path):
 b=path.read_bytes();assert b[:4] in (b'TGR1',b'TGR2');tile=struct.unpack_from('<f',b,8)[0];n=struct.unpack_from('<I',b,12)[0]
 tiles={};errors=[];max_area_error=0;triangles=0
 city=path.stem.removesuffix('_ground');alt0=json.loads(path.with_name(city+'_terrain.json').read_text())['alt0'];min_absolute=1e9;max_absolute=-1e9
 for i in range(n):
  x,z,off,cs,raw,ymin=struct.unpack_from('<iiIIIf',b,40+24*i);data=brotli.decompress(b[off:off+cs]);assert len(data)==raw
  v,t=decode(data,b[:4]==b'TGR2');assert np.isfinite(v).all() and t.min()>=0 and t.max()<len(v)
  min_absolute=min(min_absolute,float(v[:,1].min()+alt0));max_absolute=max(max_absolute,float(v[:,1].max()+alt0))
  if v[:,1].min()+alt0 < -20.05:errors.append({'tile':[x,z],'invalid_surface_altitude_m':float(v[:,1].min()+alt0)})
  a,c,d=v[t[:,0]][:,[0,2]],v[t[:,1]][:,[0,2]],v[t[:,2]][:,[0,2]]
  area=np.abs((c[:,0]-a[:,0])*(d[:,1]-a[:,1])-(c[:,1]-a[:,1])*(d[:,0]-a[:,0])).sum()/2
  delta=abs(area-tile**2);max_area_error=max(max_area_error,float(delta));triangles+=len(t)
  # Quantification à 1/64 m : tolérance surfacique 0,5 m² sur 160 000 m², raccords contrôlés séparément.
  if delta>0.5:errors.append({'tile':[x,z],'area_error_m2':float(delta)})
  if v[:,[0,2]].min()<-0.02 or v[:,[0,2]].max()>tile+0.02:errors.append({'tile':[x,z],'outside_bounds':True})
  borders=[]
  for axis,val in [(0,0),(0,tile),(2,0),(2,tile)]:
   p=v[np.abs(v[:,axis]-val)<0.001];p=p[np.argsort(p[:,2 if axis==0 else 0])];borders.append(p[:,[2 if axis==0 else 0,1]])
  tiles[(x,z)]=borders
 max_seam=0
 for (x,z),borders in tiles.items():
  for neighbor,left,right in [((x+1,z),1,0),((x,z+1),3,2)]:
   if neighbor not in tiles:continue
   a=borders[left];b_=tiles[neighbor][right];q=np.unique(np.r_[a[:,0],b_[:,0]])
   gap=float(np.max(np.abs(np.interp(q,a[:,0],a[:,1])-np.interp(q,b_[:,0],b_[:,1]))));max_seam=max(max_seam,gap)
   if gap>0.03:errors.append({'seam':[[x,z],list(neighbor)],'height_gap_m':gap})
 return {'city':path.stem.removesuffix('_ground'),'tiles':n,'triangles':triangles,'max_area_error_m2':max_area_error,'max_seam_m':max_seam,'min_altitude_m':min_absolute,'max_altitude_m':max_absolute,'errors':errors}
if __name__=='__main__':
 result=[audit(p) for p in sorted((ROOT/'data/scenes').glob('*_ground.bin'))]
 out=Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'.cache/ground-audit.json';out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps({'cities':result},ensure_ascii=False,indent=2)+'\n')
 print(json.dumps({'cities':len(result),'tiles':sum(c['tiles'] for c in result),'errors':sum(len(c['errors']) for c in result),'report':str(out)}),flush=True)
 sys.exit(1 if any(c['errors'] for c in result) else 0)
