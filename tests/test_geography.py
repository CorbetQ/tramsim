import gzip,json,math,sys,unittest
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'tools/import'),str(ROOT/'tools/maintenance')]
from terrain import fill_nodata,interpolate_elevation
from physical_network import project_profile
from stitch_terrain import read_tiles

class Geography(unittest.TestCase):
    def test_missing_dem_is_not_sea_level(self):
        values=np.full((10,10),123.4);values[4,5]=-99999;values[5,5]=np.nan
        np.testing.assert_allclose(fill_nodata(values),123.4)
        with self.assertRaises(ValueError):fill_nodata(np.full((10,10),-99999.))
    def test_bridge_height_uses_distance_not_vertex_index(self):
        points=np.array([[0,0,10],[1,0,20],[101,0,30]])
        samples=np.array([[0,0],[1,0],[51,0],[101,0]])
        np.testing.assert_allclose(interpolate_elevation(points,samples),[10,20,25,30])
    def test_gradient_constraint_is_continuous_at_a_junction(self):
        edges=[dict(id='a',**{'from':'A','to':'J'},pts=[[0,0],[10,0]],y=[0.,10.]),
               dict(id='b',**{'from':'J','to':'B'},pts=[[10,0],[20,0]],y=[10.,0.]),
               dict(id='c',**{'from':'J','to':'C'},pts=[[10,0],[10,10]],y=[10.,0.])]
        project_profile(edges)
        self.assertAlmostEqual(edges[0]['y'][-1],edges[1]['y'][0])
        self.assertAlmostEqual(edges[1]['y'][0],edges[2]['y'][0])
        for e in edges:self.assertLessEqual(abs(e['y'][1]-e['y'][0]),.8000001)
        # Symmetric treatment must raise the low samples too, rather than only burying the bridge.
        self.assertGreater(edges[0]['y'][0],0.)
    def test_every_physical_endpoint_matches_its_osm_node(self):
        for path in sorted((ROOT/'data/free').glob('*.json')):
            net=json.loads(path.read_text());osm=json.loads(gzip.decompress((ROOT/f'data/geography/osm/{path.stem}.json.gz').read_bytes()))
            nodes={n['id']:n for n in osm['elements'] if n['type']=='node'}
            lat,lon=net['origin'];factor=math.cos(math.radians(lat));r=6371008.8
            self.assertEqual(net['coverage']['missing_terrain_segments'],0,path.stem)
            self.assertFalse(net['coverage']['unmatched_stations'],path.stem)
            for e in net['edges']:
                for index,key in [(0,'node_from'),(-1,'node_to')]:
                    node=nodes[e['source'][key]];expected=(math.radians(node['lon']-lon)*r*factor,-math.radians(node['lat']-lat)*r)
                    # Le lissage des voies (tools/import/smooth_tracks.py, raccords progressifs) peut déplacer
                    # légèrement les extrémités : médiane 0,1 m, max ~3,5 m documenté (docs/SOURCES.md).
                    self.assertLess(math.dist(expected,e['pts'][index]),3.5 if net.get('track_smoothing') else .0015,(path.stem,e['id']))
                for p,q,a,b in zip(e['pts'],e['pts'][1:],e['y'],e['y'][1:]):
                    self.assertLessEqual(abs(b-a),math.dist(p,q)*.09+.002,(path.stem,e['id']))  # y arrondis au mm après rééchantillonnage
    def test_ground_files_present(self):
        for path in sorted((ROOT/'data/scenes').glob('*.json')):
            if '_' in path.stem:continue
            ground=ROOT/f'data/scenes/{path.stem}_ground.bin'
            self.assertTrue(ground.exists(),path.stem)
            self.assertIn(ground.read_bytes()[:4],(b'TGR1',b'TGR2'))
    def test_all_terrain_tile_borders_are_identical(self):
        for path in sorted((ROOT/'data/scenes').glob('*_terrain.bin')):
            tiles=read_tiles(path.read_bytes())
            self.assertEqual(path.read_bytes()[:4],b'TTR2')
            for (x,z),(grid,_) in tiles.items():
                if (x+1,z) in tiles:
                    other=tiles[x+1,z][0]
                    self.assertEqual([grid[i*41+40] for i in range(41)],[other[i*41] for i in range(41)],(path.stem,x,z))
                if (x,z+1) in tiles:self.assertEqual(grid[-41:],tiles[x,z+1][0][:41],(path.stem,x,z))

if __name__=='__main__':unittest.main()
