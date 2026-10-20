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
            for filename in ('layout.lua', 'guards.lua', 'native.lua', 'input.lua', 'pointing.lua', 'camera.lua', 'icon_colors.lua', 'duplicate.lua', 'emote.lua', 'expanded.lua', 'selection.lua', 'blacklist.lua', 'hud_plus.lua', 'foliage_compat.lua', 'entry.lua'):
                self.assertIn((ROOT / filename).read_text().encode(), body)
            self.assertEqual(manifest['Guid'], builder.GUID)
            self.assertEqual(manifest['Name'], builder.DISPLAY_NAME)
            self.assertEqual(manifest['Version'], 1)
            self.assertIn(('revision='+str(builder.REVISION)+',').encode(), body)
            self.assertIn(b'@DiversBestFriend/',body)
            self.assertIn(b'setfenv(chunk,scope)',body)
            self.assertNotIn(b'local api=', package.read('Source/bsl_startup.lua'))
            self.assertIn(b'local api=',package.read('Source/src/entry.lua'))
            self.assertIn('HUD Plus 0.2.8 / 0.2.9', manifest['Description'])
            self.assertIn('Custom Stratagem Compendium 0.4.1', manifest['Description'])
            self.assertEqual(package.read('CUSTOM-STRATAGEM-COMPATIBILITY.md'), (ROOT / 'CUSTOM-STRATAGEM-COMPATIBILITY.md').read_bytes())
            self.assertEqual(package.read('HUD-PLUS-COMPATIBILITY.md'), (ROOT / 'HUD-PLUS-COMPATIBILITY.md').read_bytes())
            self.assertEqual(package.read('INSTALL.txt'), (ROOT / 'INSTALL.txt').read_bytes())
            self.assertEqual(package.read('docs/BLACKLIST.md'), (ROOT.parent / 'docs/BLACKLIST.md').read_bytes())

    def test_every_embedded_module_compiles_independently(self):
        import subprocess,sys,tempfile
        with zipfile.ZipFile(builder.OUTPUT) as package:
            names=[n for n in package.namelist() if n.startswith('Source/src/') and n.endswith('.lua')]
            self.assertEqual(len(names),23)
            fixture='\n'.join('assert(loadstring('+builder.lua_literal(package.read(n).decode())+','+json.dumps('@'+n)+'))' for n in names)
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'syntax.lua';path.write_text(fixture)
            result=subprocess.run([sys.executable,str(ROOT.parent/'run_lua.py'),str(path)],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_bootstrap_module_scope_and_cache(self):
        import subprocess,sys,tempfile
        modules={'src/a.lua':b'local hidden=7; return {shared=hidden}',
                 'src/b.lua':b'assert(shared==7); assert(hidden==nil); calls=(calls or 0)+1; return {seen=calls}',
                 'src/entry.lua':b'assert(seen==1); rawset(_G,"DiversBestFriend",{}); update=function()return shared end; return {}'}
        boot=builder.bootstrap(modules,['src/a.lua','src/b.lua','src/b.lua','src/entry.lua'])
        fixture='local before=update;\n'+boot+'\nassert(update()==7);assert(shared==nil and calls==nil);local installed=update;\n'+boot+'\nassert(update==installed)'
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'bsl.lua';path.write_text(fixture)
            result=subprocess.run([sys.executable,str(ROOT.parent/'run_lua.py'),str(path)],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_deterministic_build(self):
        first = builder.OUTPUT.read_bytes()
        builder.build()
        self.assertEqual(builder.OUTPUT.read_bytes(), first)


if __name__ == '__main__':
    unittest.main()
