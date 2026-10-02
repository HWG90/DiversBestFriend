local function source(n) local f=assert(io.open('native-selection-poc/'..n));local s=f:read('*a');f:close();return s end
local configure,signature,filter,visibility=assert(loadstring(source('blacklist.lua')..
    '\nreturn stratagem_blacklist,blacklist_signature,blacklist_snapshot,blacklist_list_visibility'))()
assert(signature(configure({}))=='','default must preserve every stratagem')
local excluded=configure({hide_sos=true,blacklist_kind_1=33,blacklist_kind_2=145,
    blacklist_kind_3=0,blacklist_kind_4=150,blacklist_kind_5=-1,blacklist_kind_6='124',
    blacklist_kind_7=0/0,blacklist_kind_8=3.5})
assert(signature(excluded)=='33,145','stable ID validation and duplicate normalization')
local sos={address=10,kind=145,entry=0,list_y=0}
local supply={address=20,kind=33,entry=4,list_y=-68}
local reinforce={address=30,kind=124,entry=7,list_y=-136}
local native={identity=1,open=true,rows={sos,supply,reinforce},center={12,34},list=99}
local f=filter(native,excluded)
assert(f~=native and f.rows~=native.rows and #native.rows==3 and native.rows[1]==sos)
assert(#f.rows==1 and f.rows[1]==reinforce and #f.excluded_rows==2 and f.center==native.center and f.list==99)
-- Reordered loadout entries do not change the identity of an exclusion.
sos.entry=8;sos.address=70
native.rows={reinforce,sos};f=filter(native,excluded)
assert(#f.rows==1 and f.rows[1]==reinforce)
assert(#filter(native,{[124]=true,[145]=true}).rows==0)
assert(filter(nil,excluded)==nil)
native.open=false;assert(filter(native,excluded)==native);native.open=true

local scale={[10]={1,1},[70]={0.9,0.8},[20]={1,1}}
local valid=true;local writes=0
local controller=visibility({valid=function(id) return valid and id==1 end,
    get=function(address,property) return property=='scale' and scale[address] or {0,address==70 and 0 or -68} end,
    set=function(address,property,v) if property=='scale' then scale[address]={v[1],v[2]} end;writes=writes+1 end})
controller.step(filter(native,excluded));assert(scale[70][1]==0 and scale[70][2]==0)
controller.step(filter(native,{}));assert(scale[70][1]==0.9 and scale[70][2]==0.8)
controller.step(filter(native,excluded));scale[70]={0.7,0.7};controller.restore()
assert(scale[70][1]==0.7,'restore must preserve newer native/user changes')
controller.step(filter(native,excluded));valid=false;local before=writes;controller.restore()
assert(writes==before,'never restore an invalid HUD owner')
valid=true;scale[70]={1,1};controller.step(filter(native,excluded));controller.step(nil)
assert(scale[70][1]==1,'closing/disabling/switching restores the vanilla row')

-- Persistence belongs to Mod Options Menu, keyed by stable IDs, not loadout slots.
local settings=assert(loadstring(source('settings.lua')..'\nreturn canary_settings'))()
local applied={['native_stratagem_radial.hide_sos']=true,['native_stratagem_radial.blacklist_kind_1']=33}
local ids={}
local menu={get=function(id) return applied[id] end,register_option=function(id,spec)
    ids[id]=spec;return true end}
local v=settings(menu,{registered={}},{})
assert(signature(configure(v))=='33,145')
v=settings(menu,{registered={}},{})
assert(signature(configure(v))=='33,145','a fresh addon instance must read saved applied values')
assert(ids['native_stratagem_radial.hide_sos'].default==false)
assert(ids['native_stratagem_radial.blacklist_kind_8'].default==0)
print('Blacklist passed: default, stable IDs, duplicates/invalid values, loadout reorder, empty filtering, nonmutation, visibility ownership/restoration and saved settings.')
