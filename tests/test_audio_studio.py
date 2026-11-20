"""Real PCM tests, mocked official network boundaries, no cloud/AI required."""
import io
import json
import sys
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import patch
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/audio'))
from studio_lib import dsp, providers, ai, banks
from studio_lib.core import permitted, license_id, safe_path, sha256, write_json, duplicates


class StudioTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir='/dev/shm' if Path('/dev/shm').exists() else None)
        self.root = Path(self.temp.name)
        write_json(self.root / 'data/audio/sources.json', {'files': {}})
        self.rate = 32000
        t = np.arange(self.rate * 2) / self.rate
        self.audio = (.12 * np.sin(2 * np.pi * 311.3 * t) + .025 * np.sin(2 * np.pi * 877 * t))[:, None]
        self.src = self.root / 'source.wav'
        dsp.export(self.audio, self.rate, self.src)

    def tearDown(self):
        self.temp.cleanup()

    def row(self):
        return {'id': 'commons-1', 'name': 'File:Example.wav', 'provider': 'commons',
                'download_url': 'https://upload.wikimedia.org/example.wav',
                'source_url': 'https://commons.wikimedia.org/wiki/File:Example.wav',
                'author': 'Example author', 'license': 'CC BY 4.0',
                'license_url': 'https://creativecommons.org/licenses/by/4.0/', 'evidence': {'api': 'official'}}

    def test_licences_deny_nc_nd_unknown_and_conflicts(self):
        row = self.row()
        self.assertTrue(permitted(row))
        for url in ['https://creativecommons.org/licenses/by-nc/4.0/', 'https://creativecommons.org/licenses/by-nd/4.0/',
                    'https://evil.invalid/licenses/by/4.0/', 'CC BY 4.0 probably', '']:
            self.assertFalse(permitted(dict(row, license_url=url)))
        self.assertFalse(permitted(dict(row, license='CC-BY-3.0')))
        self.assertFalse(permitted(dict(row, author='')))
        self.assertFalse(permitted(dict(row, evidence={})))
        sa = dict(row, license='CC-BY-SA-4.0', license_url='https://creativecommons.org/licenses/by-sa/4.0/')
        self.assertFalse(permitted(sa)); self.assertTrue(permitted(sa, True))
        self.assertEqual(license_id('https://creativecommons.org/publicdomain/zero/1.0/'), 'CC0-1.0')
        self.assertEqual(license_id('http://creativecommons.org/publicdomain/zero/1.0/deed.en'), 'CC0-1.0')

    def test_paths_and_urls(self):
        for path in ['../escape', '.git/config', '/etc/passwd']:
            with self.assertRaises(ValueError): safe_path(self.root, path)
        (self.root / 'link').symlink_to('/tmp', target_is_directory=True)
        with self.assertRaises(ValueError): safe_path(self.root, 'link/escape.wav')
        for url in ['file:///etc/passwd', 'http://upload.wikimedia.org/a.wav', 'https://localhost/a.wav',
                    'https://user:password@upload.wikimedia.org/a.wav', 'https://upload.wikimedia.org:99/a.wav']:
            with self.assertRaises(ValueError): providers.check_url(url)

    def test_atomic_json(self):
        p = self.root / 'manifest.json'
        write_json(p, {'ok': 1})
        self.assertEqual(json.loads(p.read_text()), {'ok': 1})
        self.assertFalse(p.with_suffix('.json.part').exists())

    def test_rms_lufs_peak_actual_export(self):
        m = dsp.analyze(self.src)
        self.assertAlmostEqual(m['duration_s'], 2, places=3)
        self.assertLess(m['true_peak_dbfs_4x'], -10)
        self.assertEqual(m['clipped_samples'], 0)
        self.assertIsNotNone(m['integrated_lufs'])
        self.assertGreater(m['rms_dbfs'], -30)

    def test_process_reproducible_ogg(self):
        recipe = {'rate': 32000, 'channels': 1, 'highpass': 70, 'lowpass': 8000, 'target_lufs': -20,
                  'max_gain_db': 8, 'loop_overlap': .12, 'ceiling_db': -2}
        a, b = self.root / 'a.ogg', self.root / 'b.ogg'
        ma = dsp.process(self.src, a, recipe)
        mb = dsp.process(self.src, b, recipe)
        self.assertEqual(sha256(a), sha256(b))
        self.assertEqual(ma['sha256'], mb['sha256'])
        self.assertEqual(ma['clipped_samples'], 0)
        self.assertLess(ma['true_peak_dbfs_4x'], -1)
        self.assertLess(abs(ma['integrated_lufs'] + 20), 1)
        self.assertAlmostEqual(ma['duration_s'], 1.88, places=2)
        self.assertLess(ma['seam_to_peak'], .025)
        self.assertTrue(Path(str(a) + '.recipe.json').is_file())

    def test_loop_continuity_without_silence_dip(self):
        out = dsp.loopify(self.audio, self.rate, .12)
        self.assertLess(np.max(np.abs(out[-1] - out[0])), 1e-9)
        seam_rms = np.sqrt(np.mean(np.concatenate([out[-320:], out[:320]]) ** 2))
        self.assertGreater(seam_rms, .03)
        self.assertEqual(len(out), len(self.audio) - 3840)
        with self.assertRaises(ValueError): dsp.loopify(self.audio[:30], self.rate, .12)

    def test_silence_and_clipping_detected(self):
        m = dsp.metrics(np.zeros((32000, 1)), 32000)
        self.assertIsNone(m['integrated_lufs']); self.assertEqual(m['silent_fraction_20ms'], 1)
        m = dsp.metrics(np.ones((1000, 1)) * 1.01, 32000, integrated=False)
        self.assertEqual(m['clipped_samples'], 1000)
        silent = self.root / 'silence.wav'; dsp.export(np.zeros((32000, 1)), 32000, silent)
        with self.assertRaises(ValueError): dsp.process(silent, self.root / 'bad.wav', {'target_lufs': -20})

    def test_original_never_overwritten_and_recipe_validated(self):
        original = sha256(self.src)
        with self.assertRaises(ValueError): dsp.process(self.src, self.src, {})
        with self.assertRaises(ValueError): dsp.process(self.src, self.root / 'bad.wav', {'shell': 'malicious'})
        self.assertEqual(sha256(self.src), original)

    def test_comparison_and_segment_suggestions(self):
        result = dsp.compare(self.src, self.src)
        self.assertAlmostEqual(result['spectrum_correlation'], 1)
        self.assertAlmostEqual(result['log_spectrum_shape_rmse_db'], 0)
        self.assertTrue(dsp.segments(self.src, .5))

    def test_ai_disabled_no_network_or_fake_audio(self):
        with patch('urllib.request.build_opener') as network:
            with self.assertRaisesRegex(ValueError, 'disabled'): ai.submit(self.root, 'Tram door')
            network.assert_not_called()
        self.assertFalse(ai.status(self.root)['config']['enabled'])
        self.assertEqual(ai.MODELS['audiogen']['commercial'], 'NO')

    def test_ai_rejects_cloud_and_unreviewed_model(self):
        config = {'enabled': True, 'license_review': 'Test only', 'model_installed_confirmed': True,
                  'weights_path': 'source.wav', 'weights_sha256': sha256(self.src), 'model': 'stable-audio-open-small', 'url': 'https://cloud.invalid'}
        write_json(self.root / '.cache/audio-studio/ai-config.json', config)
        with self.assertRaisesRegex(ValueError, 'loopback'): ai.submit(self.root, 'test')
        config['model'] = 'audiogen'; write_json(self.root / '.cache/audio-studio/ai-config.json', config)
        with self.assertRaisesRegex(ValueError, 'Unapproved'): ai.submit(self.root, 'test')

    def test_download_cache_integrity_and_deduplication(self):
        raw = self.src.read_bytes()
        class Response(io.BytesIO):
            headers = {'Content-Length': str(len(raw))}
        row = self.row()
        with patch.object(providers, 'refresh_source', return_value=row), patch.object(providers.Client, 'open', return_value=Response(raw)) as download:
            first = providers.fetch(self.root, row, 'citadis_302', 'motor')
            second = providers.fetch(self.root, row, 'citadis_302', 'motor')
            self.assertEqual(first['sha256'], second['sha256']); self.assertEqual(download.call_count, 1)
        cached = safe_path(self.root, first['path']); cached.write_bytes(b'corrupt')
        with patch.object(providers, 'refresh_source', return_value=row), patch.object(providers.Client, 'open', return_value=Response(raw)) as download:
            providers.fetch(self.root, row, 'citadis_302', 'motor')
            self.assertEqual(download.call_count, 1)
        self.assertEqual(duplicates({'a': {'sha256': 'abc'}, 'b': {'sha256': 'abc'}}), [['a', 'b']])

    def test_interrupted_download_no_cache_entry_or_partial(self):
        class Response(io.BytesIO):
            headers = {'Content-Length': '900000'}
        row = self.row()
        with patch.object(providers, 'refresh_source', return_value=row), patch.object(providers.Client, 'open', return_value=Response(b'incomplete')):
            with self.assertRaisesRegex(ValueError, 'Interrupted'): providers.fetch(self.root, row, 'citadis_302', 'motor')
        self.assertFalse(list((self.root / '.cache/audio-studio/originals').glob('*.part')))
        self.assertEqual(json.loads((self.root / 'data/audio/sources.json').read_text()), {'files': {}})

    def test_freesound_original_requires_oauth(self):
        row = dict(self.row(), provider='freesound', name='example.wav')
        with patch.object(providers, 'refresh_source', return_value=row), patch.dict('os.environ', {}, clear=True):
            with self.assertRaisesRegex(ValueError, 'OAuth'): providers.fetch(self.root, row, 'generic', 'effect')

    def test_retry_after_and_metadata_cache(self):
        class Opener:
            count = 0
            def open(self, request, timeout):
                self.count += 1
                if self.count == 1:
                    raise urllib.error.HTTPError(request.full_url, 429, 'Rate limited', {'Retry-After': '2'}, None)
                return io.BytesIO(b'{"query": {"ok": true}}')
        opener = Opener(); delays = []
        client = providers.Client(self.root, opener=opener, sleeper=delays.append)
        url = 'https://commons.wikimedia.org/w/api.php?action=query'
        self.assertTrue(client.json(url)['query']['ok'])
        self.assertTrue(client.json(url)['query']['ok']); self.assertEqual(opener.count, 2)
        self.assertIn(2, delays)
        class LongBackoff:
            def open(self, request, timeout):
                raise urllib.error.HTTPError(request.full_url, 429, 'Rate limited', {'Retry-After': '120'}, None)
        client = providers.Client(self.root, opener=LongBackoff(), sleeper=delays.append)
        with self.assertRaisesRegex(ValueError, 'retry the command later'):
            client.open(url)

    def test_commons_search_uses_separate_media_queries(self):
        calls = []
        def api(client, **params):
            calls.append(params['srsearch'])
            return {'query': {'search': [{'title': 'File:Same.ogg'}]}}
        with patch.object(providers, 'commons_api', side_effect=api), patch.object(providers, 'commons_inspect', return_value={'id': 'one'}) as inspect:
            result = providers.search(self.root, 'commons', 'Citadis 302', 2)
        self.assertEqual(calls, ['Citadis 302 filetype:audio', 'Citadis 302 filetype:video'])
        self.assertEqual(len(result), 1); self.assertEqual(inspect.call_count, 1)

    def test_bank_build_real_encoding_and_tamper_detection(self):
        from studio_lib.core import register
        row = dict(self.row(), id='test-source', path='source.wav', sha256=sha256(self.src),
                   kind='recorded_related', family='citadis_302', event='motor', validation_status='technical_validated_human_pending')
        register(self.root, row)
        write_json(self.root / 'data/audio/families.json', {'profiles': {'citadis_302': {}}, 'banks': {}})
        manifest = {'id': 'test_bank_v1', 'label': 'Fixture bank, not an authentic tram', 'compatible_families': ['citadis_302'],
                    'layers': {'motor': {'source_id': 'test-source', 'recipe': {'loop_overlap': .12, 'target_lufs': -20}}}}
        built = banks.build(self.root, manifest)
        self.assertEqual(built['production_status'], 'candidate_human_audition_required')
        self.assertTrue(banks.validate(self.root, waveforms=True)['ok'])
        self.assertTrue(banks.rebuild(self.root, manifest['id'])['ok'])
        entries = json.loads((self.root / 'data/audio/sources.json').read_text())['catalogue']
        derivative = entries['asset:studio/test_bank_v1_motor.ogg']
        self.assertEqual(derivative['license'], row['license'])
        self.assertEqual(derivative['parent_ids'], ['test-source'])
        self.assertIn(derivative['id'], entries['test-source']['derived_files'])
        self.src.write_bytes(b'tampered')
        manifest['id'] = 'test_bank_v2'
        with self.assertRaisesRegex(ValueError, 'SHA-256'): banks.build(self.root, manifest)

    def test_ai_adapter_local_job_receipt_not_a_generation_claim(self):
        config = {'enabled': True, 'license_review': 'Mock endpoint contract only; no inference', 'model_installed_confirmed': True,
                  'weights_path': 'source.wav', 'weights_sha256': sha256(self.src), 'model': 'stable-audio-open-small'}
        write_json(self.root / '.cache/audio-studio/ai-config.json', config)
        class Opener:
            def open(self, request, timeout):
                payload = json.loads(request.data)
                assert payload['seed'] == 42 and payload['variations'] == 2
                return io.BytesIO(b'{"job_id":"test-job"}')
        with patch('urllib.request.build_opener', return_value=Opener()):
            receipt = ai.submit(self.root, 'test', seed=42, variations=2)
        self.assertEqual(receipt['status'], 'submitted_not_generated')
        self.assertEqual(len(list((self.root / '.cache/audio-studio/ai-jobs').glob('*.json'))), 1)
        self.assertFalse(list((self.root / '.cache/audio-studio/ai-jobs').glob('*.wav')))

    def test_local_ai_import_requires_provenance_and_labels(self):
        from studio_lib import catalogue
        row = dict(self.row(), id='local-test', path='source.wav', kind='ai_generated', family='generic', event='effect')
        with self.assertRaisesRegex(ValueError, 'AI exports'): catalogue.add_local(self.root, row)
        row['ai_metadata'] = {'model': 'fixture-only', 'prompt': 'test', 'seed': 7, 'weights_sha256': '0' * 64, 'license_review': 'Fixture, no real model inference'}
        result = catalogue.add_local(self.root, row)
        self.assertEqual(result['kind'], 'ai_generated')
        self.assertEqual(result['sha256'], sha256(self.src))

    def test_bank_activation_requires_human_audition(self):
        with self.assertRaisesRegex(ValueError, 'human-reviewed'): banks.activate(self.root, 'candidate', 'citadis_302')


if __name__ == '__main__':
    unittest.main()
