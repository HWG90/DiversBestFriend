"""Deterministic, allowlisted ASS loader packages from the maintained Lua core."""
from pathlib import Path
import hashlib,json,re,zipfile
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'dist/releases/r45'
VERSION='R45'
ORDER=('layout','guards','native','menu_latch','mission_blacklist','input','pointing','camera','icon_colors','duplicate','emote','expanded','selection','release','blacklist','settings','feedback','hud_plus','foliage_compat','entry')

def sources(loader):
    modules={}
    for name in ORDER:
        text=(ROOT/'native-selection-poc'/f'{name}.lua').read_text(encoding='utf-8')
        if loader=='LLL' and name=='settings':
            text=text.replace('for _,s in ipairs(specs) do','for _,s in ipairs(specs) do\n        if mod.config.preferences and mod.config.preferences[s[1]]~=nil then s[5]=mod.config.preferences[s[1]] end',1)
        exports=[]
        for line in text.splitlines():
            if line.startswith('local function '): exports.append(re.match(r'local function (\w+)',line)[1])
            elif line.startswith('local '):
                declaration=line[6:].split('=',1)[0].strip()
                exports.extend(k.strip() for k in declaration.split(',') if re.fullmatch(r'[A-Za-z_][A-Za-z_0-9]*',k.strip()))
        exports=list(dict.fromkeys(exports))
        modules['src/'+name+'.lua']=(text+'\nreturn {'+','.join(k+'='+k for k in exports)+'}\n').encode()
    return modules

def build(loader):
    assert loader in ('LLL','MDL')
    modules=sources(loader)
    files=dict(modules)
    entry='main.lua' if loader=='LLL' else 'mod.lua'
    files[entry]=(ROOT/'adapters'/entry).read_bytes()
    manifest={'id':'divers_best_friend','name':"Diver's Best Friend",'version':VERSION,'author':'Goose',
        'description':'ASS R45: HUD Plus, custom stratagem, exhausted-state and Foliage Pass-Through compatibility.'}
    manifest[loader.lower()]={'entry':entry,'modules':list(modules),'restart_only':True,'retain_until_exit':True}
    if loader=='MDL':manifest['mdl']['api']=2
    else:manifest['lll']['defaults']='config/defaults.cfg'
    defaults={}
    settings=(ROOT/'native-selection-poc/settings.lua').read_text()
    for key,value in re.findall(r"\{\s*'([^']+)'\s*,\s*'[^']+'\s*,\s*'[^']+'\s*,\s*'[^']+'\s*,\s*(true|false|-?\d+(?:\.\d+)?)",settings):defaults[key]=json.loads(value)
    files['config/defaults.cfg']=(json.dumps({'preferences':defaults},indent=2)+'\n').encode()
    files['manifest.json']=(json.dumps(manifest,indent=2)+'\n').encode()
    files['INSTALL.txt']=("Diver's Best Friend R45 - "+loader+"\n\nClose the game. Extract divers_best_friend into %LOCALAPPDATA%/"+loader+"/Helldivers2/Mods. Enable it in your loader and restart. Install ONE ASS variant; disable/remove the old archive provider. Requires Mod Bindings Menu v2+ / API 1 and Mod Options Menu through your shared-loader compatibility route. MCM is optional. Those dependencies are not bundled. ASS is restart-only: do not hot-reload or switch providers during play. Native/gameplay acceptance is established on LLL; BSL packaging and MDL lifecycle adapters have offline coverage only. See RELEASE-r45.md.\n").encode()
    for dest,source in {'RELEASE-r45.md':'docs/RELEASE-r45.md','LICENSE':'LICENSE','HUD-PLUS-COMPATIBILITY.md':'native-selection-poc/HUD-PLUS-COMPATIBILITY.md','CUSTOM-STRATAGEM-COMPATIBILITY.md':'native-selection-poc/CUSTOM-STRATAGEM-COMPATIBILITY.md'}.items():files[dest]=(ROOT/source).read_bytes()
    files['FILES-SHA256.txt']=''.join(hashlib.sha256(b).hexdigest()+'  '+n+'\n' for n,b in sorted(files.items())).encode()
    OUT.mkdir(parents=True,exist_ok=True)
    target=OUT/f'DiversBestFriend-R45-{loader}.zip'
    with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for n,b in sorted(files.items()):
            info=zipfile.ZipInfo('divers_best_friend/'+n,(1980,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o100644<<16;z.writestr(info,b)
    with zipfile.ZipFile(target) as z:
        assert z.testzip() is None
        for n,b in files.items():assert z.read('divers_best_friend/'+n)==b
    print(target)
    return target
