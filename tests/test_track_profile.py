"""Profil en long régulier (tools/import/smooth_profile.py) : pas de « montagnes russes ».
Mesures (tools/qa/profile_metrics.py) par ville sur data/networks et data/free :
- variation de pente entre deux fenêtres consécutives de 20 m : max <= 11 %, 99e centile <= 9 %
  (avant lissage : jusqu'à 14,3 % et 11,6 %) ;
- inversions de pente (> 0,5 %) sur 200 m glissants : au plus 4 (avant : jusqu'à 9 à Nantes).
Les maxima restants sont aux points fixes (quais, aiguillages) et aux rampes bornées à 8,8 %."""
import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "qa"))
import profile_metrics  # noqa: E402


class TrackProfile(unittest.TestCase):
    def test_profile_regularity(self):
        bad = []
        for city, m in profile_metrics.metrics(sorted(
                [os.path.join(ROOT, "data/networks", f) for f in os.listdir(os.path.join(ROOT, "data/networks")) if f.endswith(".json")]
                + [os.path.join(ROOT, "data/free", f) for f in os.listdir(os.path.join(ROOT, "data/free")) if f.endswith(".json")])).items():
            if m["dgrade20_max_pct"] > 11.0 or m["dgrade20_p99_pct"] > 9.0 or m["inv200_max"] > 4:
                bad.append((city, m))
        self.assertEqual(bad, [], bad)


if __name__ == "__main__":
    unittest.main()
