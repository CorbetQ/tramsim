import sys,unittest
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'tools/import'),str(ROOT/'tools/qa')]
from terrain_mesh import encode_tile,_fill_nodata
from audit_ground import decode
class TerrainCodecTests(unittest.TestCase):
 def test_large_height_steps_round_trip(self):
  vertices=np.array([[0.,0.,0.],[400.,600.,0.],[400.,0.,400.],[0.,700.,400.]])
  triangles=np.array([[0,1,2],[0,2,3]])
  raw,_=encode_tile(vertices,triangles,np.zeros(2,np.uint8))
  restored,t=decode(raw,wide=True)
  expected={(v[0],v[2]):v[1] for v in vertices}
  self.assertEqual(len(t),2)
  for v in restored:self.assertAlmostEqual(v[1],expected[(v[0],v[2])],places=2)
 def test_coastal_nodata_is_not_a_deep_pit(self):
  data=np.full((10,10),2.);data[4,4]=-373.3
  cleaned=_fill_nodata(data)
  self.assertGreaterEqual(cleaned.min(),0)
  self.assertEqual(cleaned[0,0],2.)
