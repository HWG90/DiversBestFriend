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
