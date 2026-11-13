#!/usr/bin/env python3
"""Photo libre (Wikimedia Commons, géolocalisée) la plus proche du point « dense » de chaque ville, pour comparer
le niveau rue. Usage : refs_commons.py <dossier_audit> <cache>  ->  <cache>/<ville>.jpg + <cache>/attributions.json"""
import hashlib, json, os, sys, time, urllib.error, urllib.parse, urllib.request

API = "https://commons.wikimedia.org/w/api.php?"
UA = {"User-Agent": "tramsim-audit/0.11 (visual audit; offline research)"}


def fetch(url):
    for wait in (5, 15, 40, 0):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30).read()
        except urllib.error.HTTPError as e:
            if e.code != 429 or not wait:
                raise
            time.sleep(wait)


def get(params):
    return json.loads(fetch(API + urllib.parse.urlencode(params)))


def main(d, cache):
    os.makedirs(cache, exist_ok=True)
    attr_path = os.path.join(cache, "attributions.json")
    attrs = json.load(open(attr_path)) if os.path.exists(attr_path) else {}
    for f in sorted(os.listdir(d)):
        if not f.endswith(".log"):
            continue
        city = f[:-4]
        if city in attrs:
            continue
        pt = None
        for l in open(os.path.join(d, f), encoding="utf-8", errors="replace"):
            if l.startswith("AUDIT|point|") and l.split("|")[3] == "dense":
                x = l.split("|"); pt = (float(x[6]), float(x[7]))
        if not pt:
            continue
        try:
            res = get({"action": "query", "list": "geosearch", "gscoord": f"{pt[0]}|{pt[1]}", "gsradius": 400,
                   "gsnamespace": 6, "gslimit": 20, "format": "json"})
        except Exception as e:
            print(city, "ECHEC", e); time.sleep(30); continue
        hits = [h for h in res.get("query", {}).get("geosearch", []) if h["title"].lower().endswith((".jpg", ".jpeg"))]
        if not hits:
            attrs[city] = None; continue
        h = hits[0]
        name = h["title"].split(":", 1)[1]
        fn = name.replace(" ", "_"); md = hashlib.md5(fn.encode()).hexdigest()
        q = urllib.parse.quote(fn)
        data = fetch(f"https://upload.wikimedia.org/wikipedia/commons/thumb/{md[0]}/{md[:2]}/{q}/500px-{q}")
        open(os.path.join(cache, f"{city}.jpg"), "wb").write(data)
        # auteur et licence : voir la page de description (API d'imageinfo limitée en débit depuis ce poste)
        attrs[city] = {"title": h["title"], "dist_m": h["dist"],
                       "url": "https://commons.wikimedia.org/wiki/" + urllib.parse.quote(h["title"].replace(" ", "_"))}
        print(city, h["title"], round(h["dist"]))
        json.dump(attrs, open(attr_path, "w"), ensure_ascii=False, indent=1)
        time.sleep(10)
    json.dump(attrs, open(attr_path, "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
