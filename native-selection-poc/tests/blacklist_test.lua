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

print('Blacklist geometry/filter tests passed.')

local timers={identity=1,open=true,rows={{address=1,kind=1},{address=2,kind=2,timer_kind='cooldown',timer_seconds=60},{address=3,kind=3,timer_kind='incoming',timer_seconds=4},{address=4,kind=4,unavailable=true}}}
local docked=filter(timers,{},true);assert(#docked.rows==4 and #docked.excluded_rows==0 and docked.native_rows==timers.rows)
assert(#filter(timers,{},false).rows==4,'dock disabled restores original list membership')
print('Dock icons preserve complete native list membership')

local retained=filter(native,excluded,true)
assert(#retained.rows==#native.rows and #retained.excluded_rows==0)
for _,row in ipairs(retained.rows)do if excluded[row.kind]then assert(row.blacklisted==true)end end
assert(native.rows[1].blacklisted==nil,'native snapshot must not be mutated')
print('List Select retains blacklisted native rows; wheels continue filtering')

-- Rearm insertion can leave several native animation endpoints equal. Compact
-- onto unique slots, including the selected row's enlarged height, not those
-- overlapping endpoints. Both hide options share this one layout plan.
local props,rows={},{}
for i,kind in ipairs({124,145,33,49,3,25})do
 local address=1000+i*100;local y=i<=2 and -(i-1)*68 or -136
 rows[i]={address=address,entry=i-1,kind=kind,height=68,list_y=y}
 if kind==33 or kind==49 then rows[i].timer_kind='cooldown'elseif kind==25 then rows[i].timer_kind='incoming'end
 props[address]={scale={kind==3 and 1.1 or 1,kind==3 and 1.1 or 1},position={0,y},animation_a={0,y},animation_b={0,y}}
end
local compact=visibility({valid=function()return true end,
 get=function(a,k)return{unpack(props[a][k])}end,set=function(a,k,v)props[a][k]={unpack(v)}end})
local original={identity=9,open=true,rows=rows}
local view=filter(original,{[145]=true,[49]=true},false,true)
assert(#view.rows==3 and #view.excluded_rows==3 and view.rows[3].timer_kind=='incoming')
local function no_overlap(s)
 local shown={};for _,r in ipairs(s.rows)do shown[#shown+1]=r end
 table.sort(shown,function(a,b)return props[a.address].position[2]>props[b.address].position[2]end)
 for i=2,#shown do local prev,cur=shown[i-1],shown[i]
  assert(props[prev.address].position[2]-props[cur.address].position[2]>=prev.height*props[prev.address].scale[2]-.0001,'visible rows overlap')
 end
end
compact.step(view);no_overlap(view)
assert(rows[5].entry==4 and view.rows[2].kind==3,'native identity never changes during packing')
local inserted={address=1900,entry=8,kind=49,height=68,timer_kind='cooldown'}
props[1900]={scale={1,1},position={0,-68},animation_a={0,-68},animation_b={0,-68}}
table.insert(rows,2,inserted)
view=filter(original,{[145]=true,[49]=true},false,true);compact.step(view);no_overlap(view)
view=filter(original,{[145]=true,[49]=true},true,true);compact.step(view);no_overlap(view)
assert(#view.rows==4,'cooldown filter works independently of blacklist hiding')
compact.step(filter(original,{},true,false));assert(props[1900].scale[1]==1,'toggle off restores hidden rows')
local all={};for _,r in ipairs(rows)do all[r.kind]=true end
view=filter(original,all,false,true);compact.step(view);assert(#view.rows==0)
compact.restore();assert(props[1500].scale[2]==1.1,'all-hidden/close restores owned scales')
print('Combined list filters: duplicate endpoints, rearm insertion, selected scale, independent toggles, all-hidden and restoration passed')
