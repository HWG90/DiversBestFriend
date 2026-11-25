-- The reader's PE gate, local entity ownership, option masks, live selectors and art IDs.
local hud = assert(arg[1])
local ffi = require('ffi')
local base = 0x10000000
local bytes = {}
local function put(address, value)
    for i=1,#value do bytes[address+i-1] = value:byte(i) end
end
local function word(address, value)
    local n = ffi.new('uint32_t[1]', value)
    put(address, ffi.string(n, 4))
end
local function float(address, value)
    put(address, ffi.string(ffi.new('float[1]', value), 4))
end
local function ptr(address, value)
    word(address,value)
    word(address+4,0)
end
local cursor = 0x20000000
local function allocate()
    cursor = cursor + 0x4000
    return cursor
end
local function array(at)
    local address = allocate()
    ptr(at, address)
    return address
end
local function map(at, id, index)
    local entries = array(at)
    word(at+8,1); word(at+12,0xffffffff); word(at+16,1)
    word(entries,id); word(entries+4,index)
end
local function component(at, offset, id, record)
    map(at+offset,id,0)
    ptr(array(at+offset+24),record)
end
local function global(rva) return array(base+rva) end
local player, owner = global(0x3326468), global(0x346bf98)
local inventory, driver = global(0x3326738), global(0x3326660)
local selector, control, rpm = global(0x3326420), global(0x3326ce0), global(0x33266d8)
local avatar, weapon = owner+0xf32f18, owner+0xf32f18+24
local aid, wid, unit = 12, 13, 85
put(base,'MZ'); word(base+60,128); put(base+128,'PE\0\0')
word(base+136,0x6ab3b43f); word(base+128+0x50,0x4744000)
-- The vanilla code operands the reader takes the records and the projectile list from.
word(base+0xfd9c53,0x1e65e4); word(base+0x75a378,0x15f); word(base+0x75a395,0x37c7670)
word(player+0x84,1); word(player+0x88,1)
local local_player = array(player+0xe8)
word(local_player+8,123); put(local_player+20,'\1'); map(player+0xd0,123,0)
word(player+0x3a8,unit); map(owner+0xf22ec8,unit,0)
word(avatar+8,aid); word(avatar+16,unit); put(avatar+20,'\1')
map(owner+0xf1aeb0,wid,1)
word(weapon,0x6f0b5c5f); word(weapon+4,0xa8cffb31); word(weapon+8,wid); put(weapon+20,'\1')
component(inventory,0x28,aid,avatar)
word(inventory+0x14,1)
local slot=array(inventory+0x50)
word(slot,wid); word(slot+28,1)
component(driver,0x28,wid,weapon); array(driver+0x50)
component(control,0x30,wid,weapon); word(control+0x20,1)
local modes, configs=array(control+0x60),array(control+0x58)
word(modes,2); word(modes+4,0x50)
for i,kind in ipairs({3,2,8,1}) do word(configs+0x34c+i*4,kind) end
map(control+0x70,wid,0)
local definitions=array(control+0xb0)
word(definitions+0x90,1); word(definitions+0x94,2)
float(definitions+0x154,25);float(definitions+0x158,50);float(definitions+0x15c,100)
word(rpm+0x38,1);ptr(array(rpm+0x68),weapon)
local rates=array(rpm+0x70);word(rates+0x1c,2)
float(rates+0x10,450);float(rates+0x14,600);float(rates+0x18,900)
-- Native kind 8 resolves the selected projectile through the RPM definition.
map(rpm+0x50,wid,0)
map(rpm+0x90,wid,0)
local projectile_definition=array(rpm+0xd0)
word(projectile_definition,115);word(projectile_definition+0x240,224)
local function asset(at,hex)
    word(at,tonumber(hex:sub(9),16));word(at+4,tonumber(hex:sub(1,8),16))
end
local aphet,flak='9dcc0312a14e11e6','f8ede5f922c05cb6'
local projectile_a,projectile_b=allocate(),allocate()
ptr(base+0x37c7670+115*8,projectile_a);asset(projectile_a+0x10,aphet)
ptr(base+0x37c7670+224*8,projectile_b);asset(projectile_b+0x10,flak)
local function static_definition(offset,n,stride)
    local p=array(owner+offset)
    local lo,hi=0x6f0b5c5f,0xa8cffb31
    local home=((hi%n)*(2^32%n)+lo%n)%n
    word(p+home*16,lo);word(p+home*16+4,hi);word(p+home*16+8,0)
    return p+n*16
end
local static_projectile=static_definition(0xf12e80,542,0x268)
word(static_projectile,115);word(static_projectile+0x240,224)
local native_definitions={
    [9]=static_definition(0xf12cd8,22,0xc0),
    [10]=static_definition(0xf12cd0,18,0x58),
    [11]=static_definition(0xf12bd8,730,0x4d0),
    [12]=static_definition(0xf12c88,10,0x2f0),
}
for kind,p in pairs(native_definitions) do
    local offsets=({[9]={0x80,0x90},[10]={0x18,0x40},[11]={0xa0,0xa8},[12]={0x158,0x2d0}})[kind]
    asset(p+offsets[1],aphet);asset(p+offsets[2],flak)
end
local read_hook
local guards,accept=0,true
local bridge={
    dbf_hud_base=function() return base end,
    dbf_hud_guard=function() guards=guards+1;return accept and 1 or 0 end,
    dbf_hud_read=function(at, buffer, size)
        if read_hook then read_hook(tonumber(at),size) end
        assert(size<=4096)
        for i=0,size-1 do buffer[i]=bytes[at+i] or 0 end
        return 1
    end,
}
local make_reader = dofile(hud..'/weapon_reader.lua').weapon_reader
local icons = dofile(hud..'/weapon_strip.lua').weapon_strip_icons
local reader=make_reader({base=base},bridge)
local first=assert(reader.poll(),reader.status)
assert(guards>20 and first.fire_mode=='SEMI' and first.ammo_options[1].asset==aphet and first.ammo_options[1].kind==8)
local row=icons(first)
assert(#row==4 and row[1].asset=='3efff09cd12fb89a' and row[2].value==900)
assert(row[3].asset=='9dcc0312a14e11e6' and row[4].value==50)
word(modes+4,0x54);word(configs+0x350,0)
local switched=icons(assert(reader.poll(),reader.status))
assert(#switched==3 and switched[1].role=='rpm' and switched[2].asset=='f8ede5f922c05cb6')
-- Unknown weapon resources use the same native paths: no resource whitelist.
-- Both choices of every target programmable kind, with unrelated control bits.
local shifts={[8]=2,[9]=6,[10]=8,[11]=10,[12]=14}
for kind=8,12 do
    word(configs+0x358,kind)
    for selected=0,1 do
        word(modes+4,0x1000+0x20+selected*2^shifts[kind])
        local model=assert(reader.poll(),reader.status)
        assert(not model.ammo_error,model.ammo_error)
        assert(model.ammo_options[1].kind==kind and model.ammo_options[1].index==selected)
        assert(model.ammo_options[1].asset==(selected==0 and aphet or flak))
    end
    word(modes+4,2*2^shifts[kind])
    local refused=assert(reader.poll(),reader.status)
    assert(#refused.ammo_options==0 and refused.ammo_error:find('outside native choices',1,true))
    assert(icons(refused)[1].role=='rpm','invalid optional metadata preserves other axes')
end
word(configs+0x358,8);word(modes+4,0x50)
-- Static projectile fallback, zero/out-of-range catalog IDs, missing texture.
word(rpm+0x98,0)
assert(assert(reader.poll()).ammo_options[1].asset==aphet)
word(rpm+0x98,1)
word(projectile_definition,0)
asset(base+0x37c7560+0x10,flak)
assert(assert(reader.poll()).ammo_options[1].asset==flak)
word(projectile_definition,0x15f)
assert(#assert(reader.poll()).ammo_options==0)
word(projectile_definition,115);asset(projectile_a+0x10,'0000000000000000')
assert(#assert(reader.poll()).ammo_options==0)
asset(projectile_a+0x10,aphet)
-- Mutation of the selected mode on the same weapon must refuse stale output.
read_hook=function(at)
    if at==projectile_a+0x10 then word(modes+4,0x54) end
end
assert(reader.poll()==nil and reader.status:find('programmable selection changed',1,true))
read_hook=nil;word(modes+4,0x50)
-- Component identity changes while catalog data is read must refuse the glyph.
read_hook=function(at)
    if at==projectile_a+0x10 then word(rpm+0x58,0) end
end
local changed=assert(reader.poll())
assert(#changed.ammo_options==0 and changed.ammo_error:find('component changed',1,true))
read_hook=nil;word(rpm+0x58,1)
assert(assert(reader.poll()).ammo_options[1].asset==aphet)
-- Later RPM reads cannot race a component relocation unnoticed.
read_hook=function(at)
    if at==rates then word(rpm+0x58,0) end
end
assert(reader.poll()==nil and reader.status:find('programmable projectile component missing',1,true))
read_hook=nil;word(rpm+0x58,1)
read_hook=function(at)
    if at==projectile_a+0x10 then word(control+0x38,0) end
end
assert(reader.poll()==nil and reader.status:find('control component changed',1,true))
read_hook=nil;word(control+0x38,1)
-- Four native axes can all be programmable; duplicate kinds remain one glyph.
for i,kind in ipairs({9,10,11,12}) do word(configs+0x34c+i*4,kind) end
word(modes+4,0)
local all=assert(reader.poll(),reader.status)
assert(#icons(all)==4 and not all.ammo_error)
word(configs+0x350,10)
assert(#icons(assert(reader.poll()))==3)
for i,kind in ipairs({0,2,8,1}) do word(configs+0x34c+i*4,kind) end
word(modes+4,0x50)
-- P2: moving the override row after reading its old icon must not publish it.
local function raced(action)
    read_hook=function(at) if at==projectile_a+0x10 then read_hook=nil;action() end end
    assert(reader.poll()==nil and reader.status:find('programmable source changed',1,true),reader.status)
    read_hook=nil
end
word(projectile_definition+0x268,224)
raced(function() map(rpm+0x90,wid,1) end)
assert(assert(reader.poll()).ammo_options[1].asset==flak)
map(rpm+0x90,wid,0)
local relocated=allocate();word(relocated,224)
raced(function() ptr(rpm+0xd0,relocated) end)
ptr(rpm+0xd0,projectile_definition)
raced(function() word(projectile_definition,224) end)
word(projectile_definition,115)
word(rpm+0x98,0)
raced(function() map(rpm+0x90,wid,1) end)
map(rpm+0x90,wid,0)
-- Kind 4 is the separate rounds-component projectile selector (not packed bits).
local rounds=global(0x3326cf0)
component(rounds,0x28,wid,weapon)
local round_state=array(rounds+0x58)
map(rounds+0x68,wid,0)
local round_definition=array(rounds+0xa8)
word(round_definition+0x40,115);word(round_definition+0x44,224)
local round_static=static_definition(0xf12820,50,0x88)
word(round_static+0x40,115);word(round_static+0x44,224)
word(configs+0x358,4)
for selected=0,1 do
    word(round_state+4,selected)
    local item=assert(reader.poll()).ammo_options[1]
    assert(item.kind==4 and item.index==selected and item.asset==(selected==0 and aphet or flak))
end
word(round_state+4,0)
word(rounds+0x70,0)
assert(assert(reader.poll()).ammo_options[1].asset==aphet)
word(rounds+0x70,1)
raced(function() word(round_state+4,1) end)
word(round_state+4,2)
assert(#assert(reader.poll()).ammo_options==0)
word(configs+0x358,8)
-- HellForge 0.5.0: the owner's records move behind the Game block and, with mods' projectiles, the projectile
-- list moves into a block of its own. The reader follows the rewritten operands; the old places read zero.
do
    local function get(address)
        local v=0;for i=3,0,-1 do v=v*256+(bytes[address+i] or 0) end;return v
    end
    local moved_records,list=owner+0x8261c78,base+0x14f29000
    local saved={};for i=0,47 do saved[i]=bytes[avatar+i] end
    local holders={get(inventory+0x28+24),get(driver+0x28+24),get(control+0x30+24),get(rpm+0x68)}
    local function records_at(at)
        for i=0,47 do bytes[avatar+i]=nil;bytes[moved_records+i]=nil end
        for i=0,47 do bytes[at+i]=saved[i] end
        ptr(holders[1],at);for i=2,4 do ptr(holders[i],at+24) end
        word(base+0xfd9c53,(at-owner+8)/8)
    end
    records_at(moved_records)
    local moved=assert(reader.poll(),reader.status)
    assert(moved.ammo_options[1].asset==aphet and moved.binding.avatar_record==moved_records,'the moved records')
    local mod_projectile=allocate();asset(mod_projectile+0x10,'0123456789abcdef')
    ptr(list+115*8,projectile_a);ptr(list+224*8,projectile_b);ptr(list+0x160*8,mod_projectile)
    ptr(base+0x37c7670+115*8,0)
    word(base+0x75a378,0x164);word(base+0x75a395,0x14f29000)
    assert(assert(reader.poll(),reader.status).ammo_options[1].asset==aphet,'the moved list, not the vanilla one')
    word(projectile_definition,0x160)
    assert(assert(reader.poll(),reader.status).ammo_options[1].asset=='0123456789abcdef','a mod projectile')
    word(projectile_definition,0x164)
    assert(#assert(reader.poll()).ammo_options==0,'past the moved bound')
    word(projectile_definition,115)
    word(base+0x75a395,0x37c7678)
    local bad=assert(reader.poll())
    assert(#bad.ammo_options==0 and bad.ammo_error:find('projectile list unrecognised',1,true),bad.ammo_error)
    word(base+0x75a395,0x14f29004)
    bad=assert(reader.poll())
    assert(#bad.ammo_options==0 and bad.ammo_error:find('projectile list unrecognised',1,true),'unaligned')
    word(base+0x75a395,0x14f29000);word(base+0x75a378,0x15e)
    bad=assert(reader.poll())
    assert(#bad.ammo_options==0 and bad.ammo_error:find('count unrecognised',1,true),bad.ammo_error)
    word(base+0x75a378,0x164)
    word(base+0xfd9c53,0x1e65e3)
    assert(reader.poll()==nil and reader.status:find('registry keys unrecognised',1,true),reader.status)
    records_at(avatar)
    ptr(base+0x37c7670+115*8,projectile_a)
    word(base+0x75a378,0x15f);word(base+0x75a395,0x37c7670)
    local back=assert(reader.poll(),reader.status)
    assert(back.ammo_options[1].asset==aphet and back.binding.avatar_record==avatar,'back to the vanilla layout')
end
-- The resource bytes only select definition records, never hard-coded names.
word(weapon,0x12345678);word(weapon+4,0xabcdef12)
assert(assert(reader.poll()).ammo_options[1].asset==aphet)
word(weapon,0x6f0b5c5f);word(weapon+4,0xa8cffb31)
word(weapon+8,77)
assert(reader.poll()==nil and reader.status:find('entity identity',1,true))
accept=false
local denied=make_reader({base=base},bridge)
assert(denied.poll()==nil and denied.status:find('layout mismatch',1,true))

-- Exercise the renderer through its production update/hide/close entry points.
ffi.cdef 'typedef struct {float x,y;} NSR_vec2;'
local root,resource=0x40000000,8192
local frame=root+0x24e3a0
local stockrow,plate,holder,glyph=frame+0x7b0,frame+0x8c0,frame+0x2fb8,frame+0x30c8
local nodes={}
local function node(p,owner)
    nodes[p]={owner=owner,style={1,1,1,1}}
    return nodes[p]
end
node(root+0x820);node(frame,root+0x820);node(stockrow,frame)
node(plate,stockrow).style[1]=.5
node(plate+0x110,plate).style={1,.75,.74,.72}
node(holder,stockrow);node(glyph,holder).style={.7,1,.98,.85}
node(frame+0x2e60,frame+0x2948).style={.4,.9,.85,.8}
local strip,scopes,releases,bindings=nil,0,0,0
local function mine(p) assert(strip and p>=strip and p<strip+0xa60,'write outside owned subtree');return nodes[p] end
local calls={
    [0x1446840]=function(p,k) assert(k==1);strip=p;node(p) end,
    [0x18166c0]=function(p,order,curved)
        assert(p==strip+0x110 and order==0x226 and curved==1)
        node(p);node(p+0x110,p)
    end,
    [0x143eab0]=function(p) mine(p);node(p) end,
    [0x144f800]=function(p,id,mode)
        assert(mode==0)
        if p==strip+0x900 then assert(id==0x5af260a786a2ae33ULL)
        elseif mine(p).asset then bindings=bindings+1
        else assert(id==0x358512d85e35b47dULL) end
        mine(p).asset=id
    end,
    [0x144f6e0]=function(p) assert(mine(p).asset);return p end,
    [0x14498c0]=function(p,id,v) assert(mine(p).asset and id==0x7701209e and tonumber(ffi.cast('uintptr_t',v))==base+0x21e2d60) end,
    [0x14497a0]=function(p,id,v) assert(mine(p).asset and id==0xe13777ce and tonumber(ffi.cast('uintptr_t',v))==base+0x21e53c0) end,
    [0x14491f0]=function(p,order) assert(mine(p) and order==0x228) end,
    [0x144cfb0]=function(p,v) mine(p).visible=v end,
    [0x144c5c0]=function(parent,p) assert(parent==stockrow or parent==strip);mine(p).owner=parent end,
    [0x144c2c0]=function(parent) assert(parent==stockrow or parent==strip) end,
    [0x143eef0]=function(p,lo,hi) assert(mine(p).asset and math.abs(lo.x-.15)<.001 and math.abs(hi.y-.85)<.001) end,
}
local proxy=setmetatable({cast=function(sig,v)
    if sig:find('(*)',1,true) then return assert(calls[v-base],sig) end
    return ffi.cast(sig,v)
end},{__index=ffi})
local model=first
local env=setmetatable({
    require=function(name) assert(name=='ffi');return proxy end,
    weapon_reader=function() return {poll=function()return model end}end,
},{__index=_G})
local chunk=assert(loadfile(hud..'/weapon_strip.lua'));setfenv(chunk,env)
local backend={
    base=base,valid=function(id)return id==root end,
    pointer=function(p)
        if nodes[p-0xf8]then return resource end
        if nodes[p-0xf0]then return nodes[p-0xf0].owner end
    end,
    read=function(p,n)
        if n==4 and nodes[p]then return 1 end
        assert(p==stockrow+0x24 and n==8)
        return ffi.string(ffi.new('float[2]',{450,56}),8)
    end,
    u32=function(word)return word end,
    set=function(p,k,v)mine(p)[k]=v end,
    get_text_style=function(p)return {unpack(nodes[p].style)}end,
    set_text_style=function(p,style)mine(p).style={unpack(style)}end,
    alloc_widget=function(n)return ffi.new('uint8_t[?]',n)end,
    release_owned_ui=function(storage,p,id,parent)
        assert(storage and p==strip and id==root and parent==stockrow and nodes[p].owner==stockrow)
        nodes[p].owner=nil;releases=releases+1;return true
    end,
}
local renderer=chunk().weapon_strip(backend,{context_scope=function(p,fn)
    assert(p==stockrow);scopes=scopes+1;return fn(resource)
end},{})
local function tick()renderer.update({identity=root},.1)end
tick();assert(renderer.status=='visible',renderer.status)
local divider=nodes[strip+0x900]
assert(divider.owner==strip and divider.visible==1 and divider.style[1]==.4)
assert(divider.size[1]==1 and divider.size[2]==32 and divider.anchor[2]==.5 and divider.position[1]==0)
local icon=strip+0x380
assert(nodes[strip].owner==stockrow and nodes[strip].anchor[1]==1)
assert(nodes[strip].size[1]==230 and nodes[icon].size[1]==48)
assert(nodes[icon].asset==0x3efff09cd12fb89aULL and nodes[icon].style[1]==.7)
assert(nodes[strip+0x110].style[1]==.5 and nodes[strip+0x220].style[2]==.75)
tick();assert(scopes==1 and bindings==4)
nodes[plate].style[1]=0;nodes[glyph].style[1]=1
tick();assert(nodes[strip+0x110].style[1]==0 and nodes[icon].style[1]==1 and bindings==4)
model={changeable={fire_mode=true},fire_mode='AUTO'}
tick();assert(nodes[icon].asset==0x6115051c9558c50eULL and nodes[icon+0x160].visible==0)
nodes[holder].owner=frame
tick();assert(renderer.status:find('Weapon HUD row changed',1,true) and nodes[strip].visible==0)
nodes[holder].owner=stockrow;tick();assert(nodes[strip].visible==1)
renderer.hide();assert(nodes[strip].visible==0)
assert(renderer.close() and renderer.close() and releases==1 and nodes[glyph].owner==holder)
