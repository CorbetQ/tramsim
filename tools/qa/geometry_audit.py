#!/usr/bin/env python3
"""Read-only geometry preflight and articulated swept-volume checks.

No network requests, no repairs, no tolerance changes in existing clearance tests.
Obstacle manifests are explicit rendered/estimated volumes, not surveyed geometry.
"""
import argparse
import gzip
import hashlib
import html
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EARTH = 6371008.8


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def finite(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


def lerp(a, b, t):
    return [x + (y - x) * t for x, y in zip(a, b)]


def polyline(edge):
    pts = edge.get('pts', [])
    heights = edge.get('y', [])
    if len(pts) < 2 or any(not isinstance(p, list) or len(p) != 2 or not all(map(finite, p)) for p in pts):
        raise ValueError('missing or invalid finite XY polyline')
    if len(heights) != len(pts) or not all(map(finite, heights)):
        raise ValueError('height count/values invalid')
    coords = [[p[0], p[1], y] for p, y in zip(pts, heights)]  # x,z,rail_y
    arc = [0.0]
    for a, b in zip(coords, coords[1:]):
        arc.append(arc[-1] + math.dist(a[:2], b[:2]))
    if arc[-1] <= 0:
        raise ValueError('zero-length geometry')
    return coords, arc


def at(coords, arc, distance):
    """Extrapolate at endpoints; neighboring-edge articulation requires an explicit route."""
    import bisect
    i = max(0, min(len(coords) - 2, bisect.bisect_right(arc, distance) - 1))
    while i < len(coords) - 2 and arc[i + 1] == arc[i]:
        i += 1
    return lerp(coords[i], coords[i + 1], (distance - arc[i]) / max(arc[i + 1] - arc[i], 1e-9))


def rectangle(center, tangent, length, width):
    dx, dz = tangent
    return [[center[0] + dx * a - dz * b, center[1] + dz * a + dx * b]
            for a, b in [(-length/2, -width/2), (length/2, -width/2), (length/2, width/2), (-length/2, width/2)]]


def orientation(a, b, c):
    return (b[0]-a[0])*(c[1]-a[1]) - (b[1]-a[1])*(c[0]-a[0])


def contains(point, ring):
    inside = False
    for a, b in zip(ring, ring[1:] + ring[:1]):
        if (a[1] > point[1]) != (b[1] > point[1]):
            cross = a[0] + (point[1]-a[1])*(b[0]-a[0])/(b[1]-a[1])
            if point[0] < cross:
                inside = not inside
    return inside


def intersects(first, second):
    for a, b in zip(first, first[1:] + first[:1]):
        for c, d in zip(second, second[1:] + second[:1]):
            # Bounding test prevents collinear, disjoint segments being mistaken for intersections.
            if (max(min(a[0],b[0]),min(c[0],d[0])) <= min(max(a[0],b[0]),max(c[0],d[0])) and
                max(min(a[1],b[1]),min(c[1],d[1])) <= min(max(a[1],b[1]),max(c[1],d[1])) and
                orientation(a,b,c)*orientation(a,b,d) <= 0 and orientation(c,d,a)*orientation(c,d,b) <= 0):
                return True
    return contains(first[0], second) or contains(second[0], first)


def finding(network, kind, edge='', point=None, severity='error', evidence=None, obstacle=None):
    identity = '|'.join([network.get('id', ''), kind, edge, str(obstacle or '')])
    origin = network.get('origin')
    geo = None
    if point is not None and isinstance(origin, list) and len(origin) == 2 and all(map(finite, origin)):
        geo = {'lat': origin[0] - math.degrees(point[1] / EARTH),
               'lon': origin[1] + math.degrees(point[0] / (EARTH * math.cos(math.radians(origin[0]))))}
    return {'id': hashlib.sha256(identity.encode()).hexdigest()[:24], 'network': network.get('id'),
            'kind': kind, 'edge': edge, 'severity': severity, 'position_xzy_m': point, 'geographic': geo,
            'status': 'open', 'classification': 'computed_graph_discrepancy', 'uncertainty_m': None, 'obstacle': obstacle, 'evidence': evidence or {}}


def swept(edge, plan, obstacles, spacing=2, margin=.1, index=None):
    coords, arc = polyline(edge)
    modules = [float(m['length_m']) for m in plan['modules']]
    if not modules or min(modules) <= 0 or not all(map(finite, modules)):
        raise ValueError('invalid vehicle module lengths')
    width, height = float(plan['width_m']), float(plan['height_m'])
    if not finite(width) or not finite(height) or min(width, height) <= 0:
        raise ValueError('invalid vehicle envelope')
    for o in obstacles if index is None else []:
        if not all(k in o for k in ['id','kind','polygon','bottom_m','top_m','provenance']):
            raise ValueError('obstacles require id, kind, polygon, heights and provenance')
        if not o['provenance']: raise ValueError('empty obstacle provenance')
        if len(o['polygon']) < 3 or any(len(p) != 2 or not all(map(finite,p)) for p in o['polygon']):
            raise ValueError('invalid obstacle polygon')
        if not finite(o['bottom_m']) or not finite(o['top_m']) or o['top_m'] < o['bottom_m']:
            raise ValueError('invalid obstacle altitude')
    hits, checks = {}, 0
    count = max(1, math.ceil(arc[-1] / spacing))
    for i in range(count + 1):
        nose, behind = arc[-1] * i / count, 0.0
        for length in modules:
            head, tail = at(coords, arc, nose-behind), at(coords, arc, nose-behind-length)
            center = lerp(head,tail,.5)
            delta = [head[0]-tail[0],head[1]-tail[1]]
            norm = math.hypot(*delta)
            tangent = [delta[0]/max(norm,1e-9),delta[1]/max(norm,1e-9)]
            ring = rectangle(center,tangent,length+2*margin,width+2*margin)
            low, high = min(head[2],tail[2])+float(plan.get('floor_m',0))-margin, max(head[2],tail[2])+height+margin
            nearby = obstacles
            if index is not None:
                ids=set()
                for x in range(math.floor(min(p[0] for p in ring)/64),math.floor(max(p[0] for p in ring)/64)+1):
                    for z in range(math.floor(min(p[1] for p in ring)/64),math.floor(max(p[1] for p in ring)/64)+1):
                        ids.update(index.get((x,z),[]))
                nearby=[obstacles[k] for k in sorted(ids)]
            for obstacle in nearby:
                checks += 1
                if obstacle['id'] in hits or high < obstacle['bottom_m'] or low > obstacle['top_m']:
                    continue
                if intersects(ring,obstacle['polygon']):
                    hits[obstacle['id']] = {'obstacle':obstacle, 'nose_offset_m':nose, 'position':center,
                                            'module_length_m':length, 'envelope_bottom_m':low, 'envelope_top_m':high}
            behind += length
    return list(hits.values()), checks



def obstacle_index(obstacles):
    # Validate through the same kernel, then construct a bounded spatial broad phase.
    fixture={'pts':[[0,0],[.1,0]],'y':[0,0]}
    plan={'width_m':1,'height_m':1,'modules':[{'length_m':.1}]}
    swept(fixture,plan,obstacles,spacing=1)
    index={};seen=set()
    for k,ob in enumerate(obstacles):
        if ob['id'] in seen: raise ValueError('duplicate obstacle identifier')
        seen.add(ob['id'])
        ring=ob['polygon']
        area=abs(sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(ring,ring[1:]+ring[:1])))/2
        if area<1e-8:raise ValueError('degenerate/self-crossing obstacle polygon')
        if len(ring)>2048:raise ValueError('polygon vertex budget exceeded')
        segments=list(zip(ring,ring[1:]+ring[:1]))
        for i,(a,b) in enumerate(segments):
            for j,(c,d) in enumerate(segments[i+1:],i+1):
                if j==i+1 or (i==0 and j==len(segments)-1):continue
                if max(min(a[0],b[0]),min(c[0],d[0]))<=min(max(a[0],b[0]),max(c[0],d[0])) and max(min(a[1],b[1]),min(c[1],d[1]))<=min(max(a[1],b[1]),max(c[1],d[1])) and orientation(a,b,c)*orientation(a,b,d)<=0 and orientation(c,d,a)*orientation(c,d,b)<=0:
                    raise ValueError('self-crossing obstacle polygon')
        x0,x1=math.floor(min(p[0] for p in ring)/64),math.floor(max(p[0] for p in ring)/64)
        z0,z1=math.floor(min(p[1] for p in ring)/64),math.floor(max(p[1] for p in ring)/64)
        if (x1-x0+1)*(z1-z0+1)>10000:raise ValueError('obstacle spatial budget exceeded')
        for x in range(x0,x1+1):
            for z in range(z0,z1+1):index.setdefault((x,z),[]).append(k)
    return index

def audit_network(net, plan=None, obstacles=None, spacing=2, horizontal=.05, vertical=.05, osm_nodes=None):
    findings, nodes, measurements = [], {}, {'edges':0,'segments':0,'swept_pairs':0}
    spatial=obstacle_index(obstacles) if plan is not None and obstacles else None
    for edge in sorted(net.get('edges',[]),key=lambda e:str(e.get('id',''))):
        eid = str(edge.get('id',''))
        try:
            coords, arc = polyline(edge)
        except (ValueError, TypeError, KeyError) as ex:
            findings.append(finding(net,'invalid_geometry',eid,evidence={'error':str(ex)})); continue
        measurements['edges'] += 1; measurements['segments'] += len(coords)-1
        for index, node in [(0,edge.get('from')),(-1,edge.get('to'))]:
            nodes.setdefault(str(node),[]).append((eid,coords[index]))
            source_id = edge.get('source',{}).get('node_from' if index==0 else 'node_to')
            if osm_nodes is not None and source_id in osm_nodes and net.get('origin'):
                osm = osm_nodes[source_id]; lat,lon = net['origin']
                expected = [math.radians(osm['lon']-lon)*EARTH*math.cos(math.radians(lat)), -math.radians(osm['lat']-lat)*EARTH]
                delta = math.dist(expected,coords[index][:2])
                if delta > horizontal:
                    findings.append(finding(net,'source_endpoint_offset:'+str(index),eid,coords[index],evidence={'osm_node':source_id,'distance_m':delta,'threshold_m':horizontal,'source':'local OSM archive'}))
        declared = edge.get('length')
        if not finite(declared) or abs(declared-arc[-1]) > max(.05,arc[-1]*.0001):
            findings.append(finding(net,'length_mismatch',eid,coords[0],evidence={'declared_m':declared if finite(declared) else repr(declared),'polyline_m':arc[-1],'length_error_m':abs(declared-arc[-1]) if finite(declared) else None}))
        for i,(a,b) in enumerate(zip(coords,coords[1:])):
            length = arc[i+1]-arc[i]
            if length < 1e-6:
                findings.append(finding(net,'duplicate_vertex:'+str(i),eid,a)); continue
            grade = abs(b[2]-a[2])/length
            if grade > .12:
                findings.append(finding(net,'grade_exceeds_policy:'+str(i),eid,a,evidence={'grade':grade,'threshold':.12,'policy':'review threshold, not manufacturer limit','elevation_source':edge.get('source',{}).get('rail_elevation')}))
        if plan is not None and obstacles:
            hits, checks = swept(edge,plan,obstacles,spacing,index=spatial)
            measurements['swept_pairs'] += checks
            for hit in hits:
                ob = hit['obstacle']
                row = finding(net,'swept_collision',eid,hit['position'],evidence={k:v for k,v in hit.items() if k not in ('obstacle','position')},obstacle=ob['id'])
                row['evidence']['provenance'] = ob['provenance'];row['evidence']['kind']=ob['kind']
                row['uncertainty_m'] = ob.get('uncertainty_m')
                row['classification']='conservative_volume_candidate_not_certified_real_collision'
                if ob.get('estimated'):row['confidence']='estimated_obstacle_requires_review'
                findings.append(row)
    for node, endpoints in sorted(nodes.items()):
        if len(endpoints) < 2: continue
        reference = endpoints[0][1]
        for eid, p in endpoints[1:]:
            h, v = math.dist(reference[:2],p[:2]),abs(reference[2]-p[2])
            if h > horizontal or v > vertical:
                findings.append(finding(net,'junction_discontinuity:'+node,eid,p,evidence={'horizontal_m':h,'vertical_m':v,'reference_edge':endpoints[0][0],'thresholds_m':[horizontal,vertical]}))
    return {'id':net.get('id'),'origin':net.get('origin'),'measurements':measurements,'findings':findings,
            'coverage':{'topology':True,'osm_reference':osm_nodes is not None,'swept_obstacles':bool(plan and obstacles),
                        'rail_route_continuity':'node endpoints; edge envelopes extrapolate at boundaries',
                        'native_rendered_clearance':'separate existing tests/run_clearance.sh; tunnels skipped there'}}



def route_edge(net, sections):
    """Only declared topological connections, never intersections inferred from XY."""
    edges = {e['id']:e for e in net['edges']}
    points, heights, previous_exit = [], [], None
    for section in sections:
        edge = edges[section['edge']]
        direction = section.get('direction',1)
        if direction not in (-1,1): raise ValueError('invalid route direction')
        entry, end = (edge['from'],edge['to']) if direction == 1 else (edge['to'],edge['from'])
        if previous_exit is not None and previous_exit != entry:
            raise ValueError('route edges are not topologically connected')
        coords,_ = polyline(edge)
        if direction == -1: coords.reverse()
        for point in coords:
            if points and points[-1] == point[:2] and heights[-1] == point[2]: continue
            points.append(point[:2]);heights.append(point[2])
        previous_exit = end
    if len(points) < 2: raise ValueError('empty route')
    return {'id':'explicit_route','from':sections[0]['edge'],'to':sections[-1]['edge'],
            'length':sum(math.dist(a,b) for a,b in zip(points,points[1:])), 'pts':points,'y':heights}


def evidence_digest(row):
    payload={'position':row['position_xzy_m'],'kind':row['kind'],'edge':row['edge'],'evidence':row['evidence']}
    return hashlib.sha256(json.dumps(payload,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()


def exclusions(findings, manifest):
    """An exclusion is exact, justified, accountable and expiring; unknown IDs are errors."""
    from datetime import date
    lookup={row['id']:row for row in findings}
    seen=set()
    for row in findings:row['evidence_sha256']=evidence_digest(row)
    for rule in manifest:
        required={'finding_id','reason','author','evidence_url','expires','evidence_sha256'}
        if required-rule.keys() or any(not rule[k] for k in required):raise ValueError('incomplete exclusion')
        if rule['finding_id'] not in lookup:raise ValueError('exclusion does not match an actual finding')
        if date.fromisoformat(rule['expires']) < date.today():raise ValueError('expired exclusion')
        if rule['finding_id'] in seen:raise ValueError('duplicate exclusion')
        seen.add(rule['finding_id'])
        row=lookup[rule['finding_id']]
        if row['evidence_sha256']!=rule['evidence_sha256']:raise ValueError('exclusion evidence changed')
        row['status']='documented_exclusion';row['exclusion']=rule
    return findings


def render_html(report):
    rows=[]
    for net in report['networks']:
        for f in net['findings']:
            geo=f['geographic']; link=''
            if geo:link=f'<a href="https://www.openstreetmap.org/?mlat={geo["lat"]}&amp;mlon={geo["lon"]}">OSM</a>'
            rows.append('<tr>'+''.join('<td>'+html.escape(str(v))+'</td>' for v in [net['id'],f['kind'],f['edge'],f['status'],f['uncertainty_m'],f['evidence']])+'<td>'+link+'</td></tr>')
    return '<!doctype html><html lang="fr"><meta charset="utf-8"><title>TramSim — QA géométrique</title><style>body{font:15px system-ui;margin:24px}table{border-collapse:collapse}td,th{border:1px solid #aaa;padding:8px;max-width:420px;overflow-wrap:anywhere}</style><h1>Contrôles géométriques — constats à examiner</h1><p>Lecture seule. Un écart géométrique ne certifie pas une erreur du relevé réel. Incertitude inconnue : null. Aucun faux positif supprimé automatiquement.</p><pre>'+html.escape(json.dumps(report['summary'],indent=2))+'</pre><table><tr><th>Réseau</th><th>Contrôle</th><th>Arête</th><th>Statut</th><th>Incertitude m</th><th>Preuves</th><th>Lieu</th></tr>'+''.join(rows)+'</table></html>'


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('networks',nargs='+',type=Path);p.add_argument('--output',type=Path,default=Path('.cache/geometry/report.json'))
    p.add_argument('--route',type=Path);p.add_argument('--plan',type=Path);p.add_argument('--obstacles',type=Path);p.add_argument('--exclusions',type=Path);p.add_argument('--baseline',type=Path)
    p.add_argument('--report-only',action='store_true');p.add_argument('--verify-osm',action='store_true');p.add_argument('--spacing',type=float,default=2)
    a=p.parse_args()
    if not .1 <= a.spacing <= 20:p.error('spacing must be 0.1..20 m')
    plan=json.loads(a.plan.read_text()) if a.plan else None
    obstacle_manifest=json.loads(a.obstacles.read_text()) if a.obstacles else {}
    reports=[]
    for path in sorted(a.networks):
        net=json.loads(path.read_text());nodes=None
        osm=ROOT/'data/geography/osm'/ (path.stem+'.json.gz')
        if a.verify_osm and path.parent.name=='free':
            if not osm.exists():raise ValueError('missing original OSM archive: '+str(osm))
            nodes={n['id']:n for n in json.loads(gzip.decompress(osm.read_bytes()))['elements'] if n['type']=='node'}
        if obstacle_manifest and (obstacle_manifest.get('network_id')!=net.get('id') or obstacle_manifest.get('network_sha256')!=digest(path)):
            raise ValueError('obstacle manifest belongs to a different graph revision')
        if a.route:
            if len(a.networks)!=1:raise ValueError('route audit requires exactly one network')
            sections=json.loads(a.route.read_text())['sections']
            net=dict(net,edges=[route_edge(net,sections)])
        row=audit_network(net,plan,obstacle_manifest.get('obstacles'),a.spacing,osm_nodes=nodes)
        row['source']={'path':str(path),'sha256':digest(path),'provenance':net.get('provenance')};reports.append(row)
    all_findings=[f for n in reports for f in n['findings']]
    exclusions(all_findings,json.loads(a.exclusions.read_text()) if a.exclusions else [])
    active=[f for f in all_findings if f['status']=='open' and f['severity']=='error']
    baseline=json.loads(gzip.decompress(a.baseline.read_bytes()) if a.baseline and a.baseline.suffix=='.gz' else a.baseline.read_text()) if a.baseline else None
    config={'spacing_m':a.spacing,'horizontal_tolerance_m':.05,'vertical_tolerance_m':.05,'plan_sha256':digest(a.plan) if a.plan else None,'verify_osm':a.verify_osm,'route_sha256':digest(a.route) if a.route else None}
    if baseline:
        if baseline.get('schema_version')!=1 or baseline.get('kind')!='geometry':raise ValueError('invalid geometry baseline schema')
        if baseline['configuration']!=config:raise ValueError('baseline configuration differs')
        if {n['id'] for n in baseline['networks']} != {n['id'] for n in reports}:raise ValueError('baseline network set differs; coverage must not silently shrink')
    old={f['id']:f for n in baseline['networks'] for f in n['findings']} if baseline else {}
    regressions=[]
    for f in active:
        previous=old.get(f['id'])
        if previous is None or previous['status'] != 'open':regressions.append(f['id']);continue
        for key in ('distance_m','horizontal_m','vertical_m','grade','length_error_m'):
            if (f['evidence'].get(key) or 0)>(previous['evidence'].get(key) or 0)+1e-6:regressions.append(f['id']);break
    import subprocess
    try: revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True,stderr=subprocess.DEVNULL).strip()
    except (OSError,subprocess.SubprocessError):revision=None
    report={'revision':revision,'tool_sha256':digest(__file__),'scope':'read-only graph geometry and optional explicit obstacle envelopes','schema_version':1,'kind':'geometry','configuration':config,'networks':reports,
            'summary':{'networks':len(reports),'findings':len(all_findings),'open_errors':len(active),'documented_exclusions':sum(f['status']=='documented_exclusion' for f in all_findings),'regressions':len(set(regressions)) if baseline else None},
            'limitations':['Static volumes are conservative envelopes, not exact mesh intersection or certified vehicle clearance.','No obstacle data means no swept-volume coverage; native tests remain required.','No geographic source is modified.']}
    report['regression_ids']=sorted(set(regressions)) if baseline else []
    report['acceptance']='not_evaluated_report_only' if a.report_only else ('regression_gate' if baseline else 'strict_geometry_gate')
    a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,ensure_ascii=False,indent=2,allow_nan=False)+'\n')
    a.output.with_suffix('.html').write_text(render_html(report))
    print(json.dumps(report['summary']));return 0 if a.report_only else int(bool(regressions if baseline else active))


if __name__=='__main__':
    import sys
    try:raise SystemExit(main())
    except (ValueError,OSError,KeyError) as error:
        print(json.dumps({'ok':False,'error':str(error)}),file=sys.stderr);raise SystemExit(2)
