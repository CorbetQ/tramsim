#!/usr/bin/env python3
"""Migration sans nouvel échantillonnage : TTR1 -> TTR2 (float32), bords partagés soudés.

Conserve l'information disponible ; ne prétend pas améliorer la résolution IGN.
Chaque sommet situé sur un bord est la moyenne de toutes ses copies présentes.
Les blocs eau / ouvrages sont conservés octet pour octet. Idempotent.
"""
import argparse
import json
import struct
from collections import defaultdict
from pathlib import Path

GRID = 41

def read_tiles(data):
    magic, count = data[:4], struct.unpack_from('<I', data, 4)[0]
    if magic not in (b'TTR1', b'TTR2'):
        raise ValueError('Format terrain inconnu')
    tiles = {}
    for i in range(count):
        x, z, off, size = struct.unpack_from('<iiII', data, 8 + 16*i)
        if magic == b'TTR1':
            base, step = struct.unpack_from('<hB', data, off)
            grid = [base/10 + q*step/100 for q in data[off+3:off+3+GRID*GRID]]
            start = off+3+GRID*GRID
        else:
            grid = list(struct.unpack_from('<1681f', data, off))
            start = off+4*GRID*GRID
        tiles[x, z] = [grid, data[start:off+size]]
    return tiles


def stitch(tiles):
    shared = defaultdict(list)
    for (tx, tz), (grid, _) in tiles.items():
        for z in range(GRID):
            for x in range(GRID):
                if x in (0,40) or z in (0,40):
                    shared[tx*40+x, tz*40+z].append((grid,z*GRID+x))
    worst = 0.
    for copies in shared.values():
        vals = [g[i] for g,i in copies]
        worst = max(worst,max(vals)-min(vals))
        mean = sum(vals)/len(vals)
        for grid,i in copies:
            grid[i] = mean
    return worst


def encode(tiles):
    head = b'TTR2'+struct.pack('<I', len(tiles))
    table, blobs = bytearray(), []
    off = 8 + 16*len(tiles)
    for (x,z), (grid, suffix) in sorted(tiles.items()):
        block = struct.pack('<1681f', *grid)+suffix
        table += struct.pack('<iiII',x,z,off,len(block))
        off += len(block)
        blobs.append(block)
    return head+table+b''.join(blobs)


def main(root):
    report = {}
    for path in sorted(root.glob('*_terrain.bin')):
        tiles = read_tiles(path.read_bytes())
        worst = stitch(tiles)
        path.write_bytes(encode(tiles))
        meta_path = path.with_suffix('.json')
        meta = json.loads(meta_path.read_text())
        meta.update(terrain_format='TTR2', height_encoding='float32 metres', shared_vertices=True)
        meta_path.write_text(json.dumps(meta,ensure_ascii=False,indent=1)+'\n')
        report[path.stem.removesuffix('_terrain')] = dict(tiles=len(tiles), max_previous_seam_m=round(worst,4), max_seam_m=0.)
    return report

if __name__ == '__main__':
    ap=argparse.ArgumentParser(); ap.add_argument('scenes',type=Path); ap.add_argument('--report',type=Path)
    a=ap.parse_args(); r=main(a.scenes)
    if a.report:a.report.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n')
    print(f'{len(r)} villes ; rupture maximale avant : {max(x["max_previous_seam_m"] for x in r.values()):.2f} m ; après : 0 m')
