"""Validate current encoded assets, not superseded pre-design segment hashes."""
import json
import sys
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/audio'))
from studio_lib import banks, catalogue


class AudioBanks(unittest.TestCase):
    def test_measured_derivatives_and_provenance(self):
        result = catalogue.validate(ROOT, waveforms=True)
        self.assertEqual(result['errors'], [])
        result = banks.validate(ROOT, waveforms=True)
        self.assertEqual(result['errors'], [])
        entries = catalogue.catalogue(ROOT)['catalogue']
        for row in entries.values():
            with self.subTest(asset=row['id']):
                self.assertIn(row['kind'], {'recorded_exact', 'recorded_related', 'modeled', 'synthetic', 'ai_generated'})
                self.assertGreater(row['duration_s'], 0)
                if row['license'] != 'LicenseRef-TramSim-Original':
                    self.assertTrue(row['author']); self.assertTrue(row['source_url'].startswith('https://'))

    def test_all_families_and_budget(self):
        manifest = json.loads((ROOT / 'data/audio/families.json').read_text())
        plans = {p.stem for p in (ROOT / 'data/rolling_stock/plans').glob('*.json')}
        self.assertEqual(set(manifest['profiles']), plans)
        size = sum(p.stat().st_size for p in (ROOT / 'data/audio').rglob('*.ogg') if 'reference' not in p.parts)
        self.assertLess(size, 10 * 1024 * 1024)


if __name__ == '__main__':
    unittest.main()
