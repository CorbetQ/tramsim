"""Production inventory and corruption/path checks for the HD stock pipeline."""
import importlib.util
import json
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('audit_stock', ROOT / 'tools/models/stock/audit_stock.py')
audit_stock = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit_stock)


class StockAssets(unittest.TestCase):
    def test_shipped_banks_have_measured_budgets_and_complete_textures(self):
        result = audit_stock.audit()
        self.assertEqual(result['errors'], [])
        self.assertTrue({'angers__citadis_x05', 'angers__citadis_302',
                         'nantes__citadis_x05_nantes'}.issubset(result['variants']))
        for files in result['variants'].values():
            self.assertEqual(len(files), 10)
            self.assertLess(files['LOD0_mobile']['triangles'], files['LOD0_pc']['triangles'])
            self.assertLess(files['LOD3_pc']['triangles'], files['LOD1_pc']['triangles'])
            self.assertTrue(files['LOD0_pc']['textures'])

    def test_truncated_download_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'broken.glb'
            path.write_bytes(b'glTF')
            with self.assertRaisesRegex(ValueError, 'Truncated'):
                audit_stock.glb_info(path)

    def test_texture_cannot_escape_asset_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp) / 'train'
            directory.mkdir()
            (Path(tmp) / 'outside.png').write_bytes(b'outside')
            with self.assertRaisesRegex(ValueError, 'unsafe'):
                audit_stock.local_file(directory, '../outside.png')

    def test_missing_texture_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, 'Missing'):
                audit_stock.local_file(Path(tmp), 'missing.png')

    def test_plausible_manifest_cannot_override_plan_dimensions_or_doors(self):
        original = Path.read_text
        for field, value in [('width_m', 1.0), ('doors', 99)]:
            with self.subTest(field=field):
                def altered(path, *args, **kwargs):
                    text = original(path, *args, **kwargs)
                    if path.name == 'manifest.json':
                        data = json.loads(text)
                        next(iter(data['variants'].values()))[field] = value
                        return json.dumps(data)
                    return text
                with patch.object(Path, 'read_text', altered):
                    errors = audit_stock.audit()['errors']
                self.assertTrue(any('source plan' in error for error in errors), errors)
