#!/usr/bin/env python3
"""Profil en long lissé des voies (data/networks, data/free) : supprime les « montagnes russes » (bruit du MNT
LiDAR, relevés de ponts, bornage de pente fix_grades.py) en gardant les points fixes.

Par arête (profil rééchantillonné tous les 2 m) :
- filtre gaussien longitudinal (sigma SIGMA m, ~100 m d'étendue efficace) ;
- lissage par chaînes d'arêtes à travers les nœuds de degré 2 (pas de cassure aux nœuds), points fixes : extrémités
  de chaîne (aiguillages, terminus) et quais (station ± demi-quai + 15 m) ;
  l'écart (profil d'origine - profil lissé) aux points fixes est réparti linéairement entre eux (raccords
  doux, pas de marche) ;
- pente bornée ensuite à G (relaxation de fix_grades.py), 8,8 % comme ce dernier.
Les ponts et trémies suivent le profil lissé (tabliers recalés à l'exécution, CityScene._fit_decks_to_tracks).
Les identifiants, longueurs, tracés et quais ne changent pas.

Usage : smooth_profile.py [fichiers...]   (défaut : data/networks/*.json et data/free/*.json)
"""
import glob, json, math, os, sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SIGMA = 30.0
STEP = 2.0
G = 0.088
QUAI = 25.0          # m, demi-longueur de quai par défaut (rame ~ 40 m) + marge ajoutée dessous


def gauss(y, sigma_samples):
    r = int(3 * sigma_samples)
    if r < 1:
        return y
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma_samples) ** 2); k /= k.sum()
    pad = np.concatenate([np.full(r, y[0]), y, np.full(r, y[-1])])
    # extrémités : prolongement linéaire (pas d'aplatissement artificiel aux nœuds)
    if len(y) >= 3:
        g0 = y[1] - y[0]; g1 = y[-1] - y[-2]
        pad[:r] = y[0] - g0 * np.arange(r, 0, -1); pad[-r:] = y[-1] + g1 * np.arange(1, r + 1)
    return np.convolve(pad, k, mode="valid")


def relax(s, y):
    d = np.diff(s)
    y = y.copy()
    for _ in range(2000):
        changed = False
        for i in range(1, len(y) - 1):
            lo, hi = y[i - 1] - G * d[i - 1], y[i - 1] + G * d[i - 1]
            if not lo <= y[i] <= hi:
                y[i] = min(max(y[i], lo), hi); changed = True
        for i in range(len(y) - 2, 0, -1):
            lo, hi = y[i + 1] - G * d[i], y[i + 1] + G * d[i]
            if not lo <= y[i] <= hi:
                y[i] = min(max(y[i], lo), hi); changed = True
        if not changed:
            break
    return y


def smooth_edge(e, fixed_spans):
    p = np.array(e["pts"], dtype=np.float64); y = np.array(e["y"], dtype=np.float64)
    s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(p, axis=0), axis=1))])
    if s[-1] < 30.0:
        return None
    L = float(e.get("length", s[-1])) or s[-1]
    k = s[-1] / L
    ss = np.linspace(0.0, s[-1], max(3, int(math.ceil(s[-1] / STEP)) + 1))
    yy = np.interp(ss, s, y)
    ys = gauss(yy, SIGMA / (ss[1] - ss[0]))
    fixed = np.zeros(len(ss), bool); fixed[0] = fixed[-1] = True
    for a, b in fixed_spans:
        fixed |= (ss >= a * k) & (ss <= b * k)
    r = np.where(fixed, yy - ys, np.nan)
    idx = np.where(fixed)[0]
    corr = np.interp(ss, ss[idx], r[idx])
    out = ys + corr
    out[fixed] = yy[fixed]
    new = np.interp(s, ss, out)
    new[0], new[-1] = y[0], y[-1]
    new = relax(s, new)
    return new


def chains(edges):
    """Chaînes d'arêtes à travers les nœuds de degré 2 : [(arête, sens)] ; cycles ouverts à un nœud quelconque."""
    inc = {}
    for e in edges:
        inc.setdefault(e["from"], []).append(e); inc.setdefault(e["to"], []).append(e)
    used, out = set(), []

    def walk(node, e):
        ch = []
        while e is not None and e["id"] not in used:
            used.add(e["id"])
            fwd = e["from"] == node
            ch.append((e, fwd))
            node = e["to"] if fwd else e["from"]
            nxt = [x for x in inc.get(node, []) if x["id"] not in used]
            e = nxt[0] if len(inc.get(node, [])) == 2 and nxt else None
        return ch
    for n, lst in inc.items():
        if len(lst) != 2:
            for e in lst:
                if e["id"] not in used:
                    out.append(walk(n, e))
    for e in edges:
        if e["id"] not in used:
            out.append(walk(e["from"], e))
    return out


def process(path):
    net = json.load(open(path))
    st_spans = {}
    for st in net.get("stations", []):
        half = QUAI + 15.0
        st_spans.setdefault(st.get("edge"), []).append((float(st.get("offset", 0.0)) - half, float(st.get("offset", 0.0)) + half))
    edges = [e for e in net.get("edges", []) if len(e.get("pts", [])) >= 2 and len(e.get("y", [])) == len(e["pts"])]
    n, dmax = 0, 0.0
    for ch in chains(edges):
        # profil de la chaîne : abscisse cumulée, altitudes, points fixes (extrémités de chaîne, quais)
        S, Y, F, parts = [], [], [], []
        base = 0.0
        for e, fwd in ch:
            p = np.array(e["pts"], dtype=np.float64); y = np.array(e["y"], dtype=np.float64)
            s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(p, axis=0), axis=1))])
            L = float(e.get("length", s[-1])) or s[-1]; k = s[-1] / L if L > 0 else 1.0
            fx = np.zeros(len(s), bool)
            for a, b in st_spans.get(e["id"], []):
                fx |= (s >= a * k) & (s <= b * k)
            if not fwd:
                s = s[-1] - s[::-1]; y = y[::-1]; fx = fx[::-1]
            parts.append((e, fwd, len(S), len(s), s[-1]))
            S.extend((base + s).tolist()); Y.extend(y.tolist()); F.extend(fx.tolist())
            base += s[-1]
        S = np.array(S); Y = np.array(Y); F = np.array(F)
        if base < 30.0:
            continue
        # quais : profil plan (droite des moindres carrés sur la zone), bruit du relevé retiré
        o = np.argsort(S, kind="stable"); i = 0
        while i < len(o):
            if F[o[i]]:
                j = i
                while j + 1 < len(o) and F[o[j + 1]]:
                    j += 1
                run = o[i:j + 1]
                if S[run].max() - S[run].min() > 10.0:
                    a, b = np.polyfit(S[run], Y[run], 1)
                    fit = a * S[run] + b
                    if np.abs(fit - Y[run]).max() < 0.25:
                        Y[run] = fit
                i = j + 1
            else:
                i += 1
        F[0] = F[-1] = True
        order = np.argsort(S, kind="stable")
        ss = np.linspace(0.0, base, max(3, int(math.ceil(base / STEP)) + 1))
        yy = np.interp(ss, S[order], Y[order])
        ys = gauss(yy, SIGMA / (ss[1] - ss[0]))
        fixed = np.interp(ss, S[order], F[order].astype(float)) > 0.5
        fixed[0] = fixed[-1] = True
        idx = np.where(fixed)[0]
        corr = np.interp(ss, ss[idx], (yy - ys)[idx])
        out = ys + corr
        out[fixed] = yy[fixed]
        new = np.interp(S, ss, out)
        new[0], new[-1] = Y[0], Y[-1]   # extrémités de chaîne (aiguillages, terminus) inchangées
        for e, fwd, i0, cnt, _ in parts:
            seg = new[i0:i0 + cnt]
            sl = S[i0:i0 + cnt] - S[i0]
            seg = relax(sl, seg) if cnt >= 3 else seg
            if not fwd:
                seg = seg[::-1]
            old = np.array(e["y"], dtype=np.float64)
            seg[0], seg[-1] = (old[0], old[-1]) if (len(ch) == 1) else (seg[0], seg[-1])
            dmax = max(dmax, float(np.abs(seg - old).max()))
            # pente bornée dans l'ordre des points de l'arête (après retournement), extrémités fixes
            pp = np.array(e["pts"], dtype=np.float64)
            so = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(pp, axis=0), axis=1))])
            seg = relax(so, np.array(seg, dtype=np.float64))
            e["y"] = [round(float(v), 3) for v in seg]
            if "grade" in e and float(e.get("length", 0)) > 0:
                e["grade"] = round((e["y"][-1] - e["y"][0]) / float(e["length"]), 5)
            n += 1
    raw = open(path).read()
    compact = "\n" not in raw.strip()
    with open(path, "w") as f:
        if compact:
            f.write(json.dumps(net, ensure_ascii=False, separators=(",", ":")) + ("\n" if raw.endswith("\n") else ""))
        else:
            json.dump(net, f, ensure_ascii=False, indent=1)
            if raw.endswith("\n"):
                f.write("\n")
    return n, round(dmax, 2)


if __name__ == "__main__":
    paths = sys.argv[1:] or sorted(glob.glob(os.path.join(ROOT, "data/networks/*.json")) + glob.glob(os.path.join(ROOT, "data/free/*.json")))
    for p in paths:
        print(os.path.basename(p), *process(p), flush=True)
