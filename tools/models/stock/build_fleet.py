#!/usr/bin/env python3
"""P4 : génère les kits HD de tout le parc (un kit par design de caisse, maître = variante maîtresse du kit).
python3 tools/models/stock/build_fleet.py [kit ...] [--jobs=3]
1. sources intermédiaires par maître (build_stock.build_variant) dans $TRAMSIM_STOCK_SRC (hors dépôt) ;
2. entrées du manifeste assets/models/rolling_stock/manifest.json (écrites une seule fois, par ce processus) ;
3. découpe en caisses canoniques tram_parts/ + atlas de livrée tram_livery/ (build_kits --hd-only, un processus par kit),
   puis fusion dans data/rolling_stock/parts_manifest.json."""
import json, os, subprocess, sys, tempfile
from multiprocessing import Pool
from pathlib import Path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import specs
from build_kits import kit_id, INDEX, ROOT
from build_stock import OUT, configure_texture_imports

# ordre de génération (§5.3) : Dualis, Flexity, TFS, puis les plus gros réseaux, puis le reste
PRIORITY = ["dualis", "marseille", "tfs1", "tfs2", "bordeaux", "lyon_egg", "lyon2020", "toulouse", "tam302", "urbos_tam",
            "tam401", "grenoble", "cts403", "cts403ng", "cts3", "eurotram", "idfm305", "idfm405", "paris_t2", "paris_t3",
            "paris_t7", "avanto_paris", "translohr_paris", "lille305", "breda", "nice302", "nice405", "rouen", "incentro",
            "urbos_nantes"]


def kits_and_masters():
    entries = json.loads((ROOT / 'data/rolling_stock/variants/index.json').read_text())['entries']
    groups = {}
    for e in entries: groups.setdefault(kit_id(e), []).append(e)
    pm = json.loads(INDEX.read_text()); out = {}
    for kid, rows in groups.items():
        kit = json.loads((ROOT / pm['kits'][kid].replace('res://', '')).read_text())
        out[kid] = kit['master']
    return out


def stock(vid):
    import build_stock
    sp, t, info = build_stock.build_variant(vid)
    return vid, build_stock.manifest_entry(sp, t, info)


def kit(kid):
    fd, tmp = tempfile.mkstemp(suffix='.json'); os.close(fd)
    r = subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), 'build_kits.py'), '--hd-only',
                        '--kits=' + kid, '--index-out=' + tmp], capture_output=True, text=True)
    if r.returncode: raise RuntimeError(kid + '\n' + r.stderr[-2000:])
    return kid, json.loads(Path(tmp).read_text())


def main():
    jobs = int(next((a[7:] for a in sys.argv if a.startswith('--jobs=')), 3))
    masters = kits_and_masters()
    wanted = [a for a in sys.argv[1:] if not a.startswith('--')] or \
             [k for k in PRIORITY if k in masters] + sorted(k for k in masters if k not in PRIORITY)
    wanted = [k for k in wanted if masters[k] not in specs.VARIANTS]     # les trois kits P2 restent tels quels
    os.makedirs(os.environ.setdefault('TRAMSIM_STOCK_SRC', tempfile.mkdtemp(prefix='stock_src_')), exist_ok=True)
    with Pool(jobs) as pool:
        entries = dict(pool.map(stock, [masters[k] for k in wanted]))
    mp = os.path.join(OUT, 'manifest.json'); man = json.load(open(mp))
    for vid, e in entries.items():   # banques sources hors dépôt : le maître est livré par son kit tram_parts
        e['composed'] = 'res://tram_parts/compositions/%s.json' % e['dir']
    man['variants'].update(entries)
    json.dump(man, open(mp, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    with Pool(jobs) as pool:
        results = dict(pool.map(kit, wanted))
    index = json.loads(INDEX.read_text())
    for kid, res in results.items():
        index['kits'][kid] = res['kits'][kid]
        for vid, v in res['variants'].items():
            if v['kit'] == kid: index['variants'][vid] = v
        for lid, l in res['liveries'].items():
            if l.get('kit') == kid and lid in res['liveries']: index['liveries'][lid] = l
    INDEX.write_text(json.dumps(index, indent=2) + '\n')
    for d in {p.parent for p in (ROOT / 'tram_livery').rglob('*.png')}: configure_texture_imports(d)
    print(len(wanted), 'kits HD :', ', '.join(wanted))


if __name__ == '__main__':
    main()
