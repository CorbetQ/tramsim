"""Package genuine Godot captures for human A/B audition; no level normalization."""
import html
from pathlib import Path
from .core import safe_path, read_json, write_json, sha256, catalogue
from . import dsp


def package(root):
    names = ['studio_baseline_302', 'studio_after_302', 'studio_candidate_302', 'studio_baseline_305', 'studio_after_305']
    out = safe_path(root, 'docs/audio-studio/demos')
    out.mkdir(parents=True, exist_ok=True)
    entries = catalogue(root)['catalogue']
    by_path = {r['path']: r for r in entries.values()}
    summaries = {}
    for name in names:
        src = safe_path(root, 'samples/demos/' + name + '.wav')
        receipt = read_json(src.with_suffix('.json'))
        if receipt['driver'] == 'Dummy' or receipt['duration'] < 45:
            raise ValueError('Not a valid actual mixer capture')
        audio, rate = dsp.decode(src)
        dst = out / (name + '.ogg')
        dsp.export(audio, rate, dst)
        summary = {k: receipt[k] for k in ['family', 'resolved_family', 'resolved_bank', 'variant', 'driver', 'mix_rate', 'recording_rate', 'duration', 'capture_mode', 'filter_mode', 'method', 'stream_paths']}
        summary.update(original_wav_sha256=sha256(src), preview_sha256=sha256(dst),
                       audio_code_sha256=receipt.get('audio_code_sha256', 'baseline: see baseline.json'),
                       engine_version=receipt.get('engine_version', '4.6.3 (capture log)'),
                       level_processing='No normalization; one Vorbis preview encode of original PCM Master capture',
                       encoded_metrics=dsp.analyze(dst))
        summary['encoded_metrics']['path'] = dst.name
        summary['attributions'] = sorted({f"{by_path[p.removeprefix('res://')]['author']} | {by_path[p.removeprefix('res://')]['source_url']} | {by_path[p.removeprefix('res://')]['license']}" for p in receipt['stream_paths'].values() if p.removeprefix('res://') in by_path})
        summary['timeline'] = [{k: row[k] for k in ['seconds', 'phase', 'kmh', 'notch', 'external', 'tunnel', 'bridge']} for row in receipt['timeline']]
        summaries[name] = summary
        write_json(out / (name + '.json'), summary)
    comparisons = {}
    for family in ('302', '305'):
        comparisons[family] = dsp.compare(safe_path(root, 'samples/demos/studio_baseline_' + family + '.wav'), safe_path(root, 'samples/demos/studio_after_' + family + '.wav'))
        for side in ('first', 'second'):
            comparisons[family][side]['path'] = Path(comparisons[family][side]['path']).name
    write_json(out / 'comparisons.json', comparisons)
    cards = ''
    labels = ['302 — référence avant modifications (Rotterdam apparenté)', '302 — après : même banque, transitions corrigées',
              '302 — candidat Moscou, famille exacte, pas motrice isolée', '305 — avant, modèle procédural', '305 — après, même modèle, transitions corrigées']
    for name, label in zip(names, labels):
        r = summaries[name]
        cards += f'<article><h2>{html.escape(label)}</h2><audio controls preload="none" src="{name}.ogg"></audio><p><a href="{name}.ogg" download>OGG</a> · <a href="{name}.json">Mesures et provenance</a></p><small>Godot / {html.escape(r["driver"])} · {r["duration"]:.2f} s · {html.escape(r["resolved_bank"])}</small></article>'
    text = '''<!doctype html><html lang="fr"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>TramSim Audio Studio — écoute comparative</title><style>body{font:17px system-ui;background:#111b25;color:#ecf4fa;max-width:960px;margin:40px auto;padding:0 20px}h1{font-size:2rem}article{background:#1c2b39;padding:20px;border-radius:14px;margin:18px 0}h2{font-size:1.2rem}audio{width:100%}a{color:#76d6cc}small{color:#bdcbd7}p{line-height:1.6}.note{border-left:4px solid #e2b65e;padding-left:18px}</style><h1>TramSim / Audio Studio</h1><p>Captures du véritable mixage Godot, avec vitesses imposées pour un scénario comparable. Aucune normalisation du mix. Aperçus OGG issus des WAV Master conservés localement.</p><p class="note">Le 305 reste une restitution modélisée. Le candidat 302 de Moscou est une captation extérieure : il contient aussi le roulement et l'environnement. Aucun son IA. L'écoute humaine n'a pas encore validé un remplacement des banques approuvées.</p><p>0–7 s : arrêt, portes, gong · 7–23 : accélération · 23–27 : roue libre extérieure · 27–31 : tunnel · 31–35 : pont, retour cabine à 33 s · 35–39 : freinage final · 39–44 : portes · 44–46 : pause · 46–48 : reprise. Comparer surtout les changements de vue vers 23 et 33 s. Les banques 302/305 de production restent identiques.</p>''' + cards + '<p><a href="../ATTRIBUTIONS.md">Attributions</a> · <a href="comparisons.json">Comparaisons techniques</a> · <a href="../REPORT.md">Rapport</a></p></html>'
    (out / 'index.html').write_text(text, encoding='utf-8')
    return {'ok': True, 'captures': len(names), 'directory': str(out.relative_to(root)), 'human_audition': 'pending'}
