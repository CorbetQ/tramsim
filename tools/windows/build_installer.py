#!/usr/bin/env python3
"""Generate a complete, native-architecture WiX 5 MSI payload (no custom actions)."""
import argparse
import hashlib
import re
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path

NS='http://wixtoolset.org/schemas/v4/wxs'
ET.register_namespace('',NS)
NAMESPACE=uuid.UUID('2cc426f3-d3b3-4c29-8752-78dc5ba5a00a')


def add(parent,tag,**attrs):return ET.SubElement(parent,'{'+NS+'}'+tag,attrs)
def identifier(prefix,value):return prefix+hashlib.sha256(value.encode()).hexdigest()[:24]


def generate(source,arch,version):
    if arch not in ('x64','arm64'):raise ValueError('Native x64 or arm64 architecture required')
    if not re.fullmatch(r'\d+\.\d+\.\d+',version):raise ValueError('MSI version must be major.minor.patch')
    major,minor,build=map(int,version.split('.'))
    if major>255 or minor>255 or build>65535:raise ValueError('Version exceeds MSI limits')
    source=source.resolve()
    files=sorted(p for p in source.rglob('*') if p.is_file())
    for path in files:
        if path.is_symlink() or not path.resolve().is_relative_to(source):raise ValueError('Unsafe payload path')
    names={p.relative_to(source).as_posix().lower() for p in files}
    if not {'tramsimfrance.exe','tramsimfrance.pck'}<=names:raise ValueError('Missing game executable or data pack')
    root=ET.Element('{'+NS+'}Wix')
    package=add(root,'Package',Name='Tram Sim France ('+arch.upper()+')',Manufacturer='Tram Sim France',
                Version=version,Language='1036',Scope='perUser',InstallerVersion='500',
                UpgradeCode=str(uuid.uuid5(NAMESPACE,'upgrade/'+arch)).upper())
    add(package,'MajorUpgrade',AllowSameVersionUpgrades='yes',Schedule='afterInstallInitialize',
        DowngradeErrorMessage='Une version plus récente de Tram Sim France est déjà installée.')
    add(package,'MediaTemplate',EmbedCab='yes',CompressionLevel='high')
    local=add(package,'StandardDirectory',Id='LocalAppDataFolder')
    programs=add(local,'Directory',Id='UserPrograms',Name='Programs')
    product=add(programs,'Directory',Id='ProductRoot',Name='TramSimFrance')
    install=add(product,'Directory',Id='INSTALLDIR',Name=arch)
    directories={'':install};components=[]
    for path in files:
        relative=path.relative_to(source);parent=''
        for part in relative.parts[:-1]:
            current=(parent+'/' if parent else '')+part
            if current not in directories:directories[current]=add(directories[parent],'Directory',Id=identifier('D',current),Name=part)
            parent=current
        key=relative.as_posix();component_id=identifier('C',arch+'/'+key)
        component=add(directories[parent],'Component',Id=component_id,
                      Guid=str(uuid.uuid5(NAMESPACE,arch+'/'+key)).upper(),Bitness='always64')
        add(component,'File',Id='TramSimExe' if key=='TramSimFrance.exe' else identifier('F',key),
            Source=str(path),Name=relative.name)
        # Per-user profile components need HKCU key paths (MSI ICE38/ICE57).
        add(component,'RegistryValue',Root='HKCU',Key='Software\\TramSimFrance\\'+arch+'\\Files',
            Name=identifier('file_',key),Type='integer',Value='1',KeyPath='yes')
        components.append(component_id)
    menu=add(package,'StandardDirectory',Id='ProgramMenuFolder')
    appmenu=add(menu,'Directory',Id='AppMenu',Name='Tram Sim France')
    shortcuts=add(appmenu,'Component',Id='UserShortcuts',Guid=str(uuid.uuid5(NAMESPACE,arch+'/shortcuts')).upper(),Bitness='always64')
    add(shortcuts,'Shortcut',Id='StartShortcut',Name='Tram Sim France ('+arch.upper()+')',
        Target='[INSTALLDIR]TramSimFrance.exe',WorkingDirectory='INSTALLDIR')
    add(shortcuts,'RemoveFolder',Id='RemoveAppMenu',On='uninstall')
    for folder in [programs,product,*directories.values()]:
        add(shortcuts,'RemoveFolder',Id='Remove_'+folder.get('Id'),Directory=folder.get('Id'),On='uninstall')
    add(shortcuts,'RegistryValue',Root='HKCU',Key='Software\\TramSimFrance\\'+arch,Name='installed',Type='integer',Value='1',KeyPath='yes')
    components.append('UserShortcuts')
    feature=add(package,'Feature',Id='Complete',Title='Tram Sim France',Level='1')
    for component in components:add(feature,'ComponentRef',Id=component)
    ET.indent(root,space='  ')
    return ET.ElementTree(root)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',type=Path,required=True)
    p.add_argument('--arch',choices=('x64','arm64'),required=True);p.add_argument('--version',required=True)
    p.add_argument('--output',type=Path,required=True);args=p.parse_args();args.output.parent.mkdir(parents=True,exist_ok=True)
    generate(args.source,args.arch,args.version).write(args.output,encoding='utf-8',xml_declaration=True)
