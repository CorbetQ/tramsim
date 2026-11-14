"""Regression: a model name must never silently capture a different audio family."""
import json
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def probe(family, variant, bank):
    return subprocess.run(
        ['godot', '--headless', '--path', str(ROOT), '--quit-after', '1',
         '--script', 'tools/audio/capture_driving_audio.gd', '--',
         family, variant, 'profile_probe_unused', bank],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20,
    )


class CaptureProfiles(unittest.TestCase):
    def test_noncanonical_305_is_rejected(self):
        result = probe('citadis_305', 'toulouse__citadis_305', 'citadis305_model')
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertIn('CAPTURE_INVALID_FAMILY|citadis_305', result.stdout)

    def test_mismatched_variant_is_rejected(self):
        result = probe('citadis_302', 'toulouse__citadis_305', 'citadis302')
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertIn('CAPTURE_INVALID_VARIANT', result.stdout)

    def test_mismatched_bank_is_rejected(self):
        result = probe('citadis_x05', 'toulouse__citadis_305', 'citadis302')
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertIn('CAPTURE_INVALID_BANK', result.stdout)

    def test_canonical_profiles_are_actually_selected(self):
        paths = {}
        for family, variant, bank in [
            ('citadis_302', 'angers__citadis_302', 'rotterdam_citadis_traction'),
            ('citadis_x05', 'toulouse__citadis_305', 'citadis305_model'),
        ]:
            result = probe(family, variant, bank)
            self.assertEqual(result.returncode, 0, result.stdout)
            line = next(line for line in result.stdout.splitlines()
                        if line.startswith('CAPTURE_PROFILE|'))
            _, actual_family, actual_bank, streams = line.split('|', 3)
            self.assertEqual(actual_family, family)
            self.assertEqual(actual_bank, bank)
            paths[family] = json.loads(streams)
        self.assertNotEqual(paths['citadis_302']['motor'], paths['citadis_x05']['motor'])
        self.assertNotEqual(paths['citadis_302']['motor_hum'], paths['citadis_x05']['motor_hum'])


if __name__ == '__main__':
    unittest.main()
