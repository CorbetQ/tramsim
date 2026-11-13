#!/usr/bin/env python3
"""Construit un APK d'aperçu installable à côté du jeu et un EXE, sans modifier les fichiers du dépôt."""
from pathlib import Path
import shutil,subprocess,os,re,json,hashlib
ROOT=Path(__file__).resolve().parents[2];STAGE=ROOT/'.cache/stock-preview-project';OUT=ROOT/'build/stock-preview'
if STAGE.exists():shutil.rmtree(STAGE)
def copy(source,target):
 source=Path(source)
 if source.suffix in ['.json','.bin'] and source.parent.name in ['scenes','free','networks']:os.link(source,target);return str(target)
 return shutil.copy2(source,target)
shutil.copytree(ROOT,STAGE,ignore=shutil.ignore_patterns('.git','.godot','.cache','docs','tools','tests','build','android'),copy_function=copy)
OUT.mkdir(parents=True,exist_ok=True)
p=STAGE/'project.godot';s=p.read_text().replace('config/name="Tram Sim France"','config/name="TramSim — Aperçu des rames"').replace('config/version="0.10.0"','config/version="0.10.0-stock.1"');p.write_text(s)
p=STAGE/'export_presets.cfg';s=p.read_text().replace('version/code=13','version/code=1').replace('version/name="0.10.0"','version/name="0.10.0-stock.1"').replace('package/unique_name="fr.tramsim.game"','package/unique_name="fr.tramsim.stockpreview"').replace('package/name="Tram Sim France"','package/name="TramSim Rames — Aperçu"')
key=Path('/workspace/tramsim/.cache/signing/tramsim-debug.keystore')
if not key.exists():raise FileNotFoundError('Clé de développement manquante')
s=s.replace('keystore/debug=""','keystore/debug="'+str(key)+'"').replace('keystore/debug_user=""','keystore/debug_user="tramsim-dev"').replace('keystore/debug_password=""','keystore/debug_password="android"')
p.write_text(s)
for name,args in [('import',['--editor','--import']),('android',['--export-debug','Android',str(OUT/'TramSim-Rames-Preview.apk')]),('windows',['--export-release','Windows',str(OUT/'TramSim-Rames-Preview.exe')])]:
 with open(OUT/(name+'.log'),'w') as log:
  result=subprocess.run(['godot','--headless','--path',str(STAGE),*args],stdout=log,stderr=subprocess.STDOUT)
 if result.returncode:raise RuntimeError(name+' : consulter '+str(OUT/(name+'.log')))
 print('BUILT',name,flush=True)
artifacts={p.name:{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in OUT.iterdir() if p.suffix in ['.apk','.exe']}
(OUT/'SHA256.json').write_text(json.dumps(artifacts,indent=2)+'\n');print(json.dumps(artifacts),flush=True)
