"""Official APIs only. No scraping or access-control bypass."""
import hashlib
import html
import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from email.utils import parsedate_to_datetime
from datetime import datetime, timezone
from pathlib import Path
from .core import safe_path, sha256, write_json, permitted, license_id, utc, register

UA = 'TramSimAudioStudio/1.0 (https://github.com/CorbetQ/tramsim; audio provenance research)'
HOSTS = {'commons.wikimedia.org', 'upload.wikimedia.org', 'freesound.org', 'cdn.freesound.org', 'cdn.freesound.org.uk'}
EXTENSIONS = {'.wav', '.ogg', '.flac', '.mp3', '.mp4', '.webm', '.oga', '.opus'}


def check_url(url):
    u = urllib.parse.urlsplit(url)
    if u.scheme != 'https' or u.hostname not in HOSTS or u.username or u.password or u.port not in (None, 443):
        raise ValueError('Unapproved source URL')
    return url


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        check_url(newurl)
        # Never leak OAuth or API credentials to a CDN or another host.
        new = super().redirect_request(req, fp, code, msg, headers, newurl)
        if urllib.parse.urlsplit(req.full_url).hostname != urllib.parse.urlsplit(newurl).hostname:
            new.remove_header('Authorization')
        return new


class Client:
    def __init__(self, root, opener=None, sleeper=time.sleep):
        self.cache = safe_path(root, '.cache/audio-studio/http')
        self.cache.mkdir(parents=True, exist_ok=True)
        self.opener = opener or urllib.request.build_opener(SafeRedirect())
        self.sleep = sleeper
        self.last = 0.0

    def open(self, url, headers=None):
        check_url(url)
        delay = 0.6 - (time.monotonic() - self.last)
        if delay > 0:
            self.sleep(delay)
        for attempt in range(3):
            self.last = time.monotonic()
            try:
                return self.opener.open(urllib.request.Request(url, headers={'User-Agent': UA, **(headers or {})}), timeout=30)
            except urllib.error.HTTPError as ex:
                if ex.code not in (429, 500, 502, 503, 504) or attempt == 2:
                    raise
                wait = ex.headers.get('Retry-After', '')
                if wait.isdigit():
                    seconds = float(wait)
                elif wait:
                    try:
                        seconds = max(0, (parsedate_to_datetime(wait) - datetime.now(timezone.utc)).total_seconds())
                    except (TypeError, ValueError):
                        seconds = 2 ** (attempt + 1)
                else:
                    seconds = 2 ** (attempt + 1)
                if seconds > 30:
                    raise ValueError('Provider rate limit: Retry-After exceeds 30 seconds; retry the command later') from ex
                self.sleep(seconds)

    def json(self, url, headers=None, refresh=False):
        # Credentials never persisted, and distinct tokens never share a cached response.
        key = hashlib.sha256((url + json.dumps(headers or {}, sort_keys=True)).encode()).hexdigest()
        path = self.cache / (key + '.json')
        if not refresh and path.exists():
            return json.loads(path.read_text())
        with self.open(url, headers) as stream:
            raw = stream.read(4 * 1024 * 1024 + 1)
        if len(raw) > 4 * 1024 * 1024:
            raise ValueError('API response exceeds limit')
        result = json.loads(raw)
        if 'error' in result:
            raise ValueError(str(result['error']))
        write_json(path, result)
        return result


def commons_api(client, refresh=False, **params):
    return client.json('https://commons.wikimedia.org/w/api.php?' + urllib.parse.urlencode(dict(action='query', format='json', **params)), refresh=refresh)


def clean(meta, key):
    return html.unescape(re.sub('<[^>]+>', '', meta.get(key, {}).get('value', ''))).strip()


def commons_inspect(client, title, refresh=False):
    if not title.startswith('File:') or '|' in title:
        raise ValueError('Expected a single Commons File: title')
    params = dict(prop='videoinfo', titles=title, viprop='url|size|extmetadata|mediatype')
    result = commons_api(client, refresh=refresh, **params)
    page = next(iter(result.get('query', {}).get('pages', {}).values()), {})
    infos = page.get('videoinfo', [])
    if not infos:
        result = commons_api(client, refresh=refresh, prop='imageinfo', titles=title, iiprop='url|size|extmetadata|mediatype')
        page = next(iter(result.get('query', {}).get('pages', {}).values()), {})
        infos = page.get('imageinfo', [])
    if not infos:
        raise ValueError('No downloadable file metadata')
    info = infos[0]
    meta = info.get('extmetadata', {})
    row = {'id': 'commons-' + str(page['pageid']), 'name': title, 'provider': 'commons',
           'source_url': info.get('descriptionurl', 'https://commons.wikimedia.org/wiki/' + urllib.parse.quote(title)),
           'download_url': info['url'], 'author': clean(meta, 'Artist'),
           'license': clean(meta, 'LicenseShortName'), 'license_url': clean(meta, 'LicenseUrl'),
           'bytes': info.get('size'), 'duration_s': info.get('duration'), 'media_type': info.get('mediatype'),
           'evidence': {'api': 'Commons videoinfo/imageinfo', 'retrieved_at': utc(), 'metadata': meta}}
    row['download_permitted'] = permitted(row)
    return row


def search(root, provider, query, limit=5, minimum=0, maximum=120):
    client = Client(root)
    if provider == 'commons':
        hits = {}
        # CirrusSearch filetype operators inside OR parentheses produce empty results
        # on Commons. Query each media type explicitly, then deduplicate.
        for media in ('audio', 'video'):
            result = commons_api(client, list='search', srnamespace=6, srlimit=max(1, min(limit, 20)), srsearch=query + ' filetype:' + media)
            for hit in result.get('query', {}).get('search', []):
                hits[hit['title']] = hit
        return [commons_inspect(client, title) for title in list(hits)[:max(1, min(limit, 20))]]
    if provider == 'freesound':
        token = os.environ.get('FREESOUND_API_KEY')
        if not token:
            raise ValueError('FREESOUND_API_KEY required for official API search; no scraping fallback')
        params = dict(query=query, page_size=min(limit, 20), filter=f'duration:[{minimum} TO {maximum}]',
                      fields='id,name,url,username,license,duration,samplerate,channels,filesize,type,previews,download')
        data = client.json('https://freesound.org/apiv2/search/text/?' + urllib.parse.urlencode(params), {'Authorization': 'Token ' + token})
        return [freesound_row(r) for r in data.get('results', [])]
    # These sources do not have a stable official download/search API equivalent.
    # Supply review links, never pretend the library-wide licence verifies a file.
    sites = {'kenney': 'https://kenney.nl/assets?q=', 'opengameart': 'https://opengameart.org/art-search-advanced?keys=',
             'institutional': 'https://www.europeana.eu/en/search?query='}
    return [{'provider': provider, 'review_url': sites[provider] + urllib.parse.quote(query),
             'validation_status': 'human_review_required', 'download_permitted': False}]


def freesound_row(row):
    result = {'id': 'freesound-' + str(row['id']), 'provider': 'freesound', 'name': row['name'],
              'source_url': row['url'], 'author': row['username'], 'license': license_id(row['license']),
              'license_url': row['license'], 'download_url': row.get('download'),
              'previews': row.get('previews', {}), 'file_type': row.get('type'), 'duration_s': row.get('duration'), 'bytes': row.get('filesize'),
              'evidence': {'api': 'Freesound API v2', 'retrieved_at': utc(), 'metadata': row}}
    result['download_permitted'] = permitted(result)
    return result


def refresh_source(root, candidate):
    """Do not trust editable candidate JSON as proof of licence or download rights."""
    client = Client(root)
    if candidate.get('provider') == 'commons':
        return commons_inspect(client, candidate['name'], refresh=True)
    if candidate.get('provider') == 'freesound':
        ident = str(candidate['id']).removeprefix('freesound-')
        if not ident.isdigit():
            raise ValueError('Invalid Freesound id')
        token = os.environ.get('FREESOUND_API_KEY')
        if not token:
            raise ValueError('FREESOUND_API_KEY required to verify source')
        return freesound_row(client.json('https://freesound.org/apiv2/sounds/' + ident + '/', {'Authorization': 'Token ' + token}, refresh=True))
    raise ValueError('Provider requires human review; automated download disabled')


def fetch(root, candidate, family, event, kind='recorded_related', preview=False, max_bytes=128 * 1024 * 1024):
    row = refresh_source(root, candidate)
    if not permitted(row):
        raise ValueError('Source licence/provenance not approved by default policy')
    if kind not in {'recorded_exact', 'recorded_related'}:
        raise ValueError('Downloaded recordings must be classified honestly')
    headers = {}
    url = row['download_url']
    row['source_quality'] = 'original'
    if row['provider'] == 'freesound':
        if preview:
            url = row['previews'].get('preview-hq-ogg') or row['previews'].get('preview-hq-mp3')
            row['source_quality'] = 'lossy_preview'
        else:
            token = os.environ.get('FREESOUND_ACCESS_TOKEN')
            if not token:
                raise ValueError('Original download requires OAuth FREESOUND_ACCESS_TOKEN; use --preview explicitly for an API-authorized preview')
            headers['Authorization'] = 'Bearer ' + token
    check_url(url)
    ext = Path(urllib.parse.unquote(urllib.parse.urlsplit(url).path)).suffix.lower()
    if row['provider'] == 'freesound' and not preview:
        ext = ('.' + row['file_type'].lower()) if row.get('file_type') else Path(row['name']).suffix.lower()
    if ext not in EXTENSIONS:
        raise ValueError('Unsupported media extension')
    if row.get('bytes') and not preview and int(row['bytes']) > max_bytes:
        raise ValueError('Original exceeds download budget; not silently replacing it with a transcode')
    cache = safe_path(root, '.cache/audio-studio/originals')
    cache.mkdir(parents=True, exist_ok=True)
    receipt = cache / (row['id'] + '.json')
    if receipt.exists():
        old = json.loads(receipt.read_text())
        path = safe_path(root, old['path'])
        if old.get('download_url') == url and path.exists() and sha256(path) == old['sha256']:
            register(root, old)
            return old
    part = cache / (row['id'] + '.part')
    # Restart rather than append: safe for servers without trustworthy Range/ETag support.
    try:
        with Client(root).open(url, headers) as response, part.open('wb') as output:
            size = 0
            expected = response.headers.get('Content-Length')
            while chunk := response.read(256 * 1024):
                size += len(chunk)
                if size > max_bytes:
                    raise ValueError('Download budget exceeded')
                output.write(chunk)
            if expected and size != int(expected):
                raise ValueError('Interrupted/incomplete download')
            if row.get('bytes') and not preview and size != int(row['bytes']):
                raise ValueError('Download length differs from official original metadata')
        from .dsp import probe
        metadata = probe(part)
        digest = sha256(part)
        path = cache / (digest + ext)
        part.replace(path)
    finally:
        part.unlink(missing_ok=True)
    row.update(path=str(path.relative_to(root)), sha256=digest, retrieved_at=utc(), family=family, event=event,
               kind=kind, validation_status='technical_validated_human_pending', quality='unreviewed', storage='cache_original',
               derived_files=[], transformations=[], compatible_profiles=[family], **metadata)
    write_json(receipt, row)
    register(root, row)
    return row
