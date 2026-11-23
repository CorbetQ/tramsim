#!/usr/bin/env python3
"""Rasterize factory paint from the native authoring exporter into reusable body UVs.

Geometry remains in tram_parts; no model is generated for a length or a livery.
The JSON inputs are local authoring intermediates, never downloaded scripts.
"""
import json
from pathlib import Path
from PIL import Image, ImageDraw
from audit_stock import ROOT
from build_stock import configure_texture_imports


def bake(source):
    spec = json.loads(source.read_text())
    width, height = 1024, 512
    side_h = round(height * .625)
    image = Image.new('RGB', (width, height), '#' + spec['base'])
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, width, round(side_h*(3.4-2.75)/3.4)), fill='#'+spec['roof'])
    draw.rectangle((0, round(side_h*(3.4-.45)/3.4), width, side_h), fill='#'+spec['skirt'])
    draw.rectangle((0, side_h, round(width*.1875), height), fill='#'+spec['front'])
    # Opposite sides share the same paint template, as in the native original.
    # Window/light flags and hardware use a separate lossless palette.
    for a, b, c, color, normal in spec['triangles']:
        points = (a,b,c)
        if abs(normal[0]) > .45:
            xy=[((p[2]/spec['length']+.5)*width, (3.4-p[1])/3.4*side_h) for p in points]
        elif abs(normal[2]) > .45 and spec['role'] in ('end_a','end_b'):
            sign = -1 if spec['role']=='end_a' else 1
            if normal[2]*sign < .2: continue
            xy=[((p[0]/2.6+.5)*width*.1875,side_h+(3.4-p[1])/3.4*(height-side_h)) for p in points]
        else:
            continue
        # Bounds stay within their UV island; geometry beyond 3.4m is hardware.
        lo,hi=(0,side_h-1) if abs(normal[0])>.45 else (side_h,height-1)
        xy=[(max(0,min(width-1,x)),max(lo,min(hi,y))) for x,y in xy]
        draw.polygon(xy,fill='#'+color)
    output=(ROOT/spec['output'][6:]).resolve()
    if not output.is_relative_to(ROOT/'tram_livery/livery'): raise ValueError('Unsafe output')
    output.parent.mkdir(parents=True,exist_ok=True)
    image.save(output)


def main():
    sources=sorted((ROOT/'.cache/kit-factory').glob('*.json'))
    for source in sources:bake(source)
    for directory in (ROOT/'tram_livery').rglob('*'):
        if directory.is_dir():configure_texture_imports(directory)
    print(f'{len(sources)} factory body atlases, no size-specific geometry')


if __name__=='__main__':main()
