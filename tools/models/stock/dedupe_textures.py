#!/usr/bin/env python3
"""P4 : dédoublonne les textures techniques des kits (sol, tissu, grain, métal, pupitre) référencées par les GLB de
tram_parts : une copie par contenu dans tram_livery/shared/, URI des GLB réécrites. Les atlas de livrée
(tram_livery/livery/, adressés par parts_manifest.json) ne sont pas touchés.
Rangement : tram_livery/interior/shared/<hash>/<nom> (sol, tissu, pupitre) et tram_livery/materials/shared/<hash>/<nom>."""
import hashlib, json, os, struct
from pathlib import Path
import specs
from build_stock import configure_texture_imports

ROOT = Path(specs.ROOT); OLD = ROOT / 'tram_livery/shared'
INTERIOR = ('floor_', 'fabric_', 'cab_')


def target(src, h):
    cat = 'interior' if src.name.split('_', 1)[-1].startswith(INTERIOR) or src.name.startswith(INTERIOR) else 'materials'
    name = src.name.split('_', 1)[1] if src.parent == OLD else src.name
    return ROOT / 'tram_livery' / cat / 'shared' / h / name


def rewrite(glb):
    raw = glb.read_bytes(); size, kind = struct.unpack_from('<II', raw, 12)
    doc = json.loads(raw[20:20 + size]); binary = raw[20 + size:]; changed = False
    for image in doc.get('images', []):
        uri = image.get('uri', '')
        src = (glb.parent / uri).resolve()
        if not uri or not src.exists() or '/tram_livery/livery/' in str(src) or src.parent.parent.name == 'shared': continue
        data = src.read_bytes(); h = hashlib.sha1(data).hexdigest()[:12]
        dst = target(src, h)
        if not dst.exists(): dst.parent.mkdir(parents=True, exist_ok=True); dst.write_bytes(data)
        image['uri'] = os.path.relpath(dst, glb.parent).replace(os.sep, '/'); changed = True
    if changed:
        enc = json.dumps(doc, separators=(',', ':'), ensure_ascii=False).encode(); enc += b' ' * ((-len(enc)) % 4)
        glb.write_bytes(struct.pack('<4sII', b'glTF', 2, 20 + len(enc) + len(binary)) + struct.pack('<II', len(enc), kind) + enc + binary)
    return changed


def main():
    n = sum(rewrite(g) for g in sorted((ROOT / 'tram_parts').rglob('*.glb')))
    used = set()
    for g in (ROOT / 'tram_parts').rglob('*.glb'):
        raw = g.read_bytes(); size = struct.unpack_from('<I', raw, 12)[0]
        for im in json.loads(raw[20:20 + size]).get('images', []): used.add((g.parent / im.get('uri', '')).resolve())
    removed = 0
    for d in ('interior', 'materials'):
        for p in (ROOT / 'tram_livery' / d).rglob('*.png'):
            if p.resolve() not in used and p.name.startswith(('floor_', 'fabric_', 'cab_', 'metal_')):
                p.unlink(); removed += 1
                imp = Path(str(p) + '.import')
                if imp.exists(): imp.unlink()
    if OLD.exists():
        for p in OLD.iterdir(): p.unlink()
        OLD.rmdir()
    shared = [d for c in ('interior', 'materials') for d in (ROOT / 'tram_livery' / c / 'shared').glob('*')]
    for d in shared: configure_texture_imports(d)
    print(n, 'GLB réécrits ;', removed, 'copies supprimées ;', len(shared), 'textures partagées')


if __name__ == '__main__':
    main()
