import importlib.util
import json
from pathlib import Path
import struct
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('poc_build', ROOT / 'build_poc.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class PackageTest(unittest.TestCase):
    def test_distinct_addon_and_current_source(self):
        with zipfile.ZipFile(builder.OUTPUT) as package:
            manifest = json.loads(package.read('manifest.json'))
            self.assertNotEqual(manifest['Guid'], '7f3a9c2e-6b14-4d58-8e21-0c5b9a4d71f6')
            blob = package.read('Addon/' + builder.ARCHIVE)
            self.assertEqual(struct.unpack_from('<III', blob), (0xF0000011, 1, 1))
            record = struct.unpack_from('<7Q6I', blob, 104)
            payload = blob[record[2]:record[2] + record[7]]
            size, version = struct.unpack_from('<II', payload)
            self.assertEqual(version, 2)
            self.assertEqual(size, len(payload) - 8)
            body = payload[8:]
            self.assertEqual(body, (ROOT / 'NativeStratagemRadial.lua').read_bytes())
            self.assertTrue(body.startswith(('-- HD2-Addon: ' + builder.RESOURCE + '\n').encode()))
            for filename in ('layout.lua', 'guards.lua', 'native.lua', 'input.lua', 'pointing.lua', 'camera.lua', 'icon_colors.lua', 'duplicate.lua', 'emote.lua', 'expanded.lua', 'selection.lua', 'blacklist.lua', 'entry.lua'):
                self.assertIn((ROOT / filename).read_text().encode(), body)
            self.assertEqual(manifest['Guid'], builder.GUID)
            self.assertEqual(manifest['Name'], builder.DISPLAY_NAME)
            self.assertEqual(manifest['Version'], 1)
            self.assertEqual(package.read('INSTALL.txt'), (ROOT / 'INSTALL.txt').read_bytes())
            self.assertEqual(package.read('docs/BLACKLIST.md'), (ROOT.parent / 'docs/BLACKLIST.md').read_bytes())

    def test_deterministic_build(self):
        first = builder.OUTPUT.read_bytes()
        builder.build()
        self.assertEqual(builder.OUTPUT.read_bytes(), first)


if __name__ == '__main__':
    unittest.main()
