import importlib.util,json,math,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('station_power',ROOT/'tools/import/station_power.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class StationPowerImport(unittest.TestCase):
 def test_projection_matches_the_world_reference_frame(self):
  # 0,1 degré d'arc dans le repère métrique livré, pas EPSG:3857.
  self.assertAlmostEqual(math.radians(.1)*module.R,11119.50802335329,places=5)
 def test_osm_positions_footprint_and_supply_override_gtfs(self):
  def node(i,x,z,tags=None):return dict(type='node',id=i,lon=math.degrees(x/module.R),lat=-math.degrees(z/module.R),tags=tags or {})
  nodes=[node(1,0,0),node(2,200,0),node(3,100,0,{'name':'Station','railway':'tram_stop','gtfs:stop_id:test':'exact'}),node(4,120,0,{'name':'Station','railway':'tram_stop'}),node(5,80,3),node(6,120,3),node(7,120,6),node(8,80,6)]
  osm={'elements':nodes+[dict(type='way',id=10,nodes=[1,2],tags={'railway':'tram','electrified':'ground-level_power_supply'}),dict(type='way',id=11,nodes=[5,6,7,8,5],tags={'public_transport':'platform','name':'Station'})]}
  data={'schema':1,'origin':[0,0],'source_id':'angers','geometry_kind':'physical','edges':[dict(id='rail',length=200,pts=[[0,0],[200,0]],y=[0,0],supply='overhead',source={'way':10})],'stations':[dict(name='Station',stop_id='exact',edge='rail',offset=119)],'missions':[dict(stops=[0],start_edge='rail',start_offset=119)]}
  with tempfile.TemporaryDirectory() as directory:
   path=Path(directory)/'network.json';path.write_text(json.dumps(data));module.enrich(path,osm);result=json.loads(path.read_text())
  self.assertEqual(result['stations'][0]['source_osm_node'],3)
  self.assertAlmostEqual(result['stations'][0]['offset'],100,places=2)
  self.assertEqual(result['edges'][0]['supply'],'aps')
  self.assertEqual(result['platforms'][0]['pts'],[[80,3],[120,3],[120,6],[80,6]])
  self.assertFalse(result['platforms'][0]['width_estimated'])
  self.assertLess(result['missions'][0]['start_offset'],100)
 def test_station_direction_follows_the_new_physical_edge(self):
  def n(i,x,z,tags=None):return dict(type='node',id=i,lon=math.degrees(x/module.R),lat=-math.degrees(z/module.R),tags=tags or {})
  osm={'elements':[n(1,0,0),n(2,200,0),n(3,100,0,{'railway':'tram_stop','name':'Station'}),dict(type='way',id=10,nodes=[1,2],tags={'railway':'tram','electrified':'contact_line'})]}
  d={'schema':1,'origin':[0,0],'source_id':'angers','geometry_kind':'physical','edges':[dict(id='old',length=200,pts=[[0,3],[200,3]],y=[0,0]),dict(id='back',length=200,pts=[[200,0],[0,0]],y=[0,0])],'stations':[dict(name='Station',edge='old',offset=100,direction=1)]}
  with tempfile.TemporaryDirectory() as directory:
   path=Path(directory)/'network.json';path.write_text(json.dumps(d));module.enrich(path,osm);result=json.loads(path.read_text())
  self.assertEqual(result['stations'][0]['edge'],'back')
  self.assertEqual(result['stations'][0]['direction'],-1)
 def test_unpowered_track_is_not_assumed_to_charge_a_battery(self):
  self.assertEqual(module.electrical_mode('no','angers'),'none')
  self.assertEqual(module.electrical_mode('ground-level_power_supply','bordeaux'),'aps')
  self.assertIsNone(module.electrical_mode('unknown','angers'))
if __name__=='__main__':unittest.main()
