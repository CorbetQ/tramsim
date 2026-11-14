"""Source-level regressions for authored Angers sites (no GIS dependency at runtime or in this test)."""
import json, math, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def read(p):return json.loads((ROOT/p).read_text())
def local(ll,origin):return (math.radians(ll[1]-origin[1])*6371008.8*math.cos(math.radians(origin[0])),-math.radians(ll[0]-origin[0])*6371008.8)
def area(p):return abs(sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(p,p[1:]+p[:1])))*.5
def inside(p,poly):
 c=False
 for a,b in zip(poly,poly[1:]+poly[:1]):
  if (a[1]>p[1])!=(b[1]>p[1]) and p[0]<(b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0]:c=not c
 return c
class AngersStationModels(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.models=read('data/station_models/angers.json');cls.net=read('data/free/angers.json');cls.origin=cls.net['origin']
 def test_every_stop_and_physical_platform_is_covered_once(self):
  canonical=read('data/stations/angers.json')['stations'];ss=self.models['stations']
  self.assertEqual({s['name'] for s in ss},{s['name'] for s in canonical});self.assertEqual(len(ss),42)
  ways=[w for s in ss for w in s['platform_ways']]
  self.assertEqual(len(ways),len(set(ways)));self.assertEqual(set(ways),{p['osm_way'] for p in self.net['platforms']})
  self.assertEqual(len(ways),79)
 def test_each_stop_has_its_own_model_and_source_trail(self):
  for s in self.models['stations']:
   with self.subTest(station=s['name']):
    self.assertTrue(s['canopies']);self.assertTrue(s['landmarks']);self.assertTrue(s['furniture'])
    self.assertGreaterEqual(len(s['aerial_references']),2);self.assertTrue(s['references'])
    self.assertEqual(s['aerial_references'][0]['provider'],'IGN BD ORTHO')
    self.assertIn('not supplied',s['aerial_references'][0]['capture_date'])
    self.assertTrue(all(p['page'].startswith('https://') for p in s['references']))
 def test_models_stay_near_the_documented_stop(self):
  for s in self.models['stations']:
   center=local([s['lat'],s['lon']],self.origin)
   for model in s['canopies']+s['landmarks']:
    pts=[local(p,self.origin) for p in model['footprint']]
    c=(sum(p[0] for p in pts)/len(pts),sum(p[1] for p in pts)/len(pts))
    self.assertLess(math.dist(c,center),220,s['name']);self.assertGreater(area(pts),1)
 def test_gare_canopies_have_the_two_documented_lengths(self):
  s=next(s for s in self.models['stations'] if s['name']=='Les Gares')
  self.assertEqual(len(s['canopies']),2)
  lengths=sorted(c['length_m'] for c in s['canopies']);self.assertAlmostEqual(lengths[0],20,delta=2);self.assertAlmostEqual(lengths[1],40,delta=1)
 def test_workshop_roof_keeps_the_courtyard_open(self):
  depot=self.models['depot'];hole=[local(p,self.origin) for p in depot['workshop_void']]
  roof=depot['workshop_roof_triangles'];self.assertGreater(len(roof),10)
  roof_area=0
  for tri in roof:
   pts=[local(p,self.origin) for p in tri];c=tuple(sum(p[i] for p in pts)/3 for i in [0,1])
   self.assertFalse(inside(c,hole));roof_area+=area(pts)
  expected=area([tuple(p) for p in self.net['depots'][0]['buildings'][0]['pts']])-area(hole)
  self.assertAlmostEqual(roof_area,expected,delta=2)
 def test_source_geometry_is_not_mutated_by_the_authoring_data(self):
  ways={p['osm_way'] for p in self.net['platforms']}
  for s in self.models['stations']:
   for c in s['canopies']:self.assertIn(c['platform_way'],ways)
   for surface in s['surfaces']:
    self.assertIn('triangles',surface)
    for tri in surface['triangles']:
     self.assertEqual(len(tri),3)
     self.assertTrue(all(math.isfinite(v) for p in tri for v in p))
if __name__=='__main__':unittest.main()
