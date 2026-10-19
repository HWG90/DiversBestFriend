"""Validate every release asset and both loose-loader startup contracts."""
from pathlib import Path
import hashlib,json,runpy,struct,sys,zipfile
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from release_package import OUT,sources,ORDER

def quote(s):
    assert ']====]' not in s
    return '[====['+s+']====]'

def main():
    runner=runpy.run_path(str(ROOT/'run_lua.py'))
    assets={}
    for loader in ('BSL','MDL','LLL'):
        path=OUT/f'DiversBestFriend-R45-{loader}.zip'
        with zipfile.ZipFile(path) as z:
            assert z.testzip() is None
            assets[loader]={n:z.read(n) for n in z.namelist()}
            assert all('..' not in Path(n).parts and not Path(n).is_absolute() for n in z.namelist())
    for loader in ('MDL','LLL'):
        files={n.removeprefix('divers_best_friend/'):b for n,b in assets[loader].items()}
        manifest=json.loads(files['manifest.json'])
        assert manifest['version']=='R45' and manifest['id']=='divers_best_friend'
        assert manifest[loader.lower()]['restart_only'] is True
        assert set(manifest[loader.lower()]['modules'])==set(sources(loader))
        for n,b in sources(loader).items():assert files[n]==b
        for n,b in files.items():
            if n.endswith('.lua'):runner['run'](('assert(loadstring('+quote(b.decode())+'))').encode(),'syntax '+loader+'/'+n)
        fixture=(ROOT/'tests/loader_adapters.lua').read_text()
        payload='local LOADER='+quote(loader)+'\nlocal FILES={' + ','.join('[ '+quote(n)+' ]='+quote(b.decode()) for n,b in files.items() if n.endswith('.lua'))+'}\n'+fixture
        runner['run'](payload.encode(),loader+' startup contract')
    bsl=assets['BSL'];blob=bsl['Addon/9ba626afa44a3aa3.patch_0']
    record=struct.unpack_from('<7Q6I',blob,104);payload=blob[record[2]:record[2]+record[7]]
    assert payload[8:]==(ROOT/'native-selection-poc/NativeStratagemRadial.lua').read_bytes()
    for loader in ('MDL','LLL'):
        for name in ORDER:
            if name=='settings' and loader=='LLL':continue
            assert assets[loader]['divers_best_friend/src/'+name+'.lua'].startswith((ROOT/'native-selection-poc'/f'{name}.lua').read_text().encode())
    for line in (OUT/'SHA256SUMS.txt').read_text().splitlines():
        digest,name=line.split('  ');assert hashlib.sha256((OUT/name).read_bytes()).hexdigest()==digest
    print('R45: all three asset checksums, exact core/module payloads, Lua syntax and MDL/LLL startup/duplicate/restart-only contracts passed')
if __name__=='__main__':main()
