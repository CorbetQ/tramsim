#!/usr/bin/env python3
"""Local ADB benchmark capture. No root, subscription or cloud dependency.

Only a debuggable app with run-as access can receive a one-shot request. A restart
is explicit; finish normal gameplay before running capture. Progress is backed up
locally and compared after the run, never silently restored or deleted.
"""
import argparse
import hashlib
import json
import math
import re
import subprocess
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path


def identifier(value):
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]{0,79}', value):
        raise ValueError('Use a simple unique identifier with letters/numbers/underscores')
    return value


def package_name(value):
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+', value):
        raise ValueError('Invalid Android package/activity')
    return value


def fingerprint(data):
    return hashlib.sha256(data).hexdigest() if data is not None else None


class Adb:
    def __init__(self, binary='adb', serial=None, runner=subprocess.run):
        if serial is not None and not re.fullmatch(r'[A-Za-z0-9_.:-]+',serial):
            raise ValueError('Invalid device serial')
        self.base=[binary]+(['-s',serial] if serial else [])
        self.runner=runner

    def run(self,*args,data=None,optional=False):
        result=self.runner(self.base+list(args),input=data,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30,check=False)
        if result.returncode and not optional:
            raise RuntimeError(result.stderr.decode(errors='replace').strip() or 'ADB command failed')
        return result

    def read_private(self,package,relative,missing_ok=False):
        package_name(package)
        if not re.fullmatch(r'files/(?:[A-Za-z0-9_./-]+)',relative) or '..' in relative:
            raise ValueError('Invalid app-local path')
        result=self.run('exec-out','run-as',package,'cat',relative,optional=True)
        if result.returncode:
            if missing_ok and b'No such file' in result.stderr+result.stdout:return None
            raise RuntimeError('run-as read failed (debuggable APK required): '+result.stderr.decode(errors='replace'))
        return result.stdout

    def request(self,package,request):
        package_name(package)
        self.run('shell','run-as',package,'mkdir','-p','files')
        # Only the validated package is interpolated. JSON is stdin, never shell text.
        self.run('shell',f"run-as {package} sh -c 'cat > files/benchmark_request.json'",data=json.dumps(request).encode())

    def text(self,*args):
        result=self.run(*args,optional=True)
        return result.stdout.decode(errors='replace').strip() if result.returncode==0 else None


def parse_battery(text):
    text=text or ''
    def value(key,scale=1):
        match=re.search(r'^\s*'+key+r':\s*(-?\d+)\s*$',text,re.M)
        return int(match[1])/scale if match else None
    return {'battery_temperature_c':value('temperature',10),'battery_level_percent':value('level'),
            'scope':'battery sensor, not SoC temperature or app energy'}


def device_metadata(adb,serial):
    props={key:adb.text('shell','getprop',key) for key in ['ro.product.model','ro.build.version.release','ro.build.fingerprint','ro.kernel.qemu','ro.product.cpu.abi']}
    qemu=props['ro.kernel.qemu']
    # Empty or 0 is common on physical Android. A connected device remains an
    # observation, not proof of an OEM performance tier.
    emulator=qemu=='1' or bool(serial and serial.startswith('emulator-'))
    return {'serial':serial,'properties':props,'is_emulator':emulator,
            'physical_hardware_evidence':not emulator and bool(props['ro.build.fingerprint']),
            'low_power_setting':adb.text('shell','settings','get','global','low_power')}


def sensors(adb,package):
    battery=parse_battery(adb.text('shell','dumpsys','battery'))
    mem=adb.text('shell','dumpsys','meminfo',package) or ''
    for label,key in [('TOTAL PSS','pss_kib'),('TOTAL RSS','rss_kib')]:
        match=re.search(label+r':\s*(\d+)',mem)
        battery[key]=int(match[1]) if match else None
    battery['thermal_service_raw']=adb.text('shell','dumpsys','thermalservice')
    for name in ['current_now','voltage_now']:
        raw=adb.text('shell','cat','/sys/class/power_supply/battery/'+name)
        battery[name]=int(raw) if raw and re.fullmatch(r'-?\d+',raw) else None
    battery['power_scope']='raw whole-device battery current/voltage; not app watts, no energy total inferred'
    return battery


def capture(args):
    if not args.restart:raise ValueError('capture requires --restart; finish the current game session first')
    identifier(args.run_id);package_name(args.package);package_name(args.activity)
    if not args.network.startswith(('res://data/free/','res://data/networks/')) or not args.network.endswith('.json') or '..' in args.network:raise ValueError('Network must be embedded data')
    for value,minimum,maximum in [(args.phase_seconds,.1,120),(args.warmup_frames,0,600),(args.view_distance,100,1200),(args.frame_budget_ms,.1,10000),(args.timeout,1,1800)]:
        if not math.isfinite(value) or not minimum<=value<=maximum:raise ValueError('Benchmark configuration out of range')
    out=args.output.resolve()
    if out.exists():raise ValueError('Output directory already exists; preserve the old baseline')
    out.mkdir(parents=True)
    adb=Adb(args.adb,args.serial)
    if adb.text('get-state')!='device':raise ValueError('No authorized connected device')
    before=adb.read_private(args.package,'files/save.json',missing_ok=True)
    if before is not None:(out/'save-before.private.json').write_bytes(before)
    device=device_metadata(adb,args.serial)
    request={'schema_version':1,'run_id':args.run_id,'request_id':'r_'+uuid.uuid4().hex,'network':args.network,
             'phase_seconds':args.phase_seconds,'warmup_frames':args.warmup_frames,'seed':args.seed,
             'phases':['dense_driving','free_camera','night','rain','terminus'],'gpu_timing':args.gpu_timing,
             'power_mode':args.power_mode,'view_distance':args.view_distance,'budgets':{'frametime_p95_ms':args.frame_budget_ms}}
    adb.run('shell','am','force-stop',args.package)
    adb.request(args.package,request)
    (out/'request.json').write_text(json.dumps(request,indent=2)+'\n')
    adb.run('shell','am','start','-W','-n',args.package+'/'+args.activity)
    start=time.monotonic();last_sensor=-10;external=[];raw=None
    while time.monotonic()-start<args.timeout:
        raw=adb.read_private(args.package,'files/benchmarks/'+args.run_id+'.json',missing_ok=True)
        if raw is not None:
            app=json.loads(raw)
            if app.get('request_id')!=request['request_id']:raise ValueError('Stale report: run_id already belongs to another request')
            break
        if time.monotonic()-start-last_sensor>=2:
            external.append(dict(seconds=time.monotonic()-start,**sensors(adb,args.package)));last_sensor=time.monotonic()-start
        time.sleep(.5)
    else:raise TimeoutError('No completed report before timeout; app/progress files are preserved')
    after=adb.read_private(args.package,'files/save.json',missing_ok=True)
    unchanged=fingerprint(before)==fingerprint(after)
    bundle={'schema_version':1,'kind':'android_performance_capture','collected_at':datetime.now(timezone.utc).isoformat(),
            'request':request,'app':app,'device':device,'external_samples':external,'progress_unchanged':unchanged,
            'external_sampling_note':'ADB queries every ~2s add overhead; use the same protocol for A/B comparisons'}
    (out/'capture.json').write_text(json.dumps(bundle,indent=2,allow_nan=False)+'\n')
    (out/'samples.csv').write_bytes(adb.read_private(args.package,'files/benchmarks/'+args.run_id+'.csv'))
    if not unchanged:raise ValueError('Progress changed during benchmark; original retained locally in save-before.private.json')
    return {'ok':True,'status':app['status'],'report':str(out/'capture.json'),'physical_hardware_evidence':device['physical_hardware_evidence']}


def compare(first,second):
    for value in (first,second):
        if value.get('kind')!='android_performance_capture' or value.get('schema_version')!=1:
            raise ValueError('Unsupported capture schema')
        if value['app']['status'] not in ('completed','completed_with_skips') or not value.get('progress_unchanged'):
            raise ValueError('Incomplete/interrupted capture or altered progress')
    a,b=first['app'],second['app']
    for key in ['serial','properties','low_power_setting']:
        if first['device'].get(key)!=second['device'].get(key):raise ValueError('Device/OS/power configuration differs')
    for key in ['network','phase_seconds','warmup_frames','seed','phases','gpu_timing','view_distance','power_mode']:
        if a['configuration'].get(key)!=b['configuration'].get(key):raise ValueError('Benchmark scenario/configuration differs')
    for key in ['rendering_method','display_driver','network_sha256']:
        if a['metadata'].get(key)!=b['metadata'].get(key):raise ValueError('Renderer/workload differs')
    if set(a['measurements'])!=set(b['measurements']):raise ValueError('Measured phase coverage differs')
    differences={}
    for phase in a['measurements']:
        old=a['measurements'][phase]['frametime_ms']['p95'];new=b['measurements'][phase]['frametime_ms']['p95']
        if old is None or new is None:raise ValueError('Insufficient samples in a measured phase')
        differences[phase]={'before_ms':old,'after_ms':new,'delta_percent':(new-old)/old*100 if old else None}
    verified=all(v['device'].get('physical_hardware_evidence') and not v['device'].get('is_emulator') and v['app']['metadata'].get('sample_source')=='runtime_monitors' and v['app']['metadata'].get('os')=='Android' for v in (first,second))
    return {'schema_version':1,'scope':'physical_android' if verified else 'fixture_or_unverified_device','frametime_p95':differences,
            'limitations':['Comparison is not proof of perceptual quality or exact scene equivalence; inspect source assets and trajectories.']}


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--adb',default='adb')
    sub=p.add_subparsers(dest='command',required=True)
    sub.add_parser('devices')
    c=sub.add_parser('capture');c.add_argument('--serial',required=True);c.add_argument('--package',default='fr.tramsim.game');c.add_argument('--activity',default='org.godotengine.godot.GodotApp')
    c.add_argument('--run-id',required=True);c.add_argument('--output',type=Path,required=True);c.add_argument('--restart',action='store_true')
    c.add_argument('--network',default='res://data/free/angers.json');c.add_argument('--phase-seconds',type=float,default=8);c.add_argument('--warmup-frames',type=int,default=10)
    c.add_argument('--seed',type=int,default=7);c.add_argument('--gpu-timing',action='store_true');c.add_argument('--power-mode',default='not_reported');c.add_argument('--view-distance',type=float,default=400)
    c.add_argument('--frame-budget-ms',type=float,default=33.3333);c.add_argument('--timeout',type=float,default=300)
    c=sub.add_parser('compare');c.add_argument('baseline',type=Path);c.add_argument('candidate',type=Path);c.add_argument('--output',type=Path)
    args=p.parse_args()
    if args.command=='devices':result={'devices':Adb(args.adb).text('devices','-l')}
    elif args.command=='capture':result=capture(args)
    else:
        result=compare(json.loads(args.baseline.read_text()),json.loads(args.candidate.read_text()))
        if args.output:args.output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2));return 0


if __name__=='__main__':
    import sys
    try:raise SystemExit(main())
    except (ValueError,OSError,RuntimeError,TimeoutError,subprocess.SubprocessError) as error:
        print(json.dumps({'ok':False,'error':str(error)}),file=sys.stderr);raise SystemExit(2)
