#!/usr/bin/env python3
"""Régularité du profil en long des voies (data/networks, data/free) : « montagnes russes ».

Par arête, profil rééchantillonné tous les 5 m (hors tunnels et ponts exclus ? non : profil complet), puis :
- dgrade20 : variation de pente maximale entre deux fenêtres consécutives de 20 m (‰ -> %) ;
- inv200 : nombre maximal d'inversions de pente (fenêtres de 20 m, pentes de plus de 0,5 % de signes opposés)
  sur 200 m glissants.
Usage : profile_metrics.py [--json] [fichiers...]   (défaut : tous les réseaux). Sortie par ville (max, p99).
"""
import glob, json, math, os, sys
from collections import defaultdict

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
STEP = 5.0


def edge_metrics(e):
    p = np.array(e.get("pts", []), dtype=np.float64); y = np.array(e.get("y", []), dtype=np.float64)
    if len(p) < 2 or len(y) != len(p):
        return None
    s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(p, axis=0), axis=1))])
    if s[-1] < 60.0:
        return None
    ss = np.arange(0.0, s[-1], STEP)
    yy = np.interp(ss, s, y)
    k = int(20.0 / STEP)
    if len(yy) <= 2 * k:
        return None
    g = (yy[k:] - yy[:-k]) / 20.0                      # pente sur 20 m glissants
    dg = np.abs(g[k:] - g[:-k])                        # variation entre fenêtres consécutives
    sign = np.where(g > 0.005, 1, np.where(g < -0.005, -1, 0))
    # inversions : changements de signe (en ignorant les paliers)
    nz = [(i, v) for i, v in enumerate(sign) if v != 0]
    flips = [nz[j][0] for j in range(1, len(nz)) if nz[j][1] != nz[j - 1][1]]
    w = int(200.0 / STEP)
    inv = 0
    for i, f in enumerate(flips):
        inv = max(inv, sum(1 for f2 in flips[i:] if f2 - f < w))
    return float(dg.max()) if len(dg) else 0.0, inv


def city_of(path, net):
    return str(net.get("source_id") or os.path.basename(path).split("_")[0].split(".")[0])


def metrics(paths):
    out = defaultdict(lambda: {"dgrade20": [], "inv200": []})
    for path in paths:
        net = json.load(open(path))
        c = city_of(path, net)
        for e in net.get("edges", []):
            m = edge_metrics(e)
            if m:
                out[c]["dgrade20"].append(m[0]); out[c]["inv200"].append(m[1])
    res = {}
    for c, d in sorted(out.items()):
        a = np.array(d["dgrade20"]); b = np.array(d["inv200"])
        res[c] = {"dgrade20_max_pct": round(float(a.max()) * 100, 2), "dgrade20_p99_pct": round(float(np.percentile(a, 99)) * 100, 2),
                  "inv200_max": int(b.max()), "inv200_p99": float(np.percentile(b, 99))}
    return res


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    paths = args or sorted(glob.glob(os.path.join(ROOT, "data/networks/*.json")) + glob.glob(os.path.join(ROOT, "data/free/*.json")))
    r = metrics(paths)
    if "--json" in sys.argv:
        print(json.dumps(r, indent=1))
    else:
        for c, v in r.items():
            print(c, v)
