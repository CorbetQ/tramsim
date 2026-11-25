#!/usr/bin/env python3
"""Bundle the byte-identical, signed official Godot runtime beside an exported PCK.

No resource editing, PCK embedding, self-signing or security-policy changes.
Windows CI must additionally verify Authenticode trust before publishing.
"""
import argparse
import hashlib
import json
import shutil
import struct
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCES = Path(__file__).with_name('runtime_sources.json')
MACHINES = {'x64': 0x8664, 'arm64': 0xAA64}


def pe_info(data):
    if len(data)<256 or data[:2]!=b'MZ':raise ValueError('Not a PE executable')
    pe=struct.unpack_from('<I',data,60)[0]
    if data[pe:pe+4]!=b'PE\0\0':raise ValueError('Invalid PE header')
    if struct.unpack_from('<H',data,pe+24)[0]!=0x20b:raise ValueError('PE32+ required')
    offset,size=struct.unpack_from('<II',data,pe+24+112+32)
    if size<8 or offset+size>len(data):raise ValueError('Missing/truncated Authenticode table')
    return {'machine':struct.unpack_from('<H',data,pe+4)[0],
            'certificate_bytes':size,'sha256':hashlib.sha256(data).hexdigest()}


def download(url,path,limit):
    partial=path.with_suffix(path.suffix+'.partial')
    try:
        with urllib.request.urlopen(url,timeout=120) as response,partial.open('wb') as out:
            size=0
            while block:=response.read(1024*1024):
                size+=len(block)
                if size>limit:raise ValueError('Download size limit exceeded')
                out.write(block)
        partial.replace(path)
    finally:partial.unlink(missing_ok=True)


def prepare(arch,destination,cache,version=None):
    config=json.loads(SOURCES.read_text());row=config['architectures'][arch]
    if version and version!=config['version']:raise ValueError('Runtime/exporter versions differ')
    destination.mkdir(parents=True,exist_ok=True);cache.mkdir(parents=True,exist_ok=True)
    pck=destination/'TramSimFrance.pck'
    if not pck.is_file() or pck.stat().st_size<16:raise ValueError('Exported game PCK missing')
    archive=cache/row['archive']
    url=f"{config['repository']}/releases/download/{config['version']}-stable/{row['archive']}"
    if not archive.exists():download(url,archive,256*1024*1024)
    if hashlib.sha512(archive.read_bytes()).hexdigest()!=row['sha512']:
        raise ValueError('Official runtime archive checksum mismatch; cache preserved for inspection')
    with zipfile.ZipFile(archive) as zipped:
        member=zipped.getinfo(row['executable'])
        if member.file_size>300*1024*1024:raise ValueError('Runtime size limit exceeded')
        binary=zipped.read(member)
    info=pe_info(binary)
    if info['machine']!=MACHINES[arch]:raise ValueError('Wrong runtime architecture')
    # Rename only. Do not alter the signed bytes or append the game data.
    (destination/'TramSimFrance.exe').write_bytes(binary)
    for name in ['CREDITS.md','README.md']:
        shutil.copyfile(ROOT/name,destination/name)
    shutil.copyfile(ROOT/'docs/windows/LISEZMOI.md',destination/'WINDOWS-LISEZMOI.md')
    for name in ['LICENSE.txt','COPYRIGHT.txt']:
        target=cache/('Godot-'+config['version']+'-'+name)
        if not target.exists():
            download(f"https://raw.githubusercontent.com/godotengine/godot/{config['version']}-stable/{name}",target,2*1024*1024)
        shutil.copyfile(target,destination/('GODOT-'+name))
    info.update({'architecture':arch,'godot_version':config['version'],'origin':url,
                 'archive_sha512':row['sha512'],'publisher':config['signer'],
                 'signature_table_present':True,'windows_trust_validation':'required in CI'})
    (destination/'RUNTIME-PROVENANCE.json').write_text(json.dumps(info,indent=2)+'\n')
    return info


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--arch',choices=MACHINES,required=True)
    p.add_argument('--destination',type=Path,required=True);p.add_argument('--cache',type=Path,required=True)
    p.add_argument('--godot-version');args=p.parse_args()
    print(json.dumps(prepare(args.arch,args.destination,args.cache,args.godot_version),indent=2))
