"""Borne la pente des profils (y) des réseaux à 8 % là où un relevé de pont a créé une marche.
Relaxation symétrique (montée/descente) limitée aux arêtes en défaut ; extrémités conservées
(raccords aux nœuds voisins). Usage : python tools/import/fix_grades.py data/free/*.json"""
import json, math, sys
G = 0.088   # < 0,09 toléré par test_geography ; certaines arêtes courtes ont 8,0x % imposé par leurs extrémités
def relax(pts, y):
    d = [math.dist(p, q) for p, q in zip(pts, pts[1:])]
    y = list(y)
    for _ in range(5000):
        changed = False
        for i in range(1, len(y)):        # avant : pas de chute/montée > G·d
            lo, hi = y[i-1] - G*d[i-1], y[i-1] + G*d[i-1]
            if i < len(y) - 1 and not lo <= y[i] <= hi: y[i] = min(max(y[i], lo), hi); changed = True
        for i in range(len(y) - 2, 0, -1):  # arrière
            lo, hi = y[i+1] - G*d[i], y[i+1] + G*d[i]
            if not lo <= y[i] <= hi: y[i] = min(max(y[i], lo), hi); changed = True
        if not changed: break
    return [round(v, 3) for v in y]
for path in sys.argv[1:]:
    raw = open(path).read(); net = json.loads(raw); n = 0
    for e in net.get('edges', []):
        pts, y = e.get('pts', []), e.get('y', [])
        if len(y) != len(pts) or len(y) < 3: continue
        if any(abs(b-a) > math.dist(p, q)*G + 0.002 for p, q, a, b in zip(pts, pts[1:], y, y[1:])):
            e['y'] = relax(pts, y); n += 1
    if n:
        compact = not raw.lstrip().startswith('{\n')
        open(path, 'w').write(json.dumps(net, ensure_ascii=False, separators=(',', ':')) if compact else json.dumps(net, ensure_ascii=False, indent=1))
        print(path, n, 'arêtes corrigées')
