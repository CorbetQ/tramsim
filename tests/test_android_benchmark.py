import copy
import importlib.util
import json
import subprocess
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('android_benchmark',ROOT/'tools/perf/android_benchmark.py')
b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)

class AndroidBenchmark(unittest.TestCase):
    def bundle(self):
        return {'schema_version':1,'kind':'android_performance_capture','progress_unchanged':True,
                'device':{'serial':'fixture','properties':{'model':'fixture'},'low_power_setting':'0','physical_hardware_evidence':False,'is_emulator':False},
                'app':{'status':'completed','configuration':{'seed':7,'phases':['night']},
                       'metadata':{'sample_source':'synthetic_fixture','os':'Linux','rendering_method':'gl_compatibility','display_driver':'headless','network_sha256':'a'*64},
                       'measurements':{'night':{'frametime_ms':{'p95':40}}}}}
    def test_package_and_serial_injection_rejected(self):
        for text in ['fr.tramsim;rm -rf /','x/y','not a package']:
            with self.assertRaises(ValueError):b.package_name(text)
        with self.assertRaises(ValueError):b.Adb(serial='device;echo bad')
        with self.assertRaises(ValueError):b.identifier('../report')
    def test_safe_request_uses_stdin(self):
        calls=[]
        def runner(args,**kwargs):
            calls.append((args,kwargs));return subprocess.CompletedProcess(args,0,b'',b'')
        adb=b.Adb(serial='test_device',runner=runner)
        request={'prompt':'literal $() `text` ; never a shell fragment'}
        adb.request('fr.tramsim.game',request)
        self.assertEqual(json.loads(calls[-1][1]['input']),request)
        self.assertNotIn('literal',' '.join(calls[-1][0]))
        self.assertFalse(calls[-1][1].get('shell',False))
    def test_battery_units_and_missing_values(self):
        x=b.parse_battery('  temperature: 315\n level: 80\n')
        self.assertEqual(x['battery_temperature_c'],31.5)
        self.assertEqual(x['battery_level_percent'],80)
        self.assertIsNone(b.parse_battery(None)['battery_temperature_c'])
    def test_missing_save_differs_from_denied_access(self):
        def missing(args,**kwargs):return subprocess.CompletedProcess(args,1,b'',b'No such file or directory')
        adb=b.Adb(runner=missing)
        self.assertIsNone(adb.read_private('fr.tramsim.game','files/save.json',missing_ok=True))
        def denied(args,**kwargs):return subprocess.CompletedProcess(args,1,b'',b'Permission denied')
        adb=b.Adb(runner=denied)
        with self.assertRaises(RuntimeError):adb.read_private('fr.tramsim.game','files/save.json',missing_ok=True)
        with self.assertRaises(ValueError):adb.read_private('fr.tramsim.game','files/../../other')
    def test_comparison_does_not_claim_a_phone(self):
        first=self.bundle();second=copy.deepcopy(first);second['app']['measurements']['night']['frametime_ms']['p95']=20
        result=b.compare(first,second)
        self.assertEqual(result['frametime_p95']['night']['delta_percent'],-50)
        self.assertEqual(result['scope'],'fixture_or_unverified_device')
    def test_incomparable_device_power_or_scenario_rejected(self):
        for kind in ('device','power','seed','coverage','renderer'):
            first=self.bundle();second=copy.deepcopy(first)
            if kind=='device':second['device']['serial']='other'
            elif kind=='power':second['device']['low_power_setting']='1'
            elif kind=='seed':second['app']['configuration']['seed']=8
            elif kind=='coverage':second['app']['measurements']={}
            else:second['app']['metadata']['rendering_method']='mobile'
            with self.assertRaises(ValueError):b.compare(first,second)
    def test_incomplete_or_progress_mutation_rejected(self):
        first=self.bundle();second=copy.deepcopy(first);second['progress_unchanged']=False
        with self.assertRaises(ValueError):b.compare(first,second)
        second=copy.deepcopy(first);second['app']['status']='sample_limit'
        with self.assertRaises(ValueError):b.compare(first,second)
    def test_no_fake_zero_when_no_frames(self):
        first=self.bundle();first['app']['measurements']['night']['frametime_ms']['p95']=None
        with self.assertRaises(ValueError):b.compare(first,first)
    def test_emulator_is_not_physical(self):
        class Fake:
            def text(self,*args):
                return '1' if args[-1]=='ro.kernel.qemu' else 'fixture'
        self.assertTrue(b.device_metadata(Fake(),'emulator-5554')['is_emulator'])
        self.assertFalse(b.device_metadata(Fake(),'emulator-5554')['physical_hardware_evidence'])
    def test_bad_capture_config_rejected_before_adb(self):
        class Args:
            restart=True;run_id='fixture';package='fr.tramsim.game';activity='org.godotengine.godot.GodotApp'
            network='res://data/free/angers.json';phase_seconds=float('nan');warmup_frames=10;view_distance=400;frame_budget_ms=33;timeout=300
        with self.assertRaisesRegex(ValueError,'out of range'):b.capture(Args())
    def test_restart_is_never_implicit(self):
        class Args:restart=False
        with self.assertRaisesRegex(ValueError,'--restart'):b.capture(Args())

if __name__=='__main__':unittest.main()
