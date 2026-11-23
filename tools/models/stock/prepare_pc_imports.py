#!/usr/bin/env python3
"""Explicit PC validation setup; never used by Android export or asset production.

Godot retains old imported_formats in .import files, even when an override disables
ETC2. Remove that stale cache declaration to avoid a lengthy CPU ETC2 rebuild in CI.
Only import metadata changes; source images and project.godot remain untouched.
"""
import re
from audit_stock import ROOT


def main():
    override=ROOT/'override.cfg'
    if override.exists():
        if 'textures/vram_compression/import_etc2_astc=false' not in override.read_text():
            raise SystemExit('Existing override.cfg preserved: configure PC imports explicitly first.')
    else:
        override.write_text('[rendering]\ntextures/vram_compression/import_etc2_astc=false\n')
    count=0
    for path in ROOT.rglob('*.import'):
        if '.godot' in path.parts:continue
        text=path.read_text()
        if 'importer="texture"' not in text:continue
        updated=re.sub(r'^path\.etc2=.*\n','',text,flags=re.M)
        updated=updated.replace(', "etc2_astc"','')
        updated=re.sub(r', "res://[^"\n]+\.etc2\.ctex"','',updated)
        if updated!=text:path.write_text(updated);count+=1
    print(f'PC validation imports prepared: {count} cache declarations; Android project settings preserved.')


if __name__=='__main__':main()
