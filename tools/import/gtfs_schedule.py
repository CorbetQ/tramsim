#!/usr/bin/env python3
"""Extrait d'un GTFS les horaires d'un trip (secondes depuis minuit) : stops.txt + stop_times.txt + trips.txt.
Usage : gtfs_schedule.py gtfs_dir route_id [--direction 0] -> JSON {stops:[{name,arrival_s,departure_s}]}"""
import csv, json, os, sys, argparse


def hms(t):
    h, m, s = (int(x) for x in t.split(":"))
    return h * 3600 + m * 60 + s


def schedule(gtfs_dir, route_id, direction="0"):
    rd = lambda n: list(csv.DictReader(open(os.path.join(gtfs_dir, n), encoding="utf-8-sig")))
    stops = {s["stop_id"]: s["stop_name"] for s in rd("stops.txt")}
    trips = [t for t in rd("trips.txt") if t["route_id"] == route_id and t.get("direction_id", "0") == direction]
    if not trips:
        raise SystemExit(f"aucun trip pour la route {route_id}")
    tid = trips[0]["trip_id"]
    st = sorted((r for r in rd("stop_times.txt") if r["trip_id"] == tid), key=lambda r: int(r["stop_sequence"]))
    return {"trip_id": tid, "stops": [{"name": stops[r["stop_id"]], "arrival_s": hms(r["arrival_time"]),
                                       "departure_s": hms(r["departure_time"])} for r in st]}


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("dir"); ap.add_argument("route"); ap.add_argument("--direction", default="0")
    a = ap.parse_args()
    print(json.dumps(schedule(a.dir, a.route, a.direction), ensure_ascii=False, indent=1))
