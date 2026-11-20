#!/usr/bin/env python3
"""Ponts des réseaux physiques (data/free/<ville>.json, tram-trains compris) : profil des voies et tronçons de pont
d'après les ouvrages ferroviaires BD TOPO (troncon_de_voie_ferree, position_par_rapport_au_sol > 0, Z des tronçons).

Les altitudes des voies physiques sont interpolées (pas de relevé ferroviaire) : sur un pont absent des profils, la
voie suivait le fond de la vallée (ex. tram-train sur le pont ferroviaire de la Loire à Nantes, rail sous l'eau).
Pour chaque arête : échantillons à moins de 4 m d'un tronçon ferroviaire au-dessus du sol, parallèle (|cos| >= 0,9),
-> plages de pont (>= 15 m) dont le Z (lissé, jamais sous la corde entre culées) dépasse le profil de MIN_GAP m ;
profil relevé à ce Z,
raccordé de part et d'autre par une rampe <= RAMP (sur l'arête et ses voisines via les nœuds partagés). Les plages
sont ajoutées à « bridge ». Identifiants, longueurs et quais inchangés.

Usage : TERRAIN_CACHE=<cache> free_bridges.py [VILLE...]
"""
import json, math, os, sys
from collections import defaultdict

import numpy as np
from scipy.spatial import cKDTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import terrain as T                   # noqa: E402

ROOT = T.ROOT
MIN_GAP = 1.5
RAMP = 0.035
MIN_SPAN = 15.0


def rail_bridges(frame, cache, llb):
    P, D, Z = [], [], []
    for f in T.cached_features("troncon_de_voie_ferree", cache, llb):
        pr = f["properties"]
        if not f.get("geometry") or T.pos_sol(pr) <= 0:
            continue
        for l in T.lines3d(f["geometry"], frame):
            ok = np.isfinite(l[:, 2])
            if ok.sum() < 2:
                continue
            q = np.array(T.densify(l[:, :2].tolist(), 2.0))
            s0 = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(l[:, :2], axis=0), axis=1))])
            sq = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(q, axis=0), axis=1))])
            z = np.interp(sq, s0[ok], l[ok, 2])
            d = np.gradient(q, axis=0)
            d /= np.maximum(np.linalg.norm(d, axis=1), 1e-6)[:, None]
            P.append(q); D.append(d); Z.append(z)
    if not P:
        return None
    return np.concatenate(P), np.concatenate(D), np.concatenate(Z)


def fix(city):
    path = os.path.join(ROOT, "data/free", city + ".json")
    if not os.path.exists(path):
        return None
    net = json.load(open(path))
    alt0 = float(net.get("alt0", 0.0))
    frame = T.Frame(*net["origin"])
    allp = np.concatenate([np.array(e["pts"]) for e in net["edges"] if len(e.get("pts", [])) >= 2])
    lo, hi = allp.min(0) - 100, allp.max(0) + 100
    la0, lo0 = frame.inv(lo[0], hi[1]); la1, lo1 = frame.inv(hi[0], lo[1])
    rb = rail_bridges(frame, os.path.join(T.SCRATCH, "ign_cache"), (min(la0, la1), min(lo0, lo1), max(la0, la1), max(lo0, lo1)))
    if rb is None:
        return {"ponts": 0}
    BP, BD, BZ = rb
    tree = cKDTree(BP)
    target = {}                      # edge id -> (s (m), y cible, masque pont)
    st = defaultdict(float)
    for e in net["edges"]:
        p = np.array(e["pts"], dtype=np.float64); y = np.array(e["y"], dtype=np.float64)
        if len(p) < 2 or len(y) != len(p):
            continue
        s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(p, axis=0), axis=1))])
        d = np.gradient(p, axis=0); d /= np.maximum(np.linalg.norm(d, axis=1), 1e-6)[:, None]
        dist, idx = tree.query(p, distance_upper_bound=4.0)
        ok = np.isfinite(dist)
        idx = np.minimum(idx, len(BP) - 1)
        par = np.abs((d * BD[idx]).sum(1)) >= 0.9
        zt = BZ[idx] - alt0
        m = ok & par
        if not m.any():
            continue
        # plages contiguës d'au moins MIN_SPAN m
        spans, i = [], 0
        while i < len(m):
            if m[i]:
                j = i
                while j + 1 < len(m) and m[j + 1]:
                    j += 1
                if s[j] - s[i] >= MIN_SPAN:
                    spans.append((i, j))
                i = j + 1
            else:
                i += 1
        if not spans:
            continue
        yt = y.copy(); mask = np.zeros(len(m), bool); keep = []
        for i, j in spans:
            zs = np.convolve(np.pad(zt[i:j + 1], 3, mode="edge"), np.ones(7) / 7, mode="valid")
            # jamais sous la corde entre culées (Z BD TOPO parfois interpolé au niveau de l'eau en milieu de travée)
            zs = np.maximum(zs, np.interp(s[i:j + 1], [s[i], s[j]], [zs[0], zs[-1]]))
            if np.max(zs - y[i:j + 1]) < MIN_GAP:
                continue                 # profil déjà au niveau de l'ouvrage
            yt[i:j + 1] = np.maximum(zs, y[i:j + 1]); mask[i:j + 1] = True; keep.append((i, j))
        spans = keep
        if not spans:
            continue
        target[e["id"]] = (s, yt, mask, spans)
    if not target:
        return {"ponts": 0}
    # relèvement : profil = max(profil, rampe depuis les plages de pont), propagé aux arêtes voisines par les nœuds
    E = {e["id"]: e for e in net["edges"]}
    lift = {}                        # edge id -> nouveau y
    for eid, (s, yt, mask, spans) in target.items():
        e = E[eid]; y = np.array(e["y"], dtype=np.float64)
        ny = y.copy()
        for k in np.where(mask)[0]:
            ny = np.maximum(ny, yt[k] - np.abs(s - s[k]) * RAMP)
        ny[mask] = yt[mask]
        lift[eid] = ny
        L = float(e["length"]); k = L / max(s[-1], 1e-6)
        e.setdefault("bridge", [])
        for i, j in spans:
            e["bridge"].append([round(s[i] * k, 3), round(s[j] * k, 3)])
        e["bridge"] = _merge(e["bridge"])
        st["ponts"] += len(spans); st["m"] += sum(s[j] - s[i] for i, j in spans)
        st["releve_max_m"] = max(st["releve_max_m"], float(np.max(ny - y)))
    # propagation par les nœuds (rampe RAMP le long des arêtes voisines), quelques passes
    by_node = defaultdict(list)
    for e in net["edges"]:
        by_node[e["from"]].append((e["id"], 0)); by_node[e["to"]].append((e["id"], -1))
    for _ in range(6):
        changed = False
        for node, lst in by_node.items():
            h = max(float((lift[eid] if eid in lift else np.array(E[eid]["y"]))[end]) for eid, end in lst)
            for eid, end in lst:
                y = lift[eid] if eid in lift else np.array(E[eid]["y"], dtype=np.float64)
                if y[end] >= h - 0.01:
                    continue
                p = np.array(E[eid]["pts"], dtype=np.float64)
                s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(p, axis=0), axis=1))])
                dd = s if end == 0 else s[-1] - s
                lift[eid] = np.maximum(y, h - dd * RAMP); changed = True
        if not changed:
            break
    for eid, ny in lift.items():
        E[eid]["y"] = [round(float(v), 3) for v in ny]
        g = E[eid].get("grade")
        if g is not None and len(ny) > 1:
            E[eid]["grade"] = round(float((ny[-1] - ny[0]) / max(float(E[eid]["length"]), 1e-6)), 5)
    st["aretes"] = len(lift)
    json.dump(net, open(path, "w"), ensure_ascii=False, separators=(",", ":"))
    open(path, "a").write("\n")
    return {k: round(v, 2) if isinstance(v, float) else v for k, v in st.items()}


def _merge(spans):
    spans = sorted([list(map(float, s[:2])) for s in spans])
    out = []
    for a, b in spans:
        if out and a <= out[-1][1] + 1.0:
            out[-1][1] = max(out[-1][1], b)
        else:
            out.append([a, b])
    return out


if __name__ == "__main__":
    cities = sys.argv[1:] or sorted(f[:-5] for f in os.listdir(os.path.join(ROOT, "data/free")) if f.endswith(".json"))
    for c in cities:
        try:
            print(c, fix(c), flush=True)
        except Exception as err:
            print(c, "ECHEC", repr(err)[:200], flush=True)
