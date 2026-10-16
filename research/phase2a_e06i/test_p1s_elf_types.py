"""Synthetic offline DATA-only ELF regression; no network or target execution."""
import io
import json
from pathlib import Path
import runpy
import struct
import tarfile
import unittest

BASE = Path(__file__).resolve().parent
MODULE = runpy.run_path(str(BASE / 'p1s_static_inventory.py'))
GLOBALS = MODULE['elf_metadata'].__globals__
SPEC = json.loads((BASE / 'p1s_input_contract.json').read_text())
GLOBALS['SPEC'] = SPEC


def rel():
    raw = bytearray(320)
    raw[:7] = b'\x7fELF\x02\x01\x01'
    struct.pack_into('<HHI', raw, 16, 1, 62, 1)
    struct.pack_into('<Q', raw, 40, 64)
    struct.pack_into('<HHHHHH', raw, 52, 64, 0, 0, 64, 3, 2)
    struct.pack_into('<IIQQQQIIQQ', raw, 128, 1, 1, 0, 0, 256, 8, 0, 0, 8, 0)
    struct.pack_into('<IIQQQQIIQQ', raw, 192, 7, 3, 0, 0, 264, 17, 0, 0, 1, 0)
    raw[264:281] = b'\0.text\0.shstrtab\0\0'
    return raw


def changed(raw, offset, fmt, value):
    out = bytearray(raw)
    struct.pack_into(fmt, out, offset, value)
    return out


class ElfTypes(unittest.TestCase):
    def test_rel_data_and_tar(self):
        raw = rel()
        out = MODULE['elf_metadata'](raw)
        self.assertEqual(out['type'], 'ET_REL')
        self.assertIsNone(out['needed'])
        self.assertEqual(out['section_count'], 3)
        archive = io.BytesIO()
        with tarfile.open(fileobj=archive, mode='w') as tar:
            info = tarfile.TarInfo('safe/debug.o')
            info.size = len(raw)
            tar.addfile(info, io.BytesIO(raw))
        archive.seek(0)
        vfs = {}
        MODULE['scan_tar'](archive, MODULE['Budget'](SPEC), vfs, {})
        self.assertEqual(vfs['safe/debug.o']['elf']['type'], 'ET_REL')

    def test_rel_boundaries(self):
        raw = rel()
        # NOBITS occupies memory, not file bytes; no payload read.
        raw = changed(raw, 132, '<I', 8)
        raw = changed(raw, 160, '<Q', SPEC['entry_limit'])
        self.assertEqual(MODULE['elf_metadata'](raw)['type'], 'ET_REL')
        raw = rel()
        struct.pack_into('<HH', raw, 60, 1, 0)
        self.assertEqual(MODULE['elf_metadata'](raw)['section_count'], 1)

    def test_section_count_and_name_bounds(self):
        raw = bytearray(64 + 1024*64)
        raw[:64] = rel()[:64]
        struct.pack_into('<HH', raw, 60, 1024, 0)
        for i in range(1,1024):
            struct.pack_into('<IIQQQQIIQQ',raw,64+i*64,0,1,0,0,len(raw),0,0,0,1,0)
        self.assertEqual(MODULE['elf_metadata'](raw)['section_count'],1024)
        raw = rel()
        raw.extend(bytes(4096))
        struct.pack_into('<Q',raw,224,4098)
        struct.pack_into('<I',raw,128,1)
        struct.pack_into('<I',raw,192,1)
        raw[264:4362] = b'\0' + b'a'*4096 + b'\0'
        self.assertEqual(MODULE['elf_metadata'](raw)['type'],'ET_REL')
        raw[4361:4362] = b'a'
        with self.assertRaises(ValueError):
            MODULE['elf_metadata'](raw)

    def test_malformed_and_unknown(self):
        mutations = [(16,'<H',0),(16,'<H',4),(16,'<H',65535),
                     (24,'<Q',1),(32,'<Q',64),(54,'<H',56),(56,'<H',1),
                     (40,'<Q',2**64-1),(40,'<Q',0),(58,'<H',0),
                     (60,'<H',0),(60,'<H',1025),(62,'<H',3),
                     (64,'<I',1),(132,'<I',0),(132,'<I',0x70000000),
                     (152,'<Q',319),(160,'<Q',2**64-1),(148,'<I',1),
                     (168,'<I',3),(176,'<Q',3),(184,'<Q',3),
                     (128,'<I',17),(196,'<I',1),(224,'<Q',0)]
        for offset, fmt, value in mutations:
            with self.subTest(offset=offset, value=value):
                with self.assertRaises(ValueError):
                    MODULE['elf_metadata'](changed(rel(),offset,fmt,value))
        for raw in (rel()[:63],rel()[:250],changed(rel(),280,'<B',65)):
            with self.assertRaises(ValueError):
                MODULE['elf_metadata'](raw)

    def test_exec_dyn_keep_program_header_gate(self):
        for kind in (2,3):
            raw = changed(rel(),16,'<H',kind)
            with self.assertRaisesRegex(ValueError,'ELF_PHDR'):
                MODULE['elf_metadata'](raw)


if __name__ == '__main__':
    unittest.main()
