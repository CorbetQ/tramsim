"""Vérifie les fichiers auxquels se rapportent les mesures de construction."""
import hashlib
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class AudioBanks(unittest.TestCase):
    def test_measured_derivatives_and_provenance(self):
        manifest = json.loads((ROOT / 'data/audio/families.json').read_text())
        credits = (ROOT / 'CREDITS.md').read_text()
        for bank in manifest['banks'].values():
            with self.subTest(bank=bank['label']):
                source = bank['source']
                self.assertIn(source['page'], credits)
                self.assertTrue(source['author'])
                self.assertTrue(source['license_url'].startswith('https://'))
                self.assertEqual(len(source['sha256']), 64)
                for key, relative in bank['streams'].items():
                    data = (ROOT / 'data/audio' / relative).read_bytes()
                    segment = bank['segments'][key]
                    self.assertEqual(hashlib.sha256(data).hexdigest(), segment['sha256'])
                    self.assertEqual(data[:4], b'OggS')
                    self.assertLessEqual(abs(segment['lufs'] + 20), 1.5)
                    self.assertLessEqual(segment['true_peak_dbfs'], -1.0)
                    self.assertGreater(segment['duration_s'], 3.0)
                    self.assertLess(segment['duration_s'], 6.0)

    def test_all_families_and_budget(self):
        manifest = json.loads((ROOT / 'data/audio/families.json').read_text())
        plans = {p.stem for p in (ROOT / 'data/rolling_stock/plans').glob('*.json')}
        self.assertEqual(set(manifest['profiles']), plans)
        size = sum(p.stat().st_size for p in (ROOT / 'data/audio').rglob('*.ogg')
                   if 'reference' not in p.parts)
        self.assertLess(size, 10 * 1024 * 1024)


if __name__ == '__main__':
    unittest.main()
