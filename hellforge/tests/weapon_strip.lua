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
for i,kind in ipairs({3,2,11,1}) do word(configs+0x34c+i*4,kind) end
map(control+0x70,wid,0)
local definitions=array(control+0xb0)
word(definitions+0x90,1); word(definitions+0x94,2)
float(definitions+0x154,25);float(definitions+0x158,50);float(definitions+0x15c,100)
word(rpm+0x38,1);ptr(array(rpm+0x68),weapon)
local rates=array(rpm+0x70);word(rates+0x1c,2)
float(rates+0x10,450);float(rates+0x14,600);float(rates+0x18,900)
local guards,accept=0,true
local bridge={
    dbf_hud_base=function() return base end,
    dbf_hud_guard=function() guards=guards+1;return accept and 1 or 0 end,
    dbf_hud_read=function(at, buffer, size)
        assert(size<=4096)
        for i=0,size-1 do buffer[i]=bytes[at+i] or 0 end
        return 1
    end,
}
local make_reader = dofile(hud..'/weapon_reader.lua').weapon_reader
local icons = dofile(hud..'/weapon_strip.lua').weapon_strip_icons
local reader=make_reader({base=base},bridge)
local first=assert(reader.poll(),reader.status)
assert(guards>20 and first.fire_mode=='SEMI' and first.ammo_mode=='APHET')
local row=icons(first)
assert(#row==4 and row[1].asset=='3efff09cd12fb89a' and row[2].value==900)
assert(row[3].asset=='9dcc0312a14e11e6' and row[4].value==50)
word(modes+4,0x54);word(configs+0x350,0)
local switched=icons(assert(reader.poll(),reader.status))
assert(#switched==3 and switched[1].role=='rpm' and switched[2].asset=='f8ede5f922c05cb6')
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
    [0x144f800]=function(p,id,mode) assert(id==(p==strip+0x900 and 0x5af260a786a2ae33ULL or 0x358512d85e35b47dULL) and mode==0);mine(p).asset=id end,
    [0x144f6e0]=function(p) assert(mine(p).asset);return p end,
    [0x14498c0]=function(p,id,v) assert(mine(p).asset and id==0x7701209e and tonumber(ffi.cast('uintptr_t',v))==base+0x21e2d60) end,
    [0x14497a0]=function(p,id,v) assert(mine(p).asset and id==0xe13777ce and tonumber(ffi.cast('uintptr_t',v))==base+0x21e53c0) end,
    [0x14491f0]=function(p,order) assert(mine(p) and order==0x228) end,
    [0x144cfb0]=function(p,v) mine(p).visible=v end,
    [0x144c5c0]=function(parent,p) assert(parent==stockrow or parent==strip);mine(p).owner=parent end,
    [0x144c2c0]=function(parent) assert(parent==stockrow or parent==strip) end,
    [0x1450120]=function(p,slot,id) assert(slot==0x3aa8b87e and mine(p).asset);nodes[p].texture=id;bindings=bindings+1 end,
    [0x143eef0]=function(p,lo,hi) assert(mine(p).texture and math.abs(lo.x-.15)<.001 and math.abs(hi.y-.85)<.001) end,
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
assert(nodes[icon].texture==0x3efff09cd12fb89aULL and nodes[icon].style[1]==.7)
assert(nodes[strip+0x110].style[1]==.5 and nodes[strip+0x220].style[2]==.75)
tick();assert(scopes==1 and bindings==4)
nodes[plate].style[1]=0;nodes[glyph].style[1]=1
tick();assert(nodes[strip+0x110].style[1]==0 and nodes[icon].style[1]==1 and bindings==4)
model={changeable={fire_mode=true},fire_mode='AUTO'}
tick();assert(nodes[icon].texture==0x6115051c9558c50eULL and nodes[icon+0x160].visible==0)
nodes[holder].owner=frame
tick();assert(renderer.status:find('Weapon HUD row changed',1,true) and nodes[strip].visible==0)
nodes[holder].owner=stockrow;tick();assert(nodes[strip].visible==1)
renderer.hide();assert(nodes[strip].visible==0)
assert(renderer.close() and renderer.close() and releases==1 and nodes[glyph].owner==holder)
