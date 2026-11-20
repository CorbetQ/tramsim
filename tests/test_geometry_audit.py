import importlib.util
import json
import math
import tempfile
import subprocess
import sys
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('geometry',ROOT/'tools/qa/geometry_audit.py')
g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)

class GeometryAudit(unittest.TestCase):
    def net(self, edges=None):
        return {'id':'fixture','origin':[47,-.5],'edges':edges or [self.edge()]}
    def edge(self):
        return {'id':'e','from':'A','to':'B','length':100,'pts':[[0,0],[100,0]],'y':[0,0]}
    def plan(self):
        return {'width_m':2.4,'height_m':3.3,'modules':[{'length_m':9}]}
    def obstacle(self, bottom=0,top=8):
        return {'id':'pole','kind':'catenary_pole','polygon':[[19,-.1],[21,-.1],[21,.1],[19,.1]],'bottom_m':bottom,'top_m':top,'provenance':'synthetic fixture, not a real pole'}
    def test_collision_and_grade_separation(self):
        edge=self.edge()
        hits,_=g.swept(edge,self.plan(),[self.obstacle()])
        self.assertEqual(len(hits),1)
        self.assertFalse(g.swept(edge,self.plan(),[self.obstacle(5,6)])[0])
        self.assertTrue(g.swept(edge,self.plan(),[self.obstacle(3,4)])[0])
    def test_ramp_changes_clearance(self):
        edge=self.edge();edge['y']=[0,10]
        ob=self.obstacle(5,6);ob['polygon']=[[89,-.1],[91,-.1],[91,.1],[89,.1]];ob['bottom_m']=12;ob['top_m']=13
        self.assertTrue(g.swept(edge,self.plan(),[ob])[0])
        edge['y']=[0,0]
        self.assertFalse(g.swept(edge,self.plan(),[ob])[0])
    def test_curve_sweeps_inside_of_axis(self):
        pts=[[10*math.cos(i*math.pi/80),10*math.sin(i*math.pi/80)] for i in range(41)]
        edge=dict(self.edge(),pts=pts,y=[0]*len(pts),length=5*math.pi)
        ob=self.obstacle();ob['polygon']=[[5.3,5.3],[5.8,5.3],[5.8,5.8],[5.3,5.8]]
        self.assertGreater(10-math.hypot(5.55,5.55),1.2)
        self.assertTrue(g.swept(edge,self.plan(),[ob],spacing=.25)[0])
    def test_junction_horizontal_and_vertical_discontinuity(self):
        a=self.edge();b=dict(self.edge(),id='b',**{'from':'B','to':'C'},pts=[[101,0],[200,0]],y=[1,1])
        report=g.audit_network(self.net([a,b]))
        gaps=[f for f in report['findings'] if f['kind'].startswith('junction_discontinuity')]
        self.assertEqual(len(gaps),1);self.assertEqual(gaps[0]['evidence']['horizontal_m'],1)
        self.assertIsNotNone(gaps[0]['geographic'])
    def test_no_connection_inferred_from_crossing(self):
        first=self.edge();second=dict(self.edge(),id='b',**{'from':'C','to':'D'},pts=[[50,-50],[50,50]])
        with self.assertRaisesRegex(ValueError,'topologically'):
            g.route_edge(self.net([first,second]),[{'edge':'e'},{'edge':'b'}])
    def test_route_includes_multiple_edges_and_reverse(self):
        a=self.edge();b=dict(self.edge(),id='b',**{'from':'C','to':'B'},pts=[[200,0],[100,0]])
        route=g.route_edge(self.net([a,b]),[{'edge':'e'},{'edge':'b','direction':-1}])
        self.assertEqual(route['pts'],[[0,0],[100,0],[200,0]])
        self.assertEqual(route['length'],200)
    def test_bad_geometry_reports_not_crashes(self):
        edge=self.edge();edge['y']=[float('nan'),0]
        rows=g.audit_network(self.net([edge]))['findings'];self.assertEqual(rows[0]['kind'],'invalid_geometry')
        edge=self.edge();edge['length']=float('nan')
        json.dumps(g.audit_network(self.net([edge])),allow_nan=False)
    def test_original_osm_endpoint_mismatch_detected(self):
        edge=self.edge();edge['source']={'node_from':1,'node_to':2}
        nodes={1:{'lat':47,'lon':-.5},2:{'lat':47,'lon':-.5}}
        report=g.audit_network(self.net([edge]),osm_nodes=nodes)
        self.assertTrue(any(r['kind']=='source_endpoint_offset:-1' for r in report['findings']))
    def test_exclusions_strict_and_accountable(self):
        row=g.finding(self.net(),'test','e',[0,0,0])
        with self.assertRaises(ValueError):g.exclusions([row],[{'finding_id':row['id']}])
        rule={'finding_id':row['id'],'reason':'synthetic test only','author':'test suite','evidence_url':'fixture','expires':'2099-01-01','evidence_sha256':g.evidence_digest(row)}
        g.exclusions([row],[rule]);self.assertEqual(row['status'],'documented_exclusion')
        rule['expires']='2000-01-01'
        with self.assertRaises(ValueError):g.exclusions([row],[rule])
    def test_reproducible_and_html_escapes_content(self):
        edge=self.edge();edge['y']=[0,50]
        net=self.net([edge]);net['id']='<script>alert(1)</script>'
        first=g.audit_network(net);self.assertEqual(first,g.audit_network(net))
        text=g.render_html({'networks':[first],'summary':{}})
        self.assertNotIn('<script>',text)
    def test_collinear_disjoint_polygons_do_not_collide(self):
        a=[[0,0],[1,0],[1,1],[0,1]];b=[[2,0],[3,0],[3,1],[2,1]]
        self.assertFalse(g.intersects(a,b))
    def test_spatial_index_preserves_actual_collisions(self):
        obs=[self.obstacle()]
        plain=g.swept(self.edge(),self.plan(),obs)[0]
        indexed=g.swept(self.edge(),self.plan(),obs,index=g.obstacle_index(obs))[0]
        self.assertEqual(plain,indexed)
        ob=self.obstacle();ob['polygon']=[[0,0],[1,1],[0,1],[1,0]]
        with self.assertRaises(ValueError):g.obstacle_index([ob])
    def test_cli_regression_gate_and_network_coverage(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);net=root/'net.json';report=root/'report.json';new=root/'new.json'
            data=self.net();net.write_text(json.dumps(data))
            def run(*extra):
                return subprocess.run([sys.executable,str(ROOT/'tools/qa/geometry_audit.py'),str(net),'--output',str(new),*extra],capture_output=True,text=True)
            self.assertEqual(run().returncode,0);report.write_bytes(new.read_bytes())
            data['edges'][0]['pts'][1]=[101,0];net.write_text(json.dumps(data))
            self.assertEqual(run('--baseline',str(report)).returncode,1)
            self.assertEqual(json.loads(new.read_text())['summary']['regressions'],1)
            report.write_bytes(new.read_bytes())
            data['edges'][0]['pts'][1]=[102,0];net.write_text(json.dumps(data))
            self.assertEqual(run('--baseline',str(report)).returncode,1)
            data['id']='different';net.write_text(json.dumps(data))
            self.assertEqual(run('--baseline',str(report)).returncode,2)
    def test_missing_provenance_rejected(self):
        ob=self.obstacle();del ob['provenance']
        with self.assertRaisesRegex(ValueError,'provenance'):g.swept(self.edge(),self.plan(),[ob])

if __name__=='__main__':unittest.main()
