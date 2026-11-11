#!/usr/bin/env python3
"""Écrit docs/COUVERTURE.md : réseaux livrés, sources, valeurs estimées et résultat du test national.
Usage : coverage_report.py data/index.json data/sources/gtfs_catalogue.json resultats_test_all_networks.log"""
import json, sys
from collections import defaultdict

idx = json.load(open(sys.argv[1]))["networks"]
cat = json.load(open(sys.argv[2]))["networks"]
res = {}
for line in open(sys.argv[3], encoding="utf-8"):
    if line.startswith("RESULT|"):
        f = line.rstrip("\n").split("|")
        if len(f) >= 10:
            res[f[1]] = {"stops": int(f[2]), "ok": int(f[3]), "early": int(f[4]), "late": int(f[5]), "missed": int(f[6]),
                         "t": int(f[7]), "gtfs": int(f[8]), "fault": f[9] if len(f) > 9 else ""}
def verdict(r):
    if r is None: return "non testé"
    if r["fault"] or r["early"] or r["missed"] or r["ok"] + r["late"] != r["stops"]: return "ÉCHEC"
    if r["late"]: return f"retard sur {r['late']} arrêt(s)"
    return "réussie"
by_city = defaultdict(list)
for e in idx:
    by_city[e["city"]].append(e)
ok = sum(1 for e in idx if verdict(res.get(e["id"])) == "réussie")
out = ["# État de couverture", "",
       f"Généré automatiquement. **{len(idx)} lignes / variantes** dans {len(by_city)} réseaux ; "
       f"mission réelle réussie au pilote automatique (horaires GTFS, 60 s de tolérance) : **{ok}/{len(idx)}**.", "",
       "Valeurs estimées communes à tous les réseaux (détail dans `docs/SOURCES.md`) : pentes nulles, limites de vitesse "
       "déduites de la géométrie et des horaires, alimentation supposée par caténaire (APS non localisé), rebroussement simplifié, "
       "voies de service et aiguillages intermédiaires absents (OpenStreetMap inaccessible lors de l'import), matériel générique par famille.", "",
       "| Ville | Ligne | Parcours | Type | Arrêts | km | Mission test |", "|---|---|---|---|---|---|---|"]
for city in sorted(by_city):
    for e in by_city[city]:
        out.append(f"| {city} | {e['line']} | {e['long_name']} | {e['kind']}{' (pneus)' if e['guidance'] == 'rubber_guided' else ''} | "
                   f"{e['stations'] // 2} | {e['length_km']} | {verdict(res.get(e['id']))} |")
out += ["", "## Sources", "", "| Réseau | Exploitant / AOM | Licence | État |", "|---|---|---|---|"]
imported = {e["id"].split("_")[0] for e in idx}
for c in cat:
    st = "importé" if c["id"] in imported else ("non importé : " + c["skip"] if c.get("skip") else "non importé")
    out.append(f"| {c['city']} | {c['publisher']} | {c['licence']} | {st} |")
out += ["", "## Absents ou incomplets connus", "",
        "- Annemasse : tram exploité par les TPG (Genève), absent du GTFS local.",
        "- Lignes sans GTFS tram identifié dans le catalogue national au 11/11/2026 : à compléter.",
        "- Aucun test sur téléphone réel n'a été effectué (performances non mesurées)."]
open("docs/COUVERTURE.md", "w", encoding="utf-8").write("\n".join(out) + "\n")
print("docs/COUVERTURE.md :", len(idx), "lignes,", ok, "réussies")
