#!/usr/bin/env python3
"""Lissage des tracés de voie (data/networks : polylignes GTFS sur l'axe commun ; data/free : axes OSM physiques).

Chaîne de traitement (v2) :
1. Nettoyage : pics (demi-tours), allers-retours et décrochements supprimés ; Douglas-Peucker (bruit GTFS/OSM).
2. Arrondi de chaque angle par un arc tangent de rayon RADIUS_M au plus (borné par 45 % des segments voisins).
3. Raccordements progressifs : rééchantillonnage métrique puis filtre gaussien (sigma SIGMA_M) sur la position ;
   la courbure passe linéairement de 0 à 1/R sur ~3 sigma (équivalent discret d'une clothoïde), écart à l'axe
   d'origine de quelques décimètres.
4. Continuité aux nœuds : chaque nœud reçoit une tangente (celle du tronc à un aiguillage, la moyenne sinon) ;
   les extrémités d'arête y sont raccordées par une cubique d'Hermite (point et cap exacts). Les arêtes enchaînées
   sans aiguillage (un départ de chaque côté) sont lissées ensemble : la courbure reste continue au droit des stations.
5. Échantillonnage adaptatif : variation de cap <= ANG_MAX_DEG entre segments consécutifs (sommets serrés en courbe,
   espacés en alignement), coordonnées au millimètre.

Chaque arête garde son identifiant, ses nœuds, ses côtés et sa longueur de jeu (`length`) : NetworkLoader.point_on
ramène l'abscisse à la longueur géométrique, donc stations, quais, limites, ouvrages et signaux restent valides.
Les arêtes "raw" (communications déjà sur l'axe de voie) ne sont pas modifiées. Le profil "y" est réinterpolé à
abscisse relative égale. Idempotent : le fichier porte "track_smoothing" et n'est pas relissé.

Usage : smooth_tracks.py [--force] [--report] FICHIER_OU_DOSSIER...
"""
import json, math, os, sys

import numpy as np

VERSION = 2
RADIUS_M = 25.0        # rayon d'arrondi visé aux angles (tram urbain : 20 à 25 m au plus serré)
DP_TOL = 0.30          # tolérance de simplification
SPIKE_DEG = 115.0      # demi-tour : sommet supprimé
JOG_DEG = 40.0         # décrochement : deux virages opposés rapprochés
JOG_LEN = 25.0
ARC_STEP = 1.0         # pas des sommets sur les arcs (avant filtrage)
H = 0.25               # pas du rééchantillonnage métrique
SIGMA_M = 3.0          # filtre gaussien : longueur des raccordements progressifs ~ 3 sigma
BLEND_MIN, BLEND_MAX = 6.0, 30.0   # raccord d'Hermite aux nœuds
ANG_MAX_DEG = 0.8      # variation de cap maximale couverte par un segment
SEG_MIN_REL = 0.7e-5   # longueur minimale relative à la distance à l'origine : les coordonnées sont en float32
                       # dans le moteur (Vector2) ; à 47 km de l'origine (Nantes), 0,33 m : erreur de cap ~1° au pire
SEG_MAX = 10.0         # longueur maximale d'un segment en alignement
R_HARD = 2.5           # rayon en deçà duquel un raccord court est jugé absurde (extrémité libérée)
TANGENT_MAX_DEG = 50.0 # au-delà, la branche n'est pas une continuation du nœud : extrémité libre


def _turn(a, b, c):
    ux, uz = b[0] - a[0], b[1] - a[1]
    vx, vz = c[0] - b[0], c[1] - b[1]
    lu, lv = math.hypot(ux, uz), math.hypot(vx, vz)
    if lu < 1e-9 or lv < 1e-9:
        return 0.0
    return math.atan2((ux * vz - uz * vx) / (lu * lv), (ux * vx + uz * vz) / (lu * lv))


def _unit(v):
    L = math.hypot(v[0], v[1])
    return (v[0] / L, v[1] / L) if L > 1e-9 else None


def _angle(u, v):
    return math.degrees(math.acos(max(-1.0, min(1.0, u[0] * v[0] + u[1] * v[1]))))


def _dedupe(p, eps=0.3):
    out = [p[0]]
    for q in p[1:-1]:
        if math.dist(q, out[-1]) > eps:
            out.append(q)
    if len(p) > 1:
        if len(out) > 1 and math.dist(p[-1], out[-1]) <= eps:
            out[-1] = p[-1]
        else:
            out.append(p[-1])
    return out


def _clean(p, fixed):
    """Supprime pics (demi-tours) et décrochements ; `fixed` = indices à ne pas toucher (extrémités)."""
    p = [tuple(q) for q in p]
    keep = [i in fixed for i in range(len(p))]
    changed = True
    while changed and len(p) > 2:
        changed = False
        for i in range(1, len(p) - 1):
            if keep[i]:
                continue
            if abs(math.degrees(_turn(p[i - 1], p[i], p[i + 1]))) > SPIKE_DEG:
                del p[i]; del keep[i]; changed = True; break
            if i + 2 < len(p) and not keep[i + 1] and math.dist(p[i], p[i + 1]) < JOG_LEN:
                t1, t2 = _turn(p[i - 1], p[i], p[i + 1]), _turn(p[i], p[i + 1], p[i + 2])
                if abs(math.degrees(t1)) > JOG_DEG and abs(math.degrees(t2)) > JOG_DEG and t1 * t2 < 0:
                    del p[i:i + 2]; del keep[i:i + 2]; changed = True; break
    return p, keep


def _dp(p, keep, tol):
    """Douglas-Peucker en conservant les sommets marqués."""
    n = len(p)
    mark = [False] * n
    mark[0] = mark[-1] = True
    for i, k in enumerate(keep):
        if k:
            mark[i] = True
    anchors = [i for i in range(n) if mark[i]]
    for a, b in zip(anchors, anchors[1:]):
        stack = [(a, b)]
        while stack:
            i, j = stack.pop()
            if j <= i + 1:
                continue
            ax, az = p[i]; bx, bz = p[j]
            dx, dz = bx - ax, bz - az
            L = math.hypot(dx, dz)
            best, bk = -1.0, -1
            for k in range(i + 1, j):
                # corde dégénérée (boucle fermée) : distance au point d'ancrage
                d = abs((p[k][0] - ax) * dz - (p[k][1] - az) * dx) / L if L > 1e-6 else math.dist(p[k], p[i])
                if d > best:
                    best, bk = d, k
            if best > tol:
                mark[bk] = True
                stack += [(i, bk), (bk, j)]
    return [p[i] for i in range(n) if mark[i]], [keep[i] for i in range(n) if mark[i]]


def _fillet(p, keep):
    """Remplace chaque angle par un arc tangent (coupe bornée par 45 % des segments voisins)."""
    if len(p) < 3:
        return list(p)
    out = [p[0]]
    for i in range(1, len(p) - 1):
        a, b, c = p[i - 1], p[i], p[i + 1]
        th = _turn(a, b, c)
        if keep[i] or abs(th) < math.radians(0.5):
            out.append(b); continue
        la, lc = math.dist(a, b), math.dist(b, c)
        d = min(0.45 * la, 0.45 * lc, RADIUS_M * math.tan(abs(th) / 2))
        r = d / math.tan(abs(th) / 2)
        ua = ((b[0] - a[0]) / la, (b[1] - a[1]) / la)
        p0 = (b[0] - ua[0] * d, b[1] - ua[1] * d)
        n = max(2, int(math.ceil(abs(th) * r / ARC_STEP)) + 1)
        sg = 1.0 if th > 0 else -1.0
        cx, cz = p0[0] - ua[1] * sg * r, p0[1] + ua[0] * sg * r
        a0 = math.atan2(p0[1] - cz, p0[0] - cx)
        for k in range(n):
            ang = a0 + th * k / (n - 1)
            out.append((cx + math.cos(ang) * r, cz + math.sin(ang) * r))
    out.append(p[-1])
    return _dedupe(out, 0.05)


def smooth_polyline(p, fixed=()):
    """Étapes 1-2 (nettoyage, arrondis circulaires) ; conservé pour les outils qui l'importent."""
    p = _dedupe([tuple(q) for q in p])
    if len(p) < 3:
        return p
    fixed = set(fixed) | {0, len(p) - 1}
    p, keep = _clean(p, fixed)
    p, keep = _dp(p, keep, DP_TOL)
    return _fillet(p, keep)


def _resample(p, h):
    """Rééchantillonnage à pas constant (dernier point exact)."""
    a = np.asarray(p, float)
    seg = np.hypot(*np.diff(a, axis=0).T)
    cum = np.concatenate([[0.0], np.cumsum(seg)])
    L = cum[-1]
    n = max(2, int(math.ceil(L / h)) + 1)
    s = np.linspace(0.0, L, n)
    return np.stack([np.interp(s, cum, a[:, 0]), np.interp(s, cum, a[:, 1])], axis=1), L


def _gauss(a, h, sigma, t0, t1):
    """Filtre gaussien de la polyligne régulière `a` ; prolongements fantômes rectilignes aux extrémités (t0 : cap au
    départ, t1 : cap à l'arrivée, dans le sens de parcours)."""
    k = int(math.ceil(3.0 * sigma / h))
    if k < 1 or len(a) < 3:
        return a
    steps = np.arange(1, k + 1)[:, None] * h
    head = a[0] - steps[::-1] * np.asarray(t0)
    tail = a[-1] + steps * np.asarray(t1)
    ext = np.concatenate([head, a, tail])
    x = np.arange(-k, k + 1) * h
    w = np.exp(-0.5 * (x / sigma) ** 2); w /= w.sum()
    return np.stack([np.convolve(ext[:, 0], w, "valid"), np.convolve(ext[:, 1], w, "valid")], axis=1)


def _hermite(p0, m0, p1, m1, n):
    t = np.linspace(0.0, 1.0, n)[:, None]
    t2, t3 = t * t, t * t * t
    return ((2 * t3 - 3 * t2 + 1) * p0 + (t3 - 2 * t2 + t) * m0 + (-2 * t3 + 3 * t2) * p1 + (t3 - t2) * m1)


def _dir_at(a, i, span=4):
    j0, j1 = max(0, i - span), min(len(a) - 1, i + span)
    return _unit(a[j1] - a[j0])


def _end_dir(a, start, dist=3.0):
    """Cap moyen sur les `dist` premiers (ou derniers) mètres, dans le sens de parcours."""
    if start:
        for q in a[1:]:
            if math.dist(q, a[0]) >= dist:
                return _unit((q[0] - a[0][0], q[1] - a[0][1]))
        return _unit((a[-1][0] - a[0][0], a[-1][1] - a[0][1]))
    for q in reversed(a[:-1]):
        if math.dist(q, a[-1]) >= dist:
            return _unit((a[-1][0] - q[0], a[-1][1] - q[1]))
    return _unit((a[-1][0] - a[0][0], a[-1][1] - a[0][1]))


def smooth_curve(pts, t0=None, t1=None):
    """Courbe lisse de pts[0] à pts[-1] (points exacts) ; t0/t1 : caps imposés aux extrémités (sens de parcours),
    None = cap naturel. Retourne une polyligne dense (pas H)."""
    p = _dedupe([tuple(q) for q in pts], 0.05)
    if len(p) < 2:
        return p
    if len(p) >= 3:
        p, keep = _clean(p, {0, len(p) - 1})
        p, keep = _dp(p, keep, DP_TOL)
        p = _fillet(p, keep)
    a, L = _resample(p, H)
    n0 = _end_dir(p, True) or (1.0, 0.0)
    n1 = _end_dir(p, False) or n0
    g0, g1 = (t0 or n0), (t1 or n1)
    # courte : une seule cubique d'Hermite
    dev0 = _angle(g0, n0) if t0 else 0.0
    dev1 = _angle(g1, n1) if t1 else 0.0
    b0 = min(BLEND_MAX, max(BLEND_MIN, math.radians(dev0) * RADIUS_M * 1.6)) if t0 else 0.0
    b1 = min(BLEND_MAX, max(BLEND_MIN, math.radians(dev1) * RADIUS_M * 1.6)) if t1 else 0.0
    b0, b1 = max(b0, 2.0 * SIGMA_M), max(b1, 2.0 * SIGMA_M)
    if L < 3.0 * SIGMA_M or b0 + b1 > 0.8 * L:
        # raccord court entre deux nœuds : cubique d'Hermite ; si les caps imposés exigent un rayon absurde
        # (raccourci OSM entre aiguillages de dépôt), l'extrémité la plus déviée est libérée.
        n = max(3, int(math.ceil(16.0 * L / H)) + 1)
        best = None
        for c0, c1 in ((g0, g1), (g0, n1) if dev1 >= dev0 else (n0, g1), (n0, g1) if dev1 >= dev0 else (g0, n1), (n0, n1)):
            cur = _hermite(a[0], np.asarray(c0) * L, a[-1], np.asarray(c1) * L, n)
            r = _min_radius(cur)
            if best is None or r > best[0]:
                best = (r, cur)
            if r >= R_HARD:
                break
        return [tuple(q) for q in best[1]]
    f = _gauss(a, H, SIGMA_M, g0, g1)
    f[0], f[-1] = a[0], a[-1]
    # raccords d'Hermite : point exact et cap imposé (ou naturel) aux extrémités
    for start, b, g in ((True, b0, g0), (False, b1, g1)):
        k = min(len(f) - 2, max(2, int(round(b / H))))
        if start:
            q = f[k]; tq = _dir_at(f, k) or g
            seg = _hermite(a[0], np.asarray(g) * b, q, np.asarray(tq) * b, 16 * k + 1)
            f = np.concatenate([seg, f[k + 1:]])
        else:
            i = len(f) - 1 - k
            q = f[i]; tq = _dir_at(f, i) or g
            seg = _hermite(q, np.asarray(tq) * b, a[-1], np.asarray(g) * b, 16 * k + 1)
            f = np.concatenate([f[:i], seg])
    return [tuple(q) for q in f]


def _min_radius(c):
    """Rayon minimal d'une polyligne dense (cercle circonscrit à trois points espacés d'environ 1 m)."""
    c = np.asarray(c, float)
    if len(c) < 3:
        return math.inf
    seg = np.hypot(*np.diff(c, axis=0).T)
    step = max(1, int(round(1.0 / max(float(np.median(seg)), 1e-3))))
    a, b, d = c[:-2 * step], c[step:-step], c[2 * step:]
    if len(a) == 0:
        return math.inf
    cr = np.abs((b[:, 0] - a[:, 0]) * (d[:, 1] - a[:, 1]) - (b[:, 1] - a[:, 1]) * (d[:, 0] - a[:, 0]))
    la, lb, lc = np.hypot(*(b - a).T), np.hypot(*(d - b).T), np.hypot(*(d - a).T)
    r = la * lb * lc / np.maximum(2.0 * cr, 1e-12)
    return float(r.min())


def refine(d, ang_max=0.5, passes=8):
    """Subdivision à 4 points (Dyn-Levin-Gregory, w = 1/16) des segments encadrés par un virage > ang_max : courbes
    très serrées (faisceaux de dépôt, raccords courts entre aiguillages) sans cassure de cap."""
    lim = math.radians(ang_max)
    for _ in range(passes):
        n = len(d)
        if n < 3:
            return d
        bad = [False] * n
        for i in range(1, n - 1):
            bad[i] = abs(_turn(d[i - 1], d[i], d[i + 1])) > lim
        if not any(bad):
            return d
        out = [d[0]]
        for i in range(n - 1):
            if (bad[i] or bad[i + 1]) and 0 < i < n - 2 and math.dist(d[i], d[i + 1]) > 0.02:   # segments d'extrémité intacts : cap au nœud exact
                # extrémités : extrapolation quadratique (cap d'extrémité conservé)
                p0 = d[i - 1] if i > 0 else (3 * d[0][0] - 3 * d[1][0] + d[2][0], 3 * d[0][1] - 3 * d[1][1] + d[2][1])
                p3 = d[i + 2] if i + 2 < n else (3 * d[-1][0] - 3 * d[-2][0] + d[-3][0], 3 * d[-1][1] - 3 * d[-2][1] + d[-3][1])
                p1, p2 = d[i], d[i + 1]
                out.append(((-p0[0] + 9 * p1[0] + 9 * p2[0] - p3[0]) / 16.0, (-p0[1] + 9 * p1[1] + 9 * p2[1] - p3[1]) / 16.0))
            out.append(d[i + 1])
        d = out
    return d


def decimate(d, ang_max=ANG_MAX_DEG, seg_max=SEG_MAX):
    """Sommets gardés tels que chaque segment s'écarte d'au plus ang_max/2 du cap de la courbe dense qu'il remplace
    (deux segments consécutifs diffèrent donc d'au plus ~ang_max) et mesure au plus seg_max mètres."""
    n = len(d)
    if n <= 2:
        return list(d)
    hd = [math.atan2(d[i + 1][1] - d[i][1], d[i + 1][0] - d[i][0]) for i in range(n - 1)]
    lim = math.radians(ang_max) * 0.5

    def ok(k, j):
        c = math.atan2(d[j][1] - d[k][1], d[j][0] - d[k][0])
        if math.dist(d[k], d[j]) > seg_max:
            return False
        return all(abs((hd[m] - c + math.pi) % (2 * math.pi) - math.pi) <= lim for m in range(k, j))

    out = [d[0]]; k = 0
    while k < n - 1:
        j = k + 1
        smin = min(0.35, max(0.03, SEG_MIN_REL * math.hypot(d[k][0], d[k][1])))
        while j + 1 < n and (ok(k, j + 1) or math.dist(d[k], d[j]) < smin):
            j += 1
        out.append(d[j]); k = j
    return out


def _round(piece):
    """Millimètre ; dixième de millimètre près des segments très courts (courbes de dépôt) pour que l'arrondi
    n'introduise pas de cassure de cap."""
    out = []
    for i, (x, z) in enumerate(piece):
        short = (i > 0 and math.dist(piece[i - 1], piece[i]) < 0.5) or (i + 1 < len(piece) and math.dist(piece[i], piece[i + 1]) < 0.5)
        r = 4 if short else 3
        q = [round(x, r), round(z, r)]
        if out and 0 < i < len(piece) - 1 and math.dist(q, out[-1]) < 0.02:
            continue   # sommet trop proche : le bruit d'arrondi y ferait une cassure de cap
        if out and i == len(piece) - 1 and len(out) > 1 and math.dist(q, out[-1]) < 0.02:
            out.pop()
        out.append(q)
    return out


def _cum(p):
    c = [0.0]
    for i in range(1, len(p)):
        c.append(c[-1] + math.dist(p[i - 1], p[i]))
    return c


def _project(p, cum, q, s_lo, s_hi):
    """Projection de q sur la polyligne, restreinte à l'abscisse [s_lo, s_hi]. -> (abscisse, point)."""
    best = (1e18, 0.0, p[0])
    for i in range(len(p) - 1):
        if cum[i + 1] < s_lo or cum[i] > s_hi:
            continue
        ax, az = p[i]; bx, bz = p[i + 1]
        dx, dz = bx - ax, bz - az
        L2 = dx * dx + dz * dz
        t = 0.0 if L2 < 1e-12 else max(0.0, min(1.0, ((q[0] - ax) * dx + (q[1] - az) * dz) / L2))
        x, z = ax + dx * t, az + dz * t
        d = (x - q[0]) ** 2 + (z - q[1]) ** 2
        if d < best[0]:
            best = (d, cum[i] + t * math.sqrt(L2), (x, z))
    return best[1], best[2]


def _interp_y(old_pts, ys, new_pts):
    """Profil en long réinterpolé à abscisse relative égale."""
    c0 = _cum([tuple(q) for q in old_pts]); c1 = _cum(new_pts)
    if c0[-1] < 1e-6 or c1[-1] < 1e-6:
        return [ys[0]] * len(new_pts)
    f = np.asarray(c1) / c1[-1] * c0[-1]
    return [round(float(v), 3) for v in np.interp(f, c0, ys)]


def _sides(e):
    return int(e.get("from_side", 1)), int(e.get("to_side", -1))


def _outward(e, end):
    p = [tuple(q) for q in e["pts"]]
    return _end_dir(p, True) if end == "from" else _end_dir(list(reversed(p)), True)


def node_tangents(edges, all_edges):
    """Tangente de chaque nœud (vers son côté +1) et attachements {nœud: {côté: [(arête, extrémité)]}}."""
    att = {}
    raw_nodes = set()
    for e in all_edges:
        if e.get("raw"):
            raw_nodes.add(e["from"]); raw_nodes.add(e["to"])
    for e in edges.values():
        fs, ts = _sides(e)
        att.setdefault(e["from"], {1: [], -1: []})[1 if fs >= 0 else -1].append((e["id"], "from"))
        att.setdefault(e["to"], {1: [], -1: []})[1 if ts >= 0 else -1].append((e["id"], "to"))
    tan = {}   # (arête, extrémité) -> cap imposé, orienté vers l'extérieur de l'arête
    for node, s in att.items():
        P = [(x, _outward(edges[x[0]], x[1])) for x in s[1]]
        M = [(x, _outward(edges[x[0]], x[1])) for x in s[-1]]
        P = [q for q in P if q[1]]; M = [q for q in M if q[1]]
        if not P or not M:
            continue
        if len(P) == 1 or len(M) == 1:
            # aiguillage (ou simple continuité) : la tangente du tronc s'impose aux branches
            if len(P) == 1 and len(M) == 1:
                T = _unit((P[0][1][0] - M[0][1][0], P[0][1][1] - M[0][1][1]))
            elif len(P) == 1:
                T = P[0][1]
            else:
                T = (-M[0][1][0], -M[0][1][1])
            if not T:
                continue
            for x, u in P:
                if _angle(u, T) <= TANGENT_MAX_DEG: tan[x] = T
            for x, u in M:
                if _angle(u, (-T[0], -T[1])) <= TANGENT_MAX_DEG: tan[x] = (-T[0], -T[1])
            continue
        # traversée / croisement / communication double : appariement des voies les mieux alignées,
        # tangente propre à chaque paire
        pairs = sorted(((_angle(p[1], (-m[1][0], -m[1][1])), pi, mi) for pi, p in enumerate(P) for mi, m in enumerate(M)))
        used_p, used_m, best_p, best_m = set(), set(), {}, {}
        for ang, pi, mi in pairs:
            if pi in used_p or mi in used_m or ang > TANGENT_MAX_DEG:
                continue
            used_p.add(pi); used_m.add(mi)
            T = _unit((P[pi][1][0] - M[mi][1][0], P[pi][1][1] - M[mi][1][1]))
            if T:
                tan[P[pi][0]] = T; tan[M[mi][0]] = (-T[0], -T[1])
        # branches restantes : tangente de la voie la plus proche du même côté
        for grp in (P, M):
            for x, u in grp:
                if x in tan:
                    continue
                cands = [(_angle(u, tan[y]), tan[y]) for y, _v in grp if y in tan]
                if cands:
                    a, T = min(cands)
                    if a <= TANGENT_MAX_DEG: tan[x] = T
    return tan, att, raw_nodes


def smooth_network(d):
    all_edges = d["edges"]
    edges = {e["id"]: e for e in all_edges if not e.get("raw") and len(e.get("pts", [])) >= 2}
    tan, att, raw_nodes = node_tangents(edges, all_edges)

    def end_tangent(eid, end):
        """Cap imposé à l'extrémité, orienté vers l'extérieur de l'arête (None : libre)."""
        return tan.get((eid, end))

    def through(node):
        if node in raw_nodes or node not in att:
            return None
        s = att[node]
        if len(s[1]) != 1 or len(s[-1]) != 1 or s[1][0][0] == s[-1][0][0]:
            return None
        a, b = s[1][0], s[-1][0]
        ua, ub = _outward(edges[a[0]], a[1]), _outward(edges[b[0]], b[1])
        if not ua or not ub or _angle(ua, (-ub[0], -ub[1])) > 45.0:
            return None
        pa = edges[a[0]]["pts"][0 if a[1] == "from" else -1]
        pb = edges[b[0]]["pts"][0 if b[1] == "from" else -1]
        if math.dist(pa, pb) > 0.5:
            return None
        return s

    def other(node, eid, end):
        s = through(node)
        if s is None:
            return None
        a, b = s[1][0], s[-1][0]
        return b if a == (eid, end) else a if b == (eid, end) else None

    seen, chains = set(), []
    for eid in edges:
        if eid in seen:
            continue
        # remonter au début : on parcourt l'arête depuis 'from' ; l'extrémité amont est 'from'
        cur, start_end = eid, "from"
        guard = 0
        while guard < 100000:
            o = other(edges[cur][start_end], cur, start_end)
            if o is None or o[0] == eid or o[0] in seen:
                break
            # o = (arête voisine, extrémité raccordée) ; on remonte : nouvelle extrémité amont = l'autre extrémité
            cur, start_end = o[0], ("to" if o[1] == "from" else "from")
            guard += 1
        chain = []
        while cur not in seen:
            rev = start_end == "to"
            chain.append((cur, rev)); seen.add(cur)
            far = "from" if rev else "to"
            o = other(edges[cur][far], cur, far)
            if o is None:
                break
            cur, start_end = o[0], o[1]
        chains.append(chain)

    stats = {"edges": len(edges), "chains": len(chains), "pts_in": 0, "pts_out": 0}
    for chain in chains:
        pts, joints = [], []
        for k, (eid, rev) in enumerate(chain):
            ep = [tuple(q) for q in edges[eid]["pts"]]
            if rev:
                ep.reverse()
            stats["pts_in"] += len(ep)
            if k > 0:
                joints.append(pts[-1]); ep = ep[1:]
            pts += ep
        e0, r0 = chain[0]; e1, r1 = chain[-1]
        t0 = end_tangent(e0, "to" if r0 else "from")
        t1 = end_tangent(e1, "from" if r1 else "to")
        if t1:
            t1 = (-t1[0], -t1[1])   # sens de parcours à l'arrivée
        dense = refine(_dedupe(smooth_curve(pts, t0, t1), 0.01))
        if len(dense) < 2:
            continue
        cum = _cum(dense); tot = cum[-1]
        cum0 = _cum(pts)
        cuts = [(0, dense[0])]
        for j in joints:
            f = _project(pts, cum0, j, 0.0, cum0[-1])[0] / max(cum0[-1], 1e-9)
            win = max(40.0, 0.05 * tot)
            s, _q = _project(dense, cum, j, max(cum[cuts[-1][0]], f * tot - win), f * tot + win)
            i = min(range(len(cum)), key=lambda m: abs(cum[m] - s))
            i = max(i, cuts[-1][0] + 1)
            cuts.append((i, dense[min(i, len(dense) - 1)]))
        cuts.append((len(dense) - 1, dense[-1]))
        for k, (eid, rev) in enumerate(chain):
            i0, i1 = cuts[k][0], cuts[k + 1][0]
            if i1 - i0 < 1:
                continue  # arête dégénérée : géométrie d'origine conservée
            piece = decimate(dense[i0:i1 + 1])
            if rev:
                piece.reverse()
            e = edges[eid]
            old = e["pts"]
            new = _round(piece)
            if isinstance(e.get("y"), list) and len(e["y"]) == len(old):
                e["y"] = _interp_y(old, e["y"], [tuple(q) for q in new])
            e["pts"] = new
            stats["pts_out"] += len(new)
    return stats


def metrics(d):
    """(variation de cap max entre segments consécutifs d'une arête, max aux nœuds entre arêtes enchaînables)."""
    edges = {e["id"]: e for e in d["edges"] if not e.get("raw") and len(e.get("pts", [])) >= 2}
    mx = 0.0
    for e in edges.values():
        p = e["pts"]
        for i in range(1, len(p) - 1):
            mx = max(mx, abs(math.degrees(_turn(p[i - 1], p[i], p[i + 1]))))
    _tan, att, _raw = node_tangents(edges, d["edges"])

    def first(x):
        p = edges[x[0]]["pts"]
        return _end_dir([tuple(q) for q in (p if x[1] == "from" else p[::-1])], True, 0.0)

    jmx = 0.0
    for node, s in att.items():
        for side in (1, -1):
            for x in s[side]:
                u = first(x)
                cands = [_angle(u, (-v[0], -v[1])) for v in (first(y) for y in s[-side]) if u and v]
                if cands and min(cands) < TANGENT_MAX_DEG:   # continuation naturelle (meilleur partenaire)
                    jmx = max(jmx, min(cands))
    return mx, jmx


def main(argv):
    force = "--force" in argv
    report = "--report" in argv
    paths = [a for a in argv if not a.startswith("--")]
    files = []
    for p in paths:
        if os.path.isdir(p):
            files += [os.path.join(p, f) for f in sorted(os.listdir(p)) if f.endswith(".json")]
        else:
            files.append(p)
    for f in files:
        d = json.load(open(f))
        if not isinstance(d, dict) or not d.get("edges"):
            continue
        if report:
            mx, jmx = metrics(d)
            print(f"{os.path.basename(f)}: max {mx:.2f}° jonctions {jmx:.2f}°")
            continue
        if d.get("track_smoothing", {}).get("version", 0) >= VERSION and not force:
            print(f"{os.path.basename(f)}: déjà lissé (v{VERSION})"); continue
        st = smooth_network(d)
        d["track_smoothing"] = {"version": VERSION, "radius_m": RADIUS_M, "sigma_m": SIGMA_M, "max_turn_deg": ANG_MAX_DEG}
        with open(f, "w") as fh:
            json.dump(d, fh, ensure_ascii=False, separators=(",", ":"))
        mx, jmx = metrics(d)
        print(f"{os.path.basename(f)}: {st} max {mx:.2f}° jonctions {jmx:.2f}°")


if __name__ == "__main__":
    main(sys.argv[1:])
