#!/usr/bin/env python3
"""Lissage des tracés de voie (polylignes GTFS) des réseaux : supprime les pics, allers-retours et
décrochements, simplifie le bruit (Douglas-Peucker) puis arrondit chaque angle par un arc de cercle
borné (rayon RADIUS_M). Les arêtes enchaînées sans aiguillage (1 entrée, 1 sortie) sont lissées
ensemble pour que les jonctions restent tangentes ; chaque arête garde ses extrémités partagées,
son identifiant et sa longueur de jeu (`length`) : NetworkLoader.point_on ramène l'abscisse à la
longueur géométrique, donc rendu et position des rames restent cohérents.

Usage : smooth_tracks.py FICHIER_OU_DOSSIER... (réécrit les JSON sur place ; idempotent).
Ne pas appliquer à data/free (régénéré par merge_city.py à partir de data/networks).
"""
import json, math, os, sys

RADIUS_M = 28.0        # rayon d'arrondi visé aux angles
DP_TOL = 0.35          # tolérance de simplification (bruit GTFS)
SPIKE_DEG = 115.0      # demi-tour : sommet supprimé
JOG_DEG = 40.0         # décrochement : deux virages opposés rapprochés
JOG_LEN = 25.0
ARC_STEP = 3.0         # pas des sommets sur les arcs


def _turn(a, b, c):
    ux, uz = b[0] - a[0], b[1] - a[1]
    vx, vz = c[0] - b[0], c[1] - b[1]
    lu, lv = math.hypot(ux, uz), math.hypot(vx, vz)
    if lu < 1e-9 or lv < 1e-9:
        return 0.0
    cr = (ux * vz - uz * vx) / (lu * lv)
    dt = (ux * vx + uz * vz) / (lu * lv)
    return math.atan2(cr, dt)


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
            L = math.hypot(dx, dz) or 1e-9
            best, bk = -1.0, -1
            for k in range(i + 1, j):
                d = abs((p[k][0] - ax) * dz - (p[k][1] - az) * dx) / L
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
        if keep[i] or abs(th) < math.radians(1.0):
            out.append(b); continue
        la, lc = math.dist(a, b), math.dist(b, c)
        d = min(0.45 * la, 0.45 * lc, RADIUS_M * math.tan(abs(th) / 2))
        r = d / math.tan(abs(th) / 2)
        ua = ((b[0] - a[0]) / la, (b[1] - a[1]) / la)
        uc = ((c[0] - b[0]) / lc, (c[1] - b[1]) / lc)
        p0 = (b[0] - ua[0] * d, b[1] - ua[1] * d)
        n = max(2, int(math.ceil(abs(th) * r / ARC_STEP)) + 1)
        # arc de p0 à p1 : centre à gauche/droite selon le signe du virage
        sg = 1.0 if th > 0 else -1.0
        nx, nz = -ua[1] * sg, ua[0] * sg
        cx, cz = p0[0] + nx * r, p0[1] + nz * r
        a0 = math.atan2(p0[1] - cz, p0[0] - cx)
        for k in range(n):
            ang = a0 + th * k / (n - 1)
            out.append((cx + math.cos(ang) * r, cz + math.sin(ang) * r))
    out.append(p[-1])
    return _dedupe(out, 0.05)


def smooth_polyline(p, fixed=()):
    p = _dedupe([tuple(q) for q in p])
    if len(p) < 3:
        return p
    fixed = set(fixed) | {0, len(p) - 1}
    p, keep = _clean(p, fixed)
    p, keep = _dp(p, keep, DP_TOL)
    return _fillet(p, keep)


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


def _cut(p, cum, s0, s1, a, b):
    out = [a]
    for i in range(len(p)):
        if s0 + 1e-6 < cum[i] < s1 - 1e-6:
            out.append(p[i])
    out.append(b)
    return _dedupe(out, 0.05)


def smooth_network(d):
    edges = {e["id"]: e for e in d["edges"] if not e.get("raw") and len(e.get("pts", [])) >= 2}
    n_in, n_out = {}, {}
    for e in edges.values():
        n_out.setdefault(e["from"], []).append(e["id"])
        n_in.setdefault(e["to"], []).append(e["id"])

    def through(node):
        """Nœud traversé sans aiguillage ni rebroussement (terminus) : les deux arêtes sont lissées ensemble."""
        if len(n_in.get(node, [])) != 1 or len(n_out.get(node, [])) != 1:
            return False
        a, b = edges[n_in[node][0]]["pts"], edges[n_out[node][0]]["pts"]
        if math.dist(a[-1], b[0]) > 0.5:
            return False
        return abs(math.degrees(_turn(a[-2], a[-1], b[1]))) < 45.0

    seen, chains = set(), []
    for eid, e in edges.items():
        if eid in seen:
            continue
        # remonter au début de la chaîne
        cur = e
        guard = 0
        while through(cur["from"]) and n_in[cur["from"]][0] not in seen and n_in[cur["from"]][0] != eid and guard < 10000:
            cur = edges[n_in[cur["from"]][0]]; guard += 1
        chain = []
        while cur["id"] not in seen:
            chain.append(cur["id"]); seen.add(cur["id"])
            if not through(cur["to"]):
                break
            cur = edges[n_out[cur["to"]][0]]
        chains.append(chain)
    stats = {"edges": len(edges), "chains": len(chains), "pts_in": 0, "pts_out": 0}
    for chain in chains:
        pts, joints, jpos = [], [], []
        for k, eid in enumerate(chain):
            ep = [tuple(q) for q in edges[eid]["pts"]]
            stats["pts_in"] += len(ep)
            if k > 0:
                joints.append(ep[0]); ep = ep[1:]
            pts += ep
        if len(pts) < 3:
            continue
        cum0 = _cum(pts)
        for j in joints:
            jpos.append(_project(pts, cum0, j, 0.0, cum0[-1])[0] / max(cum0[-1], 1e-9))
        sm = smooth_polyline(pts)
        cum = _cum(sm)
        tot = cum[-1]
        cuts = [(0.0, sm[0])]
        for f, j in zip(jpos, joints):
            win = max(60.0, 0.1 * tot)
            s, q = _project(sm, cum, j, max(cuts[-1][0], f * tot - win), f * tot + win)
            s = max(s, cuts[-1][0])
            cuts.append((s, q))
        cuts.append((tot, sm[-1]))
        for k, eid in enumerate(chain):
            (s0, a), (s1, b) = cuts[k], cuts[k + 1]
            piece = _cut(sm, cum, s0, s1, a, b)
            if len(piece) < 2 or s1 - s0 < 0.5:
                continue  # arête dégénérée : géométrie d'origine conservée
            edges[eid]["pts"] = [[round(x, 2), round(z, 2)] for x, z in piece]
            stats["pts_out"] += len(piece)
    return stats


def main(paths):
    files = []
    for p in paths:
        if os.path.isdir(p):
            files += [os.path.join(p, f) for f in sorted(os.listdir(p)) if f.endswith(".json")]
        else:
            files.append(p)
    for f in files:
        if os.sep + "free" + os.sep in os.path.abspath(f):
            print(f"{f}: ignoré (data/free)"); continue
        d = json.load(open(f))
        if not d.get("edges"):
            continue
        st = smooth_network(d)
        with open(f, "w") as fh:
            json.dump(d, fh, ensure_ascii=False, separators=(",", ":"))
        print(f"{os.path.basename(f)}: {st}")


if __name__ == "__main__":
    main(sys.argv[1:])
