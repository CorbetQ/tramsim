"""Recolle l'altitude des voies aux nœuds partagés (médiane des extrémités incidentes) avec raccord
progressif sur 20 m dans chaque arête, après lissage du profil. Usage : python tools/import/unify_node_heights.py data/free/*.json"""
import json, math, sys, statistics, collections
TAPER = 20.0
for path in sys.argv[1:]:
    raw = open(path).read(); net = json.loads(raw)
    acc = collections.defaultdict(list)
    edges = [e for e in net.get('edges', []) if e.get('y') and len(e['y']) == len(e.get('pts', []))]
    for e in edges:
        acc[e['from']].append(e['y'][0]); acc[e['to']].append(e['y'][-1])
    target = {k: statistics.median(v) for k, v in acc.items() if max(v) - min(v) > 0.005}
    n = 0
    for e in edges:
        pts, y = e['pts'], e['y']
        arc = [0.0]
        for a, b in zip(pts, pts[1:]): arc.append(arc[-1] + math.dist(a, b))
        L = arc[-1]
        for end, node in ((0, e['from']), (-1, e['to'])):
            if node not in target: continue
            d = target[node] - y[end]
            if abs(d) < 1e-6: continue
            n += 1
            span = min(TAPER, L * 0.45) if L > 0 else 0.0
            for i in range(len(y)):
                s = arc[i] if end == 0 else L - arc[i]
                w = 1.0 if s <= 0 else (max(0.0, 1.0 - s / span) if span > 0 else 0.0)
                if w > 0: y[i] = round(y[i] + d * w, 3)
            y[end] = round(target[node], 3)
    if n:
        compact = not raw.lstrip().startswith('{\n')
        open(path, 'w').write(json.dumps(net, ensure_ascii=False, separators=(',', ':')) if compact else json.dumps(net, ensure_ascii=False, indent=1))
        print(path, n, 'extrémités recollées')
