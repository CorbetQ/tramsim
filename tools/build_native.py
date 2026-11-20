#!/usr/bin/env python3
"""Build/install the optional Rust kernel for this platform; never download toolchains."""
import argparse, os, platform, shutil, subprocess, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--cargo',default='cargo');p.add_argument('--release',action='store_true')
    p.add_argument('--target',choices=['aarch64-linux-android','x86_64-pc-windows-gnu','aarch64-pc-windows-msvc'])
    p.add_argument('--disable',action='store_true');args=p.parse_args()
    dest=ROOT/'addons/tramsim_native';descriptor=dest/'tramsim.gdextension'
    if args.disable:
        descriptor.unlink(missing_ok=True);return
    names={'linux':('linux.x86_64','libtramsim_native.so'),'win32':('windows.x86_64','tramsim_native.dll'),'darwin':('macos','libtramsim_native.dylib')}
    if sys.platform not in names:raise SystemExit('Build target must be configured explicitly for this platform')
    key,name=names[sys.platform]
    if sys.platform=='darwin':key+='.'+('arm64' if platform.machine()=='arm64' else 'x86_64')
    targets={'aarch64-linux-android':('android.arm64','libtramsim_native.so'),'x86_64-pc-windows-gnu':('windows.x86_64','tramsim_native.dll'),'aarch64-pc-windows-msvc':('windows.arm64','tramsim_native.dll')}
    if args.target:key,name=targets[args.target]
    cmd=[args.cargo,'build','--manifest-path',str(ROOT/'native/Cargo.toml'),'--locked','-p','tramsim-native']
    if args.release:cmd.append('--release')
    if args.target:cmd+=['--target',args.target]
    subprocess.run(cmd,check=True)
    profile='release' if args.release else 'debug'
    target_dir=Path(os.environ.get('CARGO_TARGET_DIR',ROOT/'native/target'))
    artifact=target_dir/(args.target or '')/profile/name
    # Atomic replacement: never truncate a library mapped by a running Godot process.
    libdir=dest/key;libdir.mkdir(parents=True,exist_ok=True)
    staged=libdir/(name+'.tmp');shutil.copy(artifact,staged);os.replace(staged,libdir/name)
    libraries={}
    if descriptor.exists():
        section=descriptor.read_text().partition('[libraries]')[2]
        for line in section.splitlines():
            if ' = ' in line:
                feature,path=line.split(' = ',1);libraries[feature]=path
    libraries[key]='"res://addons/tramsim_native/'+key+'/'+name+'"'
    descriptor.write_text('[configuration]\nentry_symbol = "gdext_rust_init"\ncompatibility_minimum = "4.3"\nreloadable = false\n\n[libraries]\n'+'\n'.join(k+' = '+v for k,v in sorted(libraries.items()))+'\n')
    print('Installed native kernel:',libdir/name)
if __name__=='__main__':main()
