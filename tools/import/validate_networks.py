#!/usr/bin/env python3
"""Contrôles de l'import : références, distances, connexions, alimentation, stations. Code retour 1 si erreur.
Usage : validate_networks.py data/networks/*.json"""
import json, sys

SUPPLIES = {"overhead", "aps", "third_rail", "hybrid", "battery"}


def validate(net):
    errs, warns = [], []
    nodes = set(net.get("nodes", []))
    edges = {}
    if net.get("schema") != 1:
        errs.append("schema != 1")
    if net.get("supply") not in SUPPLIES:
        errs.append(f"alimentation inconnue: {net.get('supply')}")
    if net.get("guidance", "steel") not in ("steel", "rubber_guided"):
        errs.append("guidage inconnu")
    for e in net.get("edges", []):
        if e["id"] in edges:
            errs.append(f"arête dupliquée {e['id']}")
        edges[e["id"]] = e
        if e["from"] not in nodes or e["to"] not in nodes:
            errs.append(f"nœud manquant sur {e['id']}")
        if e["length"] <= 0:
            errs.append(f"longueur <= 0 sur {e['id']}")
        if not 5 <= e.get("limit_kmh", 50) <= 120:
            warns.append(f"limite suspecte sur {e['id']}")
        if abs(e.get("grade", 0)) > 0.12:
            warns.append(f"pente suspecte sur {e['id']}")
    ins = {e["to"] for e in edges.values()}; outs = {e["from"] for e in edges.values()}
    for n in nodes - ins - outs:
        errs.append(f"nœud isolé {n}")
    for s in net.get("stations", []):
        e = edges.get(s["edge"])
        if e is None:
            errs.append(f"station {s['name']}: arête inconnue")
        elif not 0 <= s["offset"] <= e["length"]:
            errs.append(f"station {s['name']}: offset hors arête")
    for s in net.get("signals", []):
        if s["edge"] not in edges:
            errs.append("signal sur arête inconnue")
    for r in net.get("roads", []):
        if r["edge"] not in edges:
            errs.append(f"route {r['id']}: arête inconnue")
        elif r["edge_offset"] > edges[r["edge"]]["length"]:
            errs.append(f"route {r['id']}: croisement hors arête")
    if not net.get("provenance"):
        errs.append("provenance manquante")
    if net.get("provisional"):
        warns.append("DONNÉES PROVISOIRES (non issues des sources)")
    # connexité faible
    adj = {n: set() for n in nodes}
    for e in edges.values():
        if e["from"] in adj and e["to"] in adj:
            adj[e["from"]].add(e["to"]); adj[e["to"]].add(e["from"])
    if nodes:
        seen, st = set(), [next(iter(nodes))]
        while st:
            n = st.pop()
            if n not in seen:
                seen.add(n); st.extend(adj[n] - seen)
        if seen != nodes:
            msg = f"réseau non connexe ({len(nodes) - len(seen)} nœuds séparés)"
            (warns if net.get("kind") == "free" else errs).append(msg)
    return errs, warns


if __name__ == "__main__":
    bad = 0
    for p in sys.argv[1:]:
        errs, warns = validate(json.load(open(p)))
        print(f"{p}: {len(errs)} erreur(s), {len(warns)} avertissement(s)")
        for m in errs: print("  ERREUR", m)
        for m in warns: print("  avert.", m)
        bad += bool(errs)
    sys.exit(1 if bad else 0)
