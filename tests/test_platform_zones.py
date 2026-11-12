import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('platform_zones', ROOT / 'tools/import/platform_zones.py')
zones = importlib.util.module_from_spec(spec)
spec.loader.exec_module(zones)


class PlatformZones(unittest.TestCase):
    def make_data(self):
        # Un quai de 40 m traverse un nœud ; à 20 m du quai, une branche
        # APS diverge de la continuité droite qui reste sous LAC.
        return dict(schema=1, source_id='test', nodes=['a','b','c','d','e'],
                    edges=[dict(id='before', **{'from':'a','to':'b'}, length=100, pts=[[0,0],[100,0]], supply='overhead'),
                           dict(id='after', **{'from':'b','to':'c'}, length=40, pts=[[100,0],[140,0]], supply='overhead'),
                           dict(id='straight', **{'from':'c','to':'d'}, length=100, pts=[[140,0],[240,0]], supply='overhead'),
                           dict(id='aps', **{'from':'c','to':'e'}, length=100, pts=[[140,0],[200,80]], supply='aps')],
                    stations=[dict(name='Transition', edge='after', offset=0, dwell_s=20)],
                    platforms=[dict(osm_way=1, name='Transition', pts=[[80,2],[120,2],[120,5],[80,5]])])

    def enrich(self, data):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/'test.json';path.write_text(json.dumps(data))
            zones.enrich(path)
            first = path.read_bytes()
            zones.enrich(path)
            self.assertEqual(first, path.read_bytes(), 'import idempotent')
            return json.loads(first)

    def test_full_platform_and_branch_transition(self):
        original = self.make_data(); result = self.enrich(original)
        area = result['stations'][0]['stop_area']
        self.assertTrue(area['power_transition'])
        self.assertEqual(area['segments'], [['before',79.0,100.0],['after',0.0,21.0]])
        self.assertEqual(result['edges'][0]['power_overlaps'], [[79.0,100.0]])
        self.assertEqual(result['edges'][1]['power_overlaps'], [[0.0,40.0]])
        self.assertNotIn('power_overlaps',result['edges'][2], 'aucun rail APS ajouté à la branche droite')
        self.assertEqual(result['platforms'],original['platforms'])
        for before,after in zip(original['edges'], result['edges']):
            for key in before:self.assertEqual(before[key],after[key])

    def test_no_dual_supply_without_a_boundary(self):
        data=self.make_data();data['edges'][-1]['supply']='overhead'
        result=self.enrich(data)
        self.assertNotIn('power_transition',result['stations'][0]['stop_area'])
        self.assertTrue(all('power_overlaps' not in edge for edge in result['edges']))

    def test_does_not_choose_an_opposite_or_remote_platform(self):
        data=self.make_data()
        data['platforms'] += [dict(osm_way=2,name='Transition',pts=[[80,-7],[120,-7],[120,-10],[80,-10]]),
                              dict(osm_way=3,name='Autre',pts=[[80,1],[120,1],[120,2],[80,2]])]
        self.assertEqual(self.enrich(data)['stations'][0]['stop_area']['osm_way'],1)

    def test_foch_both_directions(self):
        network=json.loads((ROOT/'data/free/angers.json').read_text())
        stations=[s for s in network['stations'] if s['name']=='Foch-Maison Bleue']
        self.assertEqual(len(stations),2)
        for station in stations:
            area=station['stop_area'];self.assertTrue(area['power_transition'])
            self.assertGreater(sum(b-a for _,a,b in area['segments']),38)
            self.assertEqual(len(area['segments']),2)


if __name__ == '__main__':unittest.main()
