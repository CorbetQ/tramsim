#!/usr/bin/env python3
"""Offline HD stock inventory, real triangle/texture checks and SHA-256 report.

python tools/models/stock/audit_stock.py --report build/stock-hd/audit.json
Does not rebuild assets or change the manifest. Uses only the Python standard library.
"""
import argparse
import hashlib
import json
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def local_file(directory, relative):
    path = (directory / relative).resolve()
    if not path.is_relative_to(directory.resolve()) or not path.is_file():
        raise ValueError(f"Missing or unsafe asset: {relative}")
    return path


def glb_info(path):
    data = path.read_bytes()
    if len(data) < 20:
        raise ValueError(f"Truncated GLB: {path.name}")
    magic, version, length, chunk, kind = struct.unpack_from('<4sIIII', data)
    if magic != b'glTF' or version != 2 or length != len(data) or kind != 0x4E4F534A:
        raise ValueError(f"Invalid GLB header: {path.name}")
    doc = json.loads(data[20:20 + chunk])
    binary_offset = 20 + chunk
    if binary_offset + 8 > len(data):
        raise ValueError(f'Missing binary chunk: {path.name}')
    binary_size, binary_kind = struct.unpack_from('<II', data, binary_offset)
    if binary_kind != 0x004E4942 or binary_offset + 8 + binary_size != len(data):
        raise ValueError(f'Invalid binary chunk: {path.name}')
    if any('uri' in buffer or buffer['byteLength'] > binary_size for buffer in doc.get('buffers', [])):
        raise ValueError(f'External or truncated vertex buffer: {path.name}')
    triangles = 0
    surfaces = 0
    for mesh in doc.get('meshes', []):
        for primitive in mesh['primitives']:
            if primitive.get('mode', 4) != 4:
                raise ValueError(f"Non-triangle primitive: {path.name}")
            accessor = primitive.get('indices', primitive['attributes']['POSITION'])
            count = doc['accessors'][accessor]['count']
            if count % 3:
                raise ValueError(f"Incomplete triangle: {path.name}")
            triangles += count // 3
            surfaces += 1
    if triangles == 0:
        raise ValueError(f"Empty model: {path.name}")
    textures = {}
    for image in doc.get('images', []):
        uri = image.get('uri')
        if uri:
            source = local_file(path.parent, uri)
            raw = source.read_bytes()
            # Stock textures are PNG; read IHDR without requiring Pillow in CI.
            if raw[:8] != b'\x89PNG\r\n\x1a\n' or len(raw) < 24:
                raise ValueError(f'Unsupported stock texture: {uri}')
            width, height = struct.unpack_from('>II', raw, 16)
            settings = Path(str(source) + '.import').read_text()
            if not re.search(r'^compress/mode=2$', settings, re.MULTILINE) or not re.search(r'^mipmaps/generate=true$', settings, re.MULTILINE):
                raise ValueError(f'Missing GPU compression/mipmaps: {uri}')
            textures[uri] = {'bytes': len(raw), 'width': width, 'height': height,
                             'sha256': hashlib.sha256(raw).hexdigest(), 'gpu_import': True, 'mipmaps': True}
    return {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
            'triangles': triangles, 'surfaces': surfaces, 'textures': textures}


def audit(root=ROOT):
    directory = root / 'assets/models/rolling_stock'
    manifest = json.loads((directory / 'manifest.json').read_text())
    budgets = json.loads((root / 'docs/refonte-visuelle/budgets.json').read_text())['rolling_stock_lod']
    if manifest.get('version') != 1 or not manifest.get('variants'):
        raise ValueError('Empty or unsupported stock manifest')
    result = {'schema': 1, 'manifest': 'assets/models/rolling_stock/manifest.json',
              'variants': {}, 'errors': [], 'perceptual_validation': 'human_review_required'}
    for vid, entry in manifest['variants'].items():
        files = {}
        base = directory / entry['dir']
        if not base.resolve().is_relative_to(directory.resolve()):
            result['errors'].append(f'{vid}: unsafe directory')
            continue
        if not entry.get('license') or not entry.get('sources'):
            result['errors'].append(f'{vid}: missing provenance')
        if abs(sum(entry['modules']) - entry['length_m']) > .02:
            result['errors'].append(f'{vid}: length inconsistent with modules')
        try:
            plan = json.loads(local_file(root / 'data/rolling_stock/plans', entry['family'] + '.json').read_text())
            scale = entry['length_m'] / sum(module['length_m'] for module in plan['modules'])
            expected = [module['length_m'] * scale for module in plan['modules']]
            if len(expected) != len(entry['modules']) or any(abs(a - b) > .02 for a, b in zip(expected, entry['modules'])):
                result['errors'].append(f'{vid}: modules disagree with source plan')
            if sum(len(module.get('doors', [])) for module in plan['modules']) != entry['doors']:
                result['errors'].append(f'{vid}: door count disagrees with source plan')
            if abs(entry['width_m'] - plan['width_m']) > .02:
                result['errors'].append(f'{vid}: width disagrees with source plan')
        except (OSError, ValueError, KeyError, ZeroDivisionError) as error:
            result['errors'].append(f'{vid}: invalid source plan: {error}')
        for level, spec in list(entry['lods'].items()) + [('cab', entry['cab'])]:
            budget = budgets['LOD0' if level == 'cab' else ('LOD3_impostor' if level == 'LOD3' else level)]
            for platform in ('pc', 'mobile'):
                filename = spec.get('mobile_file', spec['file']) if platform == 'mobile' else spec['file']
                key = f'{level}_{platform}'
                try:
                    info = glb_info(local_file(base, filename))
                    files[key] = {'file': filename, **info}
                    cap = budget[platform + ('_cab_tris' if level == 'cab' else '_tris')]
                    if info['triangles'] > cap:
                        result['errors'].append(f'{vid}/{key}: {info["triangles"]} > {cap} triangles')
                    declared = spec.get('mobile_tris') if platform == 'mobile' else spec.get('tris')
                    if declared is not None and declared != info['triangles']:
                        result['errors'].append(f'{vid}/{key}: measured triangles disagree with manifest')
                    texture_cap = (1024 if level == 'cab' else 2048) if platform == 'mobile' else (2048 if level == 'cab' else 4096)
                    for texture, properties in info['textures'].items():
                        if max(properties['width'], properties['height']) > texture_cap:
                            result['errors'].append(f'{vid}/{key}/{texture}: texture exceeds {texture_cap}px')
                except (OSError, ValueError, KeyError, struct.error) as error:
                    result['errors'].append(f'{vid}/{key}: {error}')
        result['variants'][vid] = files
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    report = audit()
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    for vid, files in report['variants'].items():
        print(vid + ': ' + ', '.join(f'{key}={info["triangles"]}' for key, info in files.items()))
    for error in report['errors']:
        print('FAIL: ' + error)
    raise SystemExit(bool(report['errors']))


if __name__ == '__main__':
    main()
