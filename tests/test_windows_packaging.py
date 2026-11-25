"""Packaging contract tests. Synthetic PEs are NOT trust/signature validation.
Authenticode trust and installation are tested separately on native Windows CI.
"""
import hashlib
import importlib.util
import json
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import zipfile

ROOT=Path(__file__).resolve().parents[1]
def module(name):
    spec=importlib.util.spec_from_file_location(name,ROOT/'tools/windows'/f'{name}.py')
    result=importlib.util.module_from_spec(spec);spec.loader.exec_module(result);return result
runtime=module('prepare_runtime');installer=module('build_installer')
NS={'w':installer.NS}


def synthetic_pe(machine=0xAA64,signed_table=True):
    data=bytearray(512);data[:2]=b'MZ';struct.pack_into('<I',data,60,64)
    data[64:68]=b'PE\0\0';struct.pack_into('<H',data,68,machine)
    struct.pack_into('<H',data,88,0x20b)
    if signed_table:struct.pack_into('<II',data,88+112+32,400,16)
    return bytes(data)


class WindowsPackaging(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.payload=self.root/'game';self.payload.mkdir()
        (self.payload/'TramSimFrance.exe').write_bytes(synthetic_pe())
        (self.payload/'TramSimFrance.pck').write_bytes(b'GDPC'+b'0'*32)

    def test_exported_unsigned_binary_is_rejected_as_runtime(self):
        with self.assertRaisesRegex(ValueError,'Authenticode'):runtime.pe_info(synthetic_pe(signed_table=False))

    def test_pe_architecture_is_read_from_bytes(self):
        self.assertEqual(runtime.pe_info(synthetic_pe())['machine'],0xAA64)
        self.assertEqual(runtime.pe_info(synthetic_pe(0x8664))['machine'],0x8664)

    def cached_archive(self,binary=None):
        cache=self.root/'cache';cache.mkdir()
        archive=cache/'runtime.zip'
        binary=binary or synthetic_pe()
        with zipfile.ZipFile(archive,'w') as z:z.writestr('official.exe',binary)
        config={'version':'fixture','repository':'https://github.com/godotengine/godot-builds',
                'signer':'fixture only','architectures':{'arm64':{'archive':'runtime.zip','executable':'official.exe',
                'sha512':hashlib.sha512(archive.read_bytes()).hexdigest()}}}
        source=self.root/'sources.json';source.write_text(json.dumps(config))
        for name in ['LICENSE.txt','COPYRIGHT.txt']:(cache/('Godot-fixture-'+name)).write_text('fixture')
        return cache,archive,source,binary

    def test_runtime_preserves_exact_official_binary_bytes(self):
        cache,archive,source,binary=self.cached_archive()
        with patch.object(runtime,'SOURCES',source),patch.object(runtime,'download',side_effect=AssertionError('Unexpected network')):
            result=runtime.prepare('arm64',self.payload,cache,'fixture')
        self.assertEqual((self.payload/'TramSimFrance.exe').read_bytes(),binary)
        self.assertEqual(result['sha256'],hashlib.sha256(binary).hexdigest())
        self.assertEqual(result['windows_trust_validation'],'required in CI')

    def test_modified_cached_archive_is_rejected(self):
        cache,archive,source,binary=self.cached_archive();archive.write_bytes(archive.read_bytes()+b'changed')
        with patch.object(runtime,'SOURCES',source),self.assertRaisesRegex(ValueError,'checksum'):
            runtime.prepare('arm64',self.payload,cache)

    def test_wrong_machine_is_rejected_before_distribution(self):
        cache,archive,source,binary=self.cached_archive(synthetic_pe(0x8664))
        with patch.object(runtime,'SOURCES',source),self.assertRaisesRegex(ValueError,'architecture'):
            runtime.prepare('arm64',self.payload,cache)

    def test_runtime_version_must_match_exporter(self):
        cache,archive,source,binary=self.cached_archive()
        with patch.object(runtime,'SOURCES',source),self.assertRaisesRegex(ValueError,'versions differ'):
            runtime.prepare('arm64',self.payload,cache,'different')

    def test_msi_includes_nested_payload_without_custom_actions(self):
        nested=self.payload/'native & data';nested.mkdir();(nested/'runtime.dll').write_bytes(b'fixture')
        tree=installer.generate(self.payload,'arm64','0.13.2')
        self.assertEqual(len(tree.findall('.//w:File',NS)),3)
        self.assertEqual(tree.find('.//w:Package',NS).get('Scope'),'perUser')
        self.assertEqual(tree.findall('.//w:CustomAction',NS),[])
        self.assertTrue(all(c.find('w:RegistryValue',NS).get('Root')=='HKCU' for c in tree.findall('.//w:Component',NS)))
        self.assertTrue(all(v.get('KeyPath')=='yes' for v in tree.findall('.//w:RegistryValue',NS)))

    def test_architectures_have_distinct_upgrade_and_component_guids(self):
        x64=installer.generate(self.payload,'x64','0.13.2');arm=installer.generate(self.payload,'arm64','0.13.2')
        self.assertNotEqual(x64.find('.//w:Package',NS).get('UpgradeCode'),arm.find('.//w:Package',NS).get('UpgradeCode'))
        a={c.get('Guid') for c in x64.findall('.//w:Component',NS)}
        b={c.get('Guid') for c in arm.findall('.//w:Component',NS)}
        self.assertFalse(a&b)
        again=installer.generate(self.payload,'arm64','0.13.2')
        self.assertEqual(b,{c.get('Guid') for c in again.findall('.//w:Component',NS)})

    def test_missing_pack_cannot_produce_an_installer(self):
        (self.payload/'TramSimFrance.pck').unlink()
        with self.assertRaisesRegex(ValueError,'data pack'):installer.generate(self.payload,'arm64','0.13.2')

    def test_escaping_symlink_cannot_enter_installer(self):
        outside=self.root/'outside';outside.write_bytes(b'not a payload')
        try:(self.payload/'escape').symlink_to(outside)
        except OSError:self.skipTest('Symlink creation unavailable')
        with self.assertRaisesRegex(ValueError,'Unsafe'):installer.generate(self.payload,'arm64','0.13.2')

    def test_invalid_architecture_and_msi_version_are_rejected(self):
        for arch,version in [('x86','0.13.2'),('arm64','0.13.2-preview'),('x64','999.1.1')]:
            with self.subTest(arch=arch,version=version),self.assertRaises(ValueError):installer.generate(self.payload,arch,version)
