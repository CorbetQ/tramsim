#!/usr/bin/env python3
"""Collecte les seuls fichiers Commons déjà documentés, sans API ni contournement.
Les licences proviennent du manifeste historique et sont vérifiées dans la page
File; aucune licence générale de pied de page n'est attribuée au média.
"""
import hashlib, html, json, re, subprocess, urllib.parse, urllib.request
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]

def fetch_reference(ref):
    page = ref['page']
    body = subprocess.check_output(['curl', '-f', '-L', '-sS', '--max-time', '20', page]).decode()
    match = re.search(r'<div class="fullMedia">.*?<a href="([^"]+)"', body, re.S)
    if not match:
        raise ValueError('Lien original absent')
    url = html.unescape(match.group(1)).split('?')[0]
    licenses = re.findall(r'<span class="licensetpl(?:_|&#95;)short"[^>]*>(.*?)</span>',body,re.S)
    licenses = [html.unescape(re.sub('<[^>]+>', '', x)).strip() for x in licenses]
    if ref['licence'] not in licenses:
        raise ValueError('Licence de fichier non vérifiée : '+repr(licenses))
    slug = re.sub('[^a-z0-9]+','-',ref['title'].removeprefix('File:').rsplit('.',1)[0].lower()).strip('-')
    dst = ROOT/'samples/raw'/(slug+'.ogg')
    if not dst.exists():
        subprocess.run(['curl','-f','-L','-sS','--max-time','40','--max-filesize','12582912','-o',str(dst),url],check=True)
    duration = float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0',str(dst)]))
    return dict(id=slug,title=ref['title'],page=page,download_url=url,author=ref['auteur'],license=ref['licence'],license_url='https://creativecommons.org/licenses/by-sa/3.0/' if ref['licence']=='CC BY-SA 3.0' else ('https://creativecommons.org/licenses/by-sa/4.0/' if ref['licence']=='CC BY-SA 4.0' else ('https://creativecommons.org/licenses/by/3.0/' if ref['licence']=='CC BY 3.0' else 'https://commons.wikimedia.org/wiki/Template:PD-author')),model='Non identifié ; ne pas attribuer à une famille française',family=None,city='Non identifiée',categories=[],precision='related',redistributable=True,file=str(dst.relative_to(ROOT)),sha256=hashlib.sha256(dst.read_bytes()).hexdigest(),duration_s=duration,processing='Original téléchargé sans transformation',description=ref.get('description',''),audition_status='À écouter ; identification spécifique non certifiée',license_verified_file_page=True)

def main():
    manifest=ROOT/'samples/sources.json';data=json.loads(manifest.read_text());references=json.loads((ROOT/'data/audio/sources.json').read_text())['references']
    for ref in references:
        if any(s['title']==ref['title'] for s in data['sources']):continue
        if any(e['page']==ref['page'] for e in data.get('unavailable',[])):continue
        try:
            row=fetch_reference(ref);data['sources'].append(row);print(row['id'],row['duration_s'],flush=True)
        except Exception as exc:
            data.setdefault('unavailable',[]).append(dict(page=ref['page'],error=str(exc)));print(ref['title'],str(exc),flush=True)
            if '429' in str(exc):
                manifest.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
                break
        manifest.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
if __name__=='__main__':main()
