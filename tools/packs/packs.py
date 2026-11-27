"""Données téléchargeables (docs/SERVEUR_DONNEES.md) : filtres d'export, rames par ville, estimation et manifeste.
  python3 tools/packs/packs.py filters   # réécrit exclude_filter des presets Android / Windows / Windows ARM64
  python3 tools/packs/packs.py stock     # réécrit data/packs/stock.json (rames propres à une ville) puis les filtres
  python3 tools/packs/packs.py apk [preset] [--zip]   # estimation du paquet exporté (hors moteur)
  python3 tools/packs/packs.py manifest <dossier> --data-version V [--app-version A] [--release-tag T] [--engine 4.6]
        # écrit <dossier>/manifest.json (taille, sha256, URL, dépendances) à partir des tramsim-*-<plateforme>.pck
Répartition (data/packs/plan.json) : chaque ville a son pack (scène, terrain, décor, monuments, lightmaps, rames et
livrées utilisées par elle seule) ; les fichiers de rames partagés par plusieurs villes (ou par aucune) vont dans
« commun-rames », les textures et modèles partagés dans « commun-decor ». Aucune ville ne reste dans les exports.
Les packs sont construits par tools/packs/build_packs.gd (Godot, après import) pour les plateformes mobile et pc."""
import collections, datetime, hashlib, json, os, re, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
PLAN = json.loads((ROOT / "data/packs/plan.json").read_text())
STOCK = ROOT / "data/packs/stock.json"
PRESETS = {"Android": "override.cfg, tests/*, tools/*, docs/*, data/geography/*, build/*, .github/*, data/audio/reference/*, server/*",
           "Windows": "override.cfg, tests/*, tools/*, docs/*, android/*, data/geography/*, build/*, .github/*, data/audio/reference/*, server/*",
           "Windows ARM64": "override.cfg, tests/*, tools/*, docs/*, android/*, data/geography/*, build/*, .github/*, data/audio/reference/*, server/*"}
MOBILE_EXCLUDE = PLAN["mobile_exclude"]
# réseaux de rames sans scène jouable : rattachés au pack de la ville la plus proche
ALIAS = {"saintlouis": "mulhouse", "leymen": "mulhouse", "sarreguemines": "strasbourg", "annemasse": "lyon"}
RX = re.compile(rb'res://((?:tram_parts|tram_livery)/[^"\'\s\x00:]+)')
FORMAT = PLAN["format"]


def cities():
    return sorted(p.stem for p in (ROOT / "data/scenes").glob("*.json") if "_" not in p.stem)


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
    """data/packs/stock.json : fichiers de rames (toutes LOD, filtrés par plateforme à la construction) utilisés par une
    seule ville ; les autres (partagés ou sans usage connu) vont dans le pack commun-rames."""
    use = stock_use(); allc = set(cities())
    by_city = collections.defaultdict(list)
    for p in stock_files():
        u = use.get(p, set())
        if len(u) == 1 and next(iter(u)) in allc: by_city[next(iter(u))].append("res://" + p)
    STOCK.write_text(json.dumps({"doc": "Rames HD propres à une ville (tools/packs/packs.py stock) : fichiers mis dans le "
                                 "pack de cette ville ; les autres fichiers de tram_parts/ et tram_livery/ vont dans "
                                 "commun-rames.", "cities": {c: sorted(v) for c, v in sorted(by_city.items())}},
                                ensure_ascii=False, separators=(",", ":")) + "\n")
    print("rames : %d fichiers propres à %d villes, %d partagés" % (sum(map(len, by_city.values())), len(by_city),
                                                                   len(stock_files()) - sum(map(len, by_city.values()))))
    filters()


def filters():
    p = ROOT / "export_presets.cfg"; s = p.read_text()
    pats = ", ".join(PLAN["export_exclude"])
    out = []; pos = 0
    for m in re.finditer(r'^name="([^"]+)"$', s, re.M):
        name = m.group(1)
        if name not in PRESETS: continue
        e = re.compile(r'^exclude_filter=".*"$', re.M).search(s, m.end())
        out.append(s[pos:e.start()] + f'exclude_filter="{PRESETS[name]}, {pats}"'); pos = e.end()
    p.write_text("".join(out) + s[pos:])
    print("exports : %d presets, %d motifs de données exclus" % (len(out), len(PLAN["export_exclude"])))


# Godot n'applique pas deflate aux .ctex et .scn dans l'APK (_should_compress_asset) : comptés bruts
STORED = (".ctex", ".scn", ".png", ".jpg", ".ogg", ".mp3", ".wav", ".webp")


def _imported_files(rel, mobile=True):
    f = ROOT / rel; imp = ROOT / (rel + ".import")
    if not imp.exists(): return [f]
    return [ROOT / q for k, q in re.findall(r'^(path[.\w]*)="res://(.+?)"', imp.read_text(), re.M)
            if k == "path" or (("etc2" in k or "astc" in k) if mobile else ("s3tc" in k or "bptc" in k))]


def apk(preset="Android", zipped="--zip" in sys.argv):
    """Estimation du PCK exporté par un preset (hors moteur) : ressources importées et fichiers non-ressources du filtre
    d'inclusion, moins le filtre d'exclusion. --zip : taille dans l'APK (deflate sauf .ctex/.scn/médias stockés)."""
    import zlib
    from fnmatch import fnmatch
    s = (ROOT / "export_presets.cfg").read_text()
    blk = s.partition('name="%s"' % preset)[2]
    inc = [x.strip() for x in re.search(r'^include_filter="(.*)"$', blk, re.M).group(1).split(",") if x.strip()]
    exc = [x.strip() for x in re.search(r'^exclude_filter="(.*)"$', blk, re.M).group(1).split(",") if x.strip()]
    res_ext = {".gd", ".tscn", ".tres", ".scn", ".res", ".gdshader", ".json", ".cfg", ".ttf", ".otf"}
    tot = collections.Counter(); z = 0
    for dp, dn, fn in os.walk(ROOT):
        r = os.path.relpath(dp, ROOT)
        if r.startswith(".") and r != ".": dn[:] = []; continue
        dn[:] = [d for d in dn if not d.startswith(".") and d not in ("build", "android")]
        for f in fn:
            if f.endswith((".import", ".uid")): continue
            rel = os.path.normpath(os.path.join(r, f))
            if any(fnmatch(rel, x) for x in exc): continue
            imported = (ROOT / (rel + ".import")).exists()
            if not imported and Path(f).suffix not in res_ext and not any(fnmatch(rel, x) for x in inc): continue
            files = [x for x in _imported_files(rel, preset == "Android") if x.exists()]
            tot["/".join(rel.split("/")[:2])] += sum(x.stat().st_size for x in files)
            if zipped:
                z += sum(x.stat().st_size if x.suffix in STORED else len(zlib.compress(x.read_bytes(), 6)) for x in files)
    for k, v in tot.most_common(10): print(f"  {k:30s} {v / 1048576:7.1f} Mo")
    print(f"{preset} : {sum(tot.values()) / 1048576:.1f} Mo (données exportées, non compressées)")
    if zipped: print(f"{preset} : {z / 1048576:.1f} Mo dans l'archive (hors moteur)")


def _sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""): h.update(b)
    return h.hexdigest()


def manifest(folder, *args):
    """Manifeste des packs construits : versions, plateformes, packs (fichier, taille, sha256, URL, dépendances)."""
    opt = {"--data-version": "", "--app-version": "", "--release-tag": "", "--engine": "4.6"}
    a = list(args)
    for k in opt:
        if k in a: opt[k] = a[a.index(k) + 1]
    if not opt["--data-version"]:
        opt["--data-version"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d.%H%M%S")
    ver = opt["--data-version"]
    if not re.fullmatch(r"[0-9A-Za-z._-]+", ver): sys.exit("data-version invalide : " + ver)
    folder = Path(folder); commons = list(PLAN["commons"])
    labels = {}
    for e in json.loads((ROOT / "data/index.json").read_text())["networks"]:
        labels.setdefault(str(e.get("id", "")).split("_")[0], e["city"])
    plats = {}
    for pck in sorted(folder.glob("tramsim-*-*.pck")):
        m = re.fullmatch(r"tramsim-(city-(?P<c>[a-z0-9]+)|(?P<k>commun-[a-z0-9]+))-(?P<p>mobile|pc)\.pck", pck.name)
        if not m: continue
        pid = m.group("c") or m.group("k"); kind = "city" if m.group("c") else "common"
        plats.setdefault(m.group("p"), {})[pid] = {
            "kind": kind, "label": labels.get(pid, PLAN["commons"].get(pid, {}).get("label", pid)),
            "file": pck.name, "size": pck.stat().st_size, "sha256": _sha256(pck),
            "url": f"/packs/{ver}/{pck.name}", "requires": commons if kind == "city" else []}
    if not plats: sys.exit("aucun pack dans " + str(folder))
    doc = {"schema": 1, "format": FORMAT, "engine": opt["--engine"], "data_version": ver,
           "app_version": opt["--app-version"], "release_tag": opt["--release-tag"],
           "generated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
           "platforms": plats,
           "totals": {p: sum(x["size"] for x in v.values()) for p, v in plats.items()}}
    (folder / "manifest.json").write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n")
    for p, v in plats.items():
        print("manifeste %s : %d packs, %.1f Mo" % (p, len(v), doc["totals"][p] / 1048576))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "apk":
        rest = [x for x in sys.argv[2:] if not x.startswith("-")]
        apk(*rest[:1])
    elif cmd == "manifest": manifest(*sys.argv[2:])
    elif cmd in ("filters", "stock"): {"filters": filters, "stock": stock}[cmd]()
    else: print(__doc__); sys.exit(2)
