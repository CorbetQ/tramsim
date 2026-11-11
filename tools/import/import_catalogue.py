#!/usr/bin/env python3
"""Importe toutes les lignes de tram (et tram-train) des GTFS téléchargés par fetch_gtfs.py.
Une variante = un couple de terminus ; chaque variante devient un fichier data/networks/<réseau>_<ligne>[_<n>].json.
Usage : import_catalogue.py data/sources/gtfs_catalogue.json GTFS_ROOT OUT_DIR [id ...]"""
import json, os, re, sys, types, unicodedata
sys.path.insert(0, os.path.dirname(__file__))
import gtfs_to_network as g


def slug(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "", s) or "x"


def feed_date(d):
    p = os.path.join(d, "feed_info.txt")
    if os.path.exists(p):
        rows = g.rd(d, "feed_info.txt")
        if rows and rows[0].get("feed_start_date"):
            v = rows[0]["feed_start_date"]
            return f"{v[:4]}-{v[4:6]}-{v[6:8]}"
    return "inconnue"


def run(entry, root, out_dir, max_variants=3):
    if entry.get("skip"):
        return [f"{entry['id']}: non importé — {entry['skip']}"]
    d = os.path.join(root, entry["id"])
    if not os.path.exists(os.path.join(d, "routes.txt")):
        return [f"{entry['id']}: GTFS absent"]
    types_ok = {str(t) for t in entry.get("route_types", [0])} | {"900"}
    routes = [r for r in g.rd(d, "routes.txt") if r.get("route_type", "").strip() in types_ok]
    overrides = entry.get("routes", {})
    if not routes:
        return [f"{entry['id']}: aucune ligne de tram dans ce GTFS"]
    feed = g.Feed(d, {r["route_id"] for r in routes})
    log = []
    for r in routes:
        short = r["route_short_name"] or r["route_id"]
        ov = overrides.get(short, {})
        if ov.get("skip"):
            log.append(f"{entry['id']} {short}: ignorée ({ov['skip']})")
            continue
        kept, sets = [], []
        for v in g.variants(feed, r["route_id"]):
            names = {feed.name[s] for pat, _, _ in v[2].values() for s in pat}
            if any(names <= o for o in sets):
                continue  # service partiel (terminus intermédiaire) : couvert par une variante plus longue
            kept.append(v); sets.append(names)
        vs = kept[:max_variants]
        for k, (n, key, sel) in enumerate(vs):
            net_id = f"{entry['id']}_{slug(short)}" + (f"_{k + 1}" if k else "")
            args = types.SimpleNamespace(id=net_id, city=entry["city"], source_date=feed_date(d), publisher=entry["publisher"],
                                         licence=entry["licence"], supply=ov.get("supply", entry.get("supply_default", "overhead")),
                                         supply_note=ov.get("supply_note", "APS éventuel non localisé : caténaire supposée" if entry.get("supply") == "mixed_aps" else "non vérifié"),
                                         missions=6, vmax=ov.get("vmax", 100 if (ov.get("kind") == "tram-train" or r.get("route_type", "").strip() == "2") else 70))
            try:
                net = g.build(d, r["route_id"], args, feed=feed, selection=sel, prefix=f"{slug(short)}v{k}_", net_id=net_id)
            except Exception as e:  # noqa: BLE001 — un GTFS atypique ne doit pas bloquer les autres
                log.append(f"{net_id}: ÉCHEC {type(e).__name__}: {e}")
                continue
            net["guidance"] = ov.get("guidance", "steel")
            if ov.get("guidance") == "rubber_guided":
                net["estimated"].append("guidage sur pneus d'après le catalogue (à vérifier)")
            if r.get("route_type", "").strip() == "2" or ov.get("kind") == "tram-train":
                net["kind"] = "tram-train"
                net["signalling"] = "rail"   # profil de signalisation ferroviaire sur les sections partagées
            if len(vs) > 1:
                net["long_name"] = " – ".join(sorted(key))
            if ov.get("express"):
                net["kind"] = "express"
            net["source_id"] = entry["id"]
            with open(os.path.join(out_dir, net_id + ".json"), "w", encoding="utf-8") as f:
                json.dump(net, f, ensure_ascii=False, separators=(",", ":"))
            rep = net["import_report"]
            log.append(f"{net_id}: {net['long_name'][:50]} | " + " ; ".join(f"sens {s}: {v['stops']} arrêts {v['length_m']} m écart max {v['max_stop_gap_m']} m" for s, v in rep.items()))
    return log


if __name__ == "__main__":
    cat = json.load(open(sys.argv[1]))
    only = set(sys.argv[4:])
    for e in cat["networks"]:
        if not only or e["id"] in only:
            for line in run(e, sys.argv[2], sys.argv[3]):
                print(line, flush=True)
