import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools/models/stock'))
try:
    spec=importlib.util.spec_from_file_location('audit_parts',ROOT/'tools/models/stock/audit_parts.py')
    parts=importlib.util.module_from_spec(spec);spec.loader.exec_module(parts)
finally:sys.path.pop(0)


class IndependentBodyAssets(unittest.TestCase):
    def test_inventory_includes_bound_hardware_and_interior_textures(self):
        report=parts.audit()
        paths=report['texture_files']
        self.assertTrue(any(name.endswith('/metal_normal.png') for name in paths))
        self.assertTrue(any('/interior/' in name for name in paths))

    def test_entire_catalogue_has_measured_independent_models(self):
        report=parts.audit()
        entries=json.loads((ROOT/'data/rolling_stock/variants/index.json').read_text())['entries']
        self.assertEqual(report['errors'],[])
        self.assertEqual(set(report['variants']),{e['id'] for e in entries})
        self.assertEqual(report['bodies'],sum(e['module_count'] for e in entries))
        # Prototypes are actually shared. HD kits (P4: whole catalogue) ship one file per LOD/profile for each
        # prototype, so count prototypes (file stem without its LOD suffix), not files.
        import re
        prototypes={re.sub(r'_lod\d(_m)?$','',str(Path(name).with_suffix(''))) for name in report['model_files']}
        self.assertLess(len(prototypes),report['bodies'])
        self.assertTrue(all(len(v['sha256'])==64 for v in report['model_files'].values()))

    def test_paths_cannot_escape_their_asset_category(self):
        for value in ['res://tram_parts/../../project.godot','res://src/ui/main.gd','https://example.com/model.glb']:
            with self.subTest(value=value),self.assertRaises(ValueError):parts.resource(ROOT,value,'tram_parts')

    def test_wrong_body_order_is_rejected(self):
        original=Path.read_text
        def swapped(path,*args,**kwargs):
            text=original(path,*args,**kwargs)
            if path.parent.name=='compositions' and path.suffix=='.json':
                data=json.loads(text);data['layout'][0]=data['layout'][-1]
                return json.dumps(data)
            return text
        with patch.object(Path,'read_text',swapped):report=parts.audit()
        self.assertTrue(any('body order' in error for error in report['errors']),report['errors'])

    def test_missing_native_model_is_not_hidden_by_the_legacy_fallback(self):
        original=Path.read_text
        def missing(path,*args,**kwargs):
            text=original(path,*args,**kwargs)
            if path.parent.name=='compositions' and path.suffix=='.json':
                data=json.loads(text)
                # P4: every kit is HD; a missing LOD file must be reported exactly like a missing native body.
                models=next(iter(data['parts'].values()))['models']
                models[next(iter(models))]='res://tram_parts/absent.scn' if data['renderer']=='native' else 'res://tram_parts/absent.glb'
                return json.dumps(data)
            return text
        with patch.object(Path,'read_text',missing):report=parts.audit()
        self.assertTrue(any('Missing' in error for error in report['errors']),report['errors'])

    def test_symlink_cannot_escape_allowed_root(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);(root/'tram_parts').mkdir();outside=root/'outside';outside.write_text('x')
            (root/'tram_parts/link.scn').symlink_to(outside)
            with self.assertRaises(ValueError):parts.resource(root,'res://tram_parts/link.scn','tram_parts')
