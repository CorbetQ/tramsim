#!/usr/bin/env python3
"""Exercise the actual game in an isolated user directory, never a real player profile.

This verifies the collection/scenario/export chain. Its frametimes are headless
instrumentation evidence, not phone or GPU performance claims.
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]


def run(godot,output):
    output=output.resolve();output.mkdir(parents=True,exist_ok=True)
    token='TramSimP0Fixture_'+uuid.uuid4().hex
    userdir=None
    with tempfile.TemporaryDirectory(prefix='p0_smoke_',dir=str(ROOT/'.cache')) as temp:
        project=Path(temp)
        shutil.copytree(ROOT/'src',project/'src')
        shutil.copytree(ROOT/'data',project/'data',ignore=shutil.ignore_patterns('geography','__pycache__'))
        shutil.copy(ROOT/'icon.svg',project/'icon.svg')
        config=(ROOT/'project.godot').read_text().replace('[application]','[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="'+token+'"',1)
        (project/'project.godot').write_text(config)
        (project/'userdir.gd').write_text('extends SceneTree\nfunc _initialize() -> void:\n print("USER_DIR|",OS.get_user_data_dir())\n quit()\n')
        base=[godot,'--headless','--path',str(project)]
        with (output/'import.log').open('w') as log:
            subprocess.run(base+['--import'],stdout=log,stderr=subprocess.STDOUT,timeout=120,check=True)
        text=subprocess.check_output(base+['-s','userdir.gd'],text=True,stderr=subprocess.STDOUT,timeout=30)
        line=next(s for s in text.splitlines() if s.startswith('USER_DIR|'))
        userdir=Path(line.split('|',1)[1])
        if userdir.name!=token:raise ValueError('Unexpected test user directory; no profile modified')
        userdir.mkdir(parents=True,exist_ok=True);(userdir/'.p0-owner').write_text(token)
        fixture={'version':1,'settings':{'traffic':False,'custom_preference':'preserve'},'results':[{'network':'fixture','success':True}],
                 'free':{},'unknown_extension':{'keep':'all original bytes'}}
        original=json.dumps(fixture,ensure_ascii=False).encode()
        save=userdir/'save.json';save.write_bytes(original)
        request={'schema_version':1,'run_id':'isolated_smoke','request_id':'r_'+uuid.uuid4().hex,
                 'network':'res://data/free/angers.json','phase_seconds':.25,'warmup_frames':0,'seed':7,
                 'phases':['dense_driving','free_camera','night','rain','terminus'],'gpu_timing':True,'view_distance':400}
        (project/'benchmark_request.json').write_text(json.dumps(request))
        try:
            with (output/'game.log').open('w') as log:
                subprocess.run(base+['--','--perf-request=res://benchmark_request.json'],stdout=log,stderr=subprocess.STDOUT,timeout=180,check=True)
            log=(output/'game.log').read_text()
            if 'SCRIPT ERROR' in log or 'Parse Error' in log:raise ValueError('Godot reported a script error')
            if save.read_bytes()!=original:raise ValueError('Benchmark modified the isolated progression fixture')
            report=json.loads((userdir/'benchmarks/isolated_smoke.json').read_text())
            if report['status']!='completed_with_skips':raise ValueError('Unexpected scenario status')
            events={(e['phase'],e['status']) for e in report['events']}
            for phase in ['loading','dense_driving','free_camera','night','terminus']:
                if (phase,'completed') not in events:raise ValueError('Scenario phase not executed: '+phase)
            if ('rain','skipped') not in events:raise ValueError('Unimplemented rain was not reported as skipped')
            if report['metadata']['display_driver']!='headless' or report['metadata']['physical_device_verified']:
                raise ValueError('Headless execution misclassified as physical hardware')
            if any(v.get('gpu_render_ms_p95') is not None for v in report['measurements'].values()):raise ValueError('Unexpected headless GPU data')
            shutil.copy(userdir/'benchmarks/isolated_smoke.json',output/'headless.json')
            shutil.copy(userdir/'benchmarks/isolated_smoke.csv',output/'headless.csv')
            proof={'scope':'actual desktop game, headless; not Android physical','save_fixture_unchanged':True,
                   'before_sha256':hashlib.sha256(original).hexdigest(),'after_sha256':hashlib.sha256(save.read_bytes()).hexdigest(),
                   'completed_phases':sorted(p for p,state in events if state=='completed'),'rain':'skipped; unavailable','gpu':'null; unavailable'}
            (output/'progress-check.json').write_text(json.dumps(proof,indent=2)+'\n')
            return {'ok':True,**proof}
        finally:
            if userdir.name==token and (userdir/'.p0-owner').read_text()==token:shutil.rmtree(userdir)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--godot',default=os.environ.get('GODOT','godot'));p.add_argument('--output',type=Path,default=ROOT/'.cache/p0/isolated-smoke')
    args=p.parse_args();print(json.dumps(run(args.godot,args.output),indent=2))
