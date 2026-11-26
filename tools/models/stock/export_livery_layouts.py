"""Export the editable atlas swatches from the same authoring materials as the HD models."""
import json
from pathlib import Path
import specs
from layout import Train
from geom import Builder
from citadis import materials, swatch_colors


def main():
    result = {}
    # P4 : tous les maîtres de kits HD (les autres variantes d'un kit retombent sur leur maître, LiveryPainter)
    manifest = json.loads((Path(specs.ROOT) / 'assets/models/rolling_stock/manifest.json').read_text())['variants']
    for vid in list(specs.VARIANTS) + sorted(v for v in manifest if v not in specs.VARIANTS):
        builder = Builder()
        materials(builder, Train(specs.load(vid)), 0, '4k')
        swatches = {}
        for i, name in enumerate(sorted(swatch_colors(builder))):
            if name.startswith('paint_'):
                swatches[name.removeprefix('paint_')] = [832 + i % 50 * 64, 1344 + i // 50 * 64]
        result[vid] = {'atlas': [4096, 2048], 'swatches': swatches}
    path = Path(specs.ROOT) / 'data/rolling_stock/livery_layouts.json'
    path.write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
