-- Offline check that DBF never cancels the stratagem list's own card scale
-- tween. When a stratagem leaves the list (SSSD Delivery after its call-in),
-- the game clears the card's +0x36F0 and tweens its scale to (1,0) from the
-- current value (0x16B96E3 -> 0x12E9B90). set_scale (0x12DFBE0) cancels a
-- running tween: flag 0x2000000 with a slot in +0xA8 bits 33..43. A restore
-- written in that frame froze the card drawn at full size under the next row.
--   luajit offline_scale_tween.lua <source tree>
local tree=arg[1] or '../divers_best_friend'
local here=arg[0]:match('^(.*)/[^/]*$') or '.'
local env=dofile(here..'/synthetic_image.lua')(tree..'/src/guards.lua')
local ffi,bit=require('ffi'),require('bit')
local function slurp(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
local image,root,list=env.image,env.root,env.list
ffi.cdef'void fake_allow_writes(int);'
ffi.load(here..'/fake_win32.so').fake_allow_writes(1)

local function u32(address)return tonumber(ffi.cast('uint32_t *',address)[0])end
local function set_u32(address,value)ffi.cast('uint32_t *',address)[0]=value end
local function pair(address)local f=ffi.cast('float *',address);return {f[0],f[1]}end
local function set_pair(address,v)local f=ffi.cast('float *',address);f[0],f[1]=v[1],v[2]end
local function card(index)return list+0x110+index*0x3760 end
local function near(v,x,y)return math.abs(v[1]-x)<1e-4 and math.abs(v[2]-y)<1e-4 end

-- The game's tween, as far as the list uses it.
local TWEEN,SLOT=0x2000000,bit.lshift(0x7ff,1)
local function tweening(address)
    return bit.band(u32(address),TWEEN)~=0 and bit.band(u32(address+0xac),SLOT)~=0
end
local function start_tween(address,active)
    ffi.cast('uint8_t *',address+0x36f0)[0]=active and 1 or 0
    set_u32(address,bit.bor(u32(address),TWEEN));set_u32(address+0xac,bit.bor(u32(address+0xac),bit.lshift(7,1)))
end
local function finish_tween(address,target)
    if tweening(address) then set_pair(address+20,target) end
    set_u32(address,bit.band(u32(address),bit.bnot(TWEEN)));set_u32(address+0xac,bit.band(u32(address+0xac),bit.bnot(SLOT)))
end

-- Native widget setters as Lua stand-ins (the synthetic image holds only
-- their witness bytes). set_scale cancels a running tween like 0x12DFBE0.
local scale_calls={}
local stubs={
    [0x12dfbe0]=function(address,v)
        scale_calls[#scale_calls+1]=address
        if bit.band(u32(address),TWEEN)~=0 then set_u32(address+0xac,bit.band(u32(address+0xac),bit.bnot(SLOT)))end
        set_pair(address+20,{v.x,v.y})
    end,
    [0x12df3b0]=function(address,v)set_pair(address+4,{v.x,v.y})end,
}
-- Function-pointer ctypes never compare equal, so match bind's casts by address.
local proxy=setmetatable({cast=function(ct,value)
    if type(value)=='number' and stubs[value-image] and tostring(ffi.typeof(ct)):find('(*)',1,true) then
        return stubs[value-image]
    end
    return ffi.cast(ct,value)
end},{__index=ffi})

local scope=setmetatable({},{__index=_G})
scope.require=function(name)if name=='ffi' then return proxy end;return require(name)end
local cache={}
local mod={dir=tree,config={},scope=scope};scope.mod=mod
function mod.require(name)
    if cache[name]~=nil then return cache[name]end
    local chunk=assert(loadstring(slurp(tree..'/'..name),'@'..name));setfenv(chunk,scope)
    local value=chunk();if value==nil then value=true end;cache[name]=value;return value
end
for _,name in ipairs({'src/layout.lua','src/guards.lua','src/native.lua','src/blacklist.lua'})do
    for k,v in pairs(mod.require(name))do scope[k]=v end
end
local radial=scope.radial
radial.dim_unselected=false
local b=scope.native_backend()

local failures=0
local function check(name,ok)print((ok and 'PASS ' or 'FAIL ')..name);if not ok then failures=failures+1 end end
local function snap(excluded)
    local s=assert(b.snapshot())
    for _,row in ipairs(s.rows)do row.kind=row.entry end
    return scope.blacklist_snapshot(s,excluded or {},false,false)
end
local function calls_on(address)local n=0;for _,a in ipairs(scale_calls)do if a==address then n=n+1 end end;return n end

-- 1. The highlighted row's stratagem leaves the list (SSSD Delivery called in).
local lc=radial.list_controller(b)
radial.selected=card(2)
lc.step(true,snap())
check('highlight scales the selected row',near(pair(card(2)+20),1.1,1.1))
start_tween(card(2),false)
local before=calls_on(card(2))
lc.step(true,snap())
check('removed row: its shrink tween keeps running',tweening(card(2)))
check('removed row: no set_scale while it shrinks',calls_on(card(2))==before)
finish_tween(card(2),{1,0})
lc.step(true,snap())
lc.step(true,{open=false})
check('removed row ends collapsed, not drawn',near(pair(card(2)+20),1,0))
ffi.cast('uint8_t *',card(2)+0x36f0)[0]=1;set_pair(card(2)+20,{1,1})

-- 2. A blacklisted (hidden) row leaves the list while the menu is open.
local hidden=scope.blacklist_list_visibility(b)
local excluded={[103]=true}
hidden.step(snap(excluded))
check('blacklisted row is hidden',near(pair(card(3)+20),0,0))
start_tween(card(3),false)
before=calls_on(card(3))
hidden.step(snap(excluded))
check('removed hidden row: its tween keeps running',tweening(card(3)))
check('removed hidden row: no set_scale while it shrinks',calls_on(card(3))==before)
finish_tween(card(3),{1,0})
hidden.step(snap(excluded))
hidden.restore()
check('removed hidden row ends collapsed',near(pair(card(3)+20),1,0))
ffi.cast('uint8_t *',card(3)+0x36f0)[0]=1;set_pair(card(3)+20,{1,1})

-- 3. A row is highlighted while it is still growing in.
set_pair(card(4)+20,{1,0.4});start_tween(card(4),true)
radial.selected=card(4)
lc.step(true,snap())
check('growing row: highlight waits for the tween',tweening(card(4)) and near(pair(card(4)+20),1,0.4))
finish_tween(card(4),{1,1})
lc.step(true,snap())
check('grown row: highlight applies after the tween',near(pair(card(4)+20),1.1,1.1))
radial.selected=card(0)
lc.step(true,snap())
check('deselected row returns to full size',near(pair(card(4)+20),1,1))
lc.step(true,{open=false})

-- 4. Only the stock list cards are deferred; other widgets are set as before.
start_tween(card(1),true)
check('set reports a deferred list card',b.set(card(1),'scale',{1,1})==false and calls_on(card(1))==0)
finish_tween(card(1),{1,1})
local panel=env.panel
set_u32(panel,bit.bor(u32(panel),TWEEN));set_u32(panel+0xac,bit.lshift(3,1))
before=calls_on(panel)
b.set(panel,'scale',{1,1})
check('non-card widget: set_scale still called',calls_on(panel)==before+1)

-- 5. A removed card frozen at full size (cancelled leave tween, e.g. by an
-- older build) is found; the game's other card states are not.
local SHOWN=0x45011
local function card_state(index,active,transitioned,flags,scale)
    local c=card(index)
    ffi.cast('uint8_t *',c+0x36f0)[0]=active and 1 or 0
    ffi.cast('uint8_t *',c+0x3728)[0]=transitioned and 1 or 0
    set_u32(c,flags);set_u32(c+0xac,0);set_pair(c+20,scale)
end
card_state(6,false,true,SHOWN,{1,1})     -- frozen: the SSSD row
card_state(7,false,true,SHOWN,{1,0})     -- removed, tween finished (Eagle Rearm)
card_state(8,false,false,0x4500b,{1,1})  -- reset for a new list, hidden
card_state(9,false,true,SHOWN,{1,0.5});start_tween(card(9),false) -- still shrinking
card_state(10,true,true,SHOWN,{1,1})     -- in the list
local found=b.removed_drawn_cards(root)
check('only the frozen removed card is found',found and #found==1 and found[1].address==card(6) and found[1].index==6)
check('nothing is found in a changed HUD',b.removed_drawn_cards(root+8)==nil)
for i=6,10 do card_state(i,false,false,0,{1,1})end

print(failures==0 and 'PASS scale tween' or ('FAIL scale tween: '..failures))
os.exit(failures==0 and 0 or 1)
