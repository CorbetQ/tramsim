"""Packs de ville (P4) : filtre d'exclusion du preset Android et inventaire des tailles.
  python3 tools/packs/packs.py filters   # réécrit exclude_filter du preset « Android » (export_presets.cfg)
  python3 tools/packs/packs.py sizes     # tailles brutes par ville (données + modèles importés) et du paquet de base
  python3 tools/packs/packs.py stock     # réécrit data/packs/stock.json (rames HD des villes en packs) puis les filtres
Rames HD (tram_parts/, tram_livery/) : un fichier utilisé par une rame d'Angers ou de Nantes reste dans l'APK ; un
fichier utilisé seulement par des villes en packs va dans le pack de chacune d'elles (doublons acceptés) ; un fichier
qu'aucune rame n'utilise reste dans l'APK (prudence).
Les fichiers exclus sont ceux que tools/packs/build_packs.gd met dans les packs (mêmes motifs)."""
import collections, json, os, re, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
BASE_EXCLUDE = "override.cfg, tests/*, tools/*, docs/*, data/geography/*, build/*, .github/*, data/audio/reference/*"


def cities():
    return sorted(p.stem for p in (ROOT / "data/scenes").glob("*.json") if "_" not in p.stem)


def packed():
    base = json.loads((ROOT / "data/packs/base.json").read_text())["cities"]
    return [c for c in cities() if c not in base]


def patterns(c):
    return [f"data/scenes/{c}.*", f"data/scenes/{c}_*", f"data/free/{c}.*", f"data/free/{c}_*", f"assets/models/{c}/*"]


STOCK = ROOT / "data/packs/stock.json"
# contenu PC seulement, jamais chargé sur Android (StockHD.mobile() et profil Mobile) : LOD0 et cabine PC des rames
# (repli Mobile : lod1, lod1_m, cab_m), livrées 4k (repli 2k), tableaux PBR 2048² (repli 1024²)
MOBILE_EXCLUDE = ["tram_parts/*_lod0.glb", "tram_parts/*/cab.glb", "tram_livery/livery/*_4k.png",
                  "tram_livery/shared/*_cab_desk.png", "assets/models/rolling_stock/*/lod0.glb",
                  "assets/models/rolling_stock/*/cab.glb", "assets/models/rolling_stock/*/textures/livery_4k.png",
                  "assets/models/rolling_stock/*/textures/cab_desk.png", "assets/textures/pbr/*_2k.jpg"]
# réseaux de rames sans scène jouable : rattachés au pack de la ville la plus proche
ALIAS = {"saintlouis": "mulhouse", "leymen": "mulhouse", "sarreguemines": "strasbourg", "annemasse": "lyon"}
RX = re.compile(rb'res://((?:tram_parts|tram_livery)/[^"\'\s\x00:]+)')


def _crawl(seed):
    """Fichiers tram_parts/tram_livery atteints depuis un texte : chemins res:// des json/scn/tres, images externes des glb."""
    seen = set(); todo = [x.decode() for x in RX.findall(seed)]
    while todo:
        p = todo.pop()
        if p in seen or not (ROOT / p).is_file(): continue
        seen.add(p); f = ROOT / p
        if f.suffix in (".json", ".tscn", ".tres", ".scn", ".res", ".gdshader"):
            todo += [x.decode() for x in RX.findall(f.read_bytes())]
        elif f.suffix == ".glb":
            b = f.read_bytes(); n = int.from_bytes(b[12:16], "little")
            try: g = json.loads(b[20:20 + n])
            except ValueError: g = {}
            for im in g.get("images", []):
                u = im.get("uri", "")
                if u and not u.startswith("data:"): todo.append(os.path.normpath(os.path.join(os.path.dirname(p), u)))
    return seen


def stock_use():
    """Fichier (chemin relatif) -> villes dont une rame l'utilise (variantes et livrées de parts_manifest.json)."""
    pm = json.loads((ROOT / "data/rolling_stock/parts_manifest.json").read_text())
    idx = json.loads((ROOT / "data/rolling_stock/variants/index.json").read_text())
    net = {e["id"]: e["network"] for e in idx["entries"]}
    use = collections.defaultdict(set)
    for vid, v in pm["variants"].items():
        city = net.get(vid, vid.split("__")[0]); city = ALIAS.get(city, city)
        seed = json.dumps([v, pm["kits"].get(v.get("kit")), pm["liveries"].get(v.get("livery"))]).encode()
        for p in _crawl(seed): use[p].add(city)
    nets = set(net.values())
    for lk, lv in pm["liveries"].items():   # livrées par réseau : <kit>_<réseau>_<empreinte>
        cs = [t for t in lk.split("_") if t in nets]
        if cs:
            for p in _crawl(json.dumps(lv).encode()): use[p].add(ALIAS.get(cs[-1], cs[-1]))
    return use


def stock_files():
    return sorted(str(p.relative_to(ROOT)) for d in ("tram_parts", "tram_livery") for p in (ROOT / d).rglob("*")
                  if p.is_file() and p.suffix not in (".import", ".md"))


def stock():
    """data/packs/stock.json : fichiers de rames par ville en pack et motifs d'exclusion du preset Android."""
    use = stock_use(); base = set(json.loads((ROOT / "data/packs/base.json").read_text())["cities"])
    allf = stock_files(); pk = set(packed())
    only = [p for p in allf if use.get(p) and not (use[p] & base)]
    from fnmatch import fnmatch
    mob = [p for p in only if not any(fnmatch(p, x) for x in MOBILE_EXCLUDE)]   # packs pour Android seulement
    cities = {c: sorted("res://" + p for p in mob if c in use[p]) for c in sorted(pk)}
    so = set(only); keep = [p for p in allf if p not in so]
    by_dir = collections.defaultdict(list)
    for p in only: by_dir[os.path.dirname(p)].append(p)
    excl = []
    for d, fs in sorted(by_dir.items()):
        excl += [d + "/*"] if not any(k.startswith(d + "/") for k in keep) else fs
    STOCK.write_text(json.dumps({"doc": "Rames HD hors APK (tools/packs/packs.py stock) : fichiers par pack de ville et "
                                 "motifs d'exclusion du preset Android.", "cities": cities, "exclude": excl},
                                ensure_ascii=False, separators=(",", ":")) + "\n")
    print("rames : %d fichiers hors APK, %d motifs, %d fichiers dans l'APK" % (len(only), len(excl), len(keep)))
    filters()


def filters():
    p = ROOT / "export_presets.cfg"; s = p.read_text()
    pats = ", ".join(x for c in packed() for x in patterns(c))
    pats += "".join(", " + x for x in MOBILE_EXCLUDE)
    if STOCK.exists(): pats += "".join(", " + x for x in json.loads(STOCK.read_text())["exclude"])
    head, sep, rest = s.partition('name="Android"')
    rest = re.sub(r'^exclude_filter=".*"$', f'exclude_filter="{BASE_EXCLUDE}, {pats}"', rest, count=1, flags=re.M)
    p.write_text(head + sep + rest)
    print("Android : %d villes en packs, %d motifs exclus" % (len(packed()), len(pats.split(", "))))


def size(c):
    n = 0
    for d in ("data/scenes", "data/free"):
        for f in (ROOT / d).glob(f"{c}*"):
            if f.stem == c or f.name.startswith(c + "_") or f.name.startswith(c + "."): n += f.stat().st_size
    for f in (ROOT / "assets/models" / c).glob("*.import") if (ROOT / "assets/models" / c).exists() else []:
        m = re.search(r'^path="res://(.+?)"', f.read_text(), re.M)
        if m and (ROOT / m.group(1)).exists(): n += (ROOT / m.group(1)).stat().st_size
    return n


def _exported(rel, mobile=True):
    """Taille exportée d'un fichier : version importée (etc2/astc sur Android, s3tc/bptc sur PC) ou source."""
    f = ROOT / rel; imp = ROOT / (rel + ".import")
    if not imp.exists(): return f.stat().st_size
    n = 0
    for k, q in re.findall(r'^(path[.\w]*)="res://(.+?)"', imp.read_text(), re.M):
        if k == "path" or (("etc2" in k or "astc" in k) if mobile else ("s3tc" in k or "bptc" in k)):
            if (ROOT / q).exists(): n += (ROOT / q).stat().st_size
    return n


def _deflated(rel, mobile=True):
    import zlib
    f = ROOT / rel; imp = ROOT / (rel + ".import"); files = [f]
    if imp.exists():
        files = [ROOT / q for k, q in re.findall(r'^(path[.\w]*)="res://(.+?)"', imp.read_text(), re.M)
                 if k == "path" or (("etc2" in k or "astc" in k) if mobile else ("s3tc" in k or "bptc" in k))]
    return sum(len(zlib.compress(x.read_bytes(), 6)) for x in files if x.exists())


def apk(preset="Android", zipped="--zip" in sys.argv):
    """Estimation (non compressée) du PCK exporté par un preset : ressources importées et fichiers non-ressources du
    filtre d'inclusion, moins le filtre d'exclusion. Repère pour le plafond de l'APK de base (150 Mo)."""
    from fnmatch import fnmatch
    s = (ROOT / "export_presets.cfg").read_text()
    blk = s.partition('name="%s"' % preset)[2]
    inc = [x.strip() for x in re.search(r'^include_filter="(.*)"$', blk, re.M).group(1).split(",") if x.strip()]
    exc = [x.strip() for x in re.search(r'^exclude_filter="(.*)"$', blk, re.M).group(1).split(",") if x.strip()]
    exc_set = set(x for x in exc if "*" not in x); exc_pat = [x for x in exc if "*" in x]
    res_ext = {".gd", ".tscn", ".tres", ".scn", ".res", ".gdshader", ".json", ".cfg", ".ttf", ".otf"}
    tot = collections.Counter(); z = 0
    for dp, dn, fn in os.walk(ROOT):
        r = os.path.relpath(dp, ROOT)
        if r.startswith(".") and r != ".": dn[:] = []; continue
        dn[:] = [d for d in dn if not d.startswith(".") and d not in ("build", "android")]
        for f in fn:
            if f.endswith((".import", ".uid")): continue
            rel = os.path.normpath(os.path.join(r, f))
            if rel in exc_set or any(fnmatch(rel, x) for x in exc_pat): continue
            imported = (ROOT / (rel + ".import")).exists()
            if not imported and Path(f).suffix not in res_ext and not any(fnmatch(rel, x) for x in inc): continue
            n = _exported(rel, preset == "Android"); tot[rel.split("/")[0]] += n
            if zipped: z += _deflated(rel, preset == "Android")
    for k, v in tot.most_common(8): print(f"  {k:24s} {v / 1048576:7.1f} Mo")
    print(f"{preset} : {sum(tot.values()) / 1048576:.1f} Mo (estimation non compressée)")
    if zipped: print(f"{preset} : {z / 1048576:.1f} Mo compressés (deflate, hors moteur)")


def sizes():
    tot = 0
    for c in cities():
        s = size(c); tot += s if c in packed() else 0
        print(f"{c:14s} {s / 1048576:7.1f} Mo {'pack' if c in packed() else 'base'}")
    print(f"packs : {tot / 1048576:.1f} Mo")


if __name__ == "__main__":
    {"filters": filters, "sizes": sizes, "stock": stock, "apk": apk}[sys.argv[1]](*sys.argv[2:3] if sys.argv[1] == "apk" and len(sys.argv) > 2 and not sys.argv[2].startswith("-") else ())
