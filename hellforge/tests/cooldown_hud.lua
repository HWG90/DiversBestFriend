-- Run from the repository root with lua5.1. Native addresses are simulated.
local function load_module(name, env)
    local factory = assert(loadfile('hellforge/hud/'..name..'.lua'))
    setfenv(factory, env)
    return factory()
end

local env = setmetatable({}, {__index=_G})
env._G = env
env.radial = {cooldown_display=1, cooldown_timer=2, short_timer_style=2,
    brief_timer_limit=10, short_status_placement=1}
env.cooldown_tokens = load_module('hd2_ui_style', env).tokens
env.cooldown_gui_pool = load_module('cooldown_gui', env).cooldown_gui_pool
local module = load_module('cooldown_dock', env)

local root = 100000
local frame = root+0x24e340+0x60
local row_box, health = frame+0xb30, frame+0x3e70
local stamina = root+0x24e340+0x5778
local parent = {[frame]=root+0x820,[row_box]=frame,[health]=row_box,
    [stamina]=root+0x820,[stamina+0x110]=stamina}
local function pointer(at) return parent[at-0xf0] end
local viewport = {width=1920,matrix={2,0,0,2,3,7}}
local function geometry(at)
    local x = at==health and 240 or 200
    local y = at==row_box and 107 or 127
    return {width=100,height=10,matrix={2,0,0,2,x+3,y}}
end
local function bounds() return module.cooldown_bounds(root,pointer,geometry,viewport) end
local bar, hp = bounds()
assert(bar.bottom==60 and hp.bottom==50 and hp.left==-840 and hp.box_left==-860)
parent[health]=nil
local bar2,hp2=bounds()
assert(bar2 and not hp2)
parent[health]=row_box

local props, natives, words, text, primitives = {}, {}, {}, {}, {}
local ticks, tile, dock_root, draws, cleanup = 0,nil,nil,0,0
local function widget(at)
    if not props[at] then props[at]={size={64,64},anchor={1,1},pivot={1,0},position={5,6}} end
    return props[at]
end
local function word(at)
    if not words[at] then words[at]={[0]=0} end
    return words[at]
end
natives[0x1446840]=function(at) dock_root=at end
natives[0x1839520]=function(at,a,b,c,order,flags)
    assert(a==0 and b==0 and c==0 and order==0x22b and flags==0)
    tile=tile or at
    parent[at+0x920]=at
end
natives[0x1839fd0]=function(at,dt,state,payload)
    assert(word(at+0x14b8)[0]==payload-8000)
    assert(dt==0 or dt==0.25)
    if dt==0 then assert(word(at+0x14c4)[0]==120) end
    ticks=ticks+1
    widget(at).state=state
    for _,off in ipairs({0xa30,0xb88,0xce0}) do widget(at+off).opacity=1 end
    word(at+0x14bc)[0]=2
end
natives[0x144c5c0]=function(p,at) parent[at]=p end
natives[0x144c2c0]=function() end
natives[0x144cfb0]=function(at,v) widget(at).visible=v end
natives[0x14491f0]=function(_,v) assert(v==0x22b) end
natives[0x1448ad0]=function(at,v) widget(at).opacity=v end

local ffi={
    cast=function(sig,at)
        if sig=='uintptr_t' then return at end
        if sig:find('(*)',1,true) then return assert(natives[at]) end
        return word(at)
    end,
    new=function(sig,size) assert(sig=='uint8_t[?]' and size==0x15150);return 8000000 end,
    copy=function(dst,src,n) assert(src=='span' and n==4);dst[0]=120 end,
}
env.require=function(name) assert(name=='ffi');return ffi end
local function vector(...) return {...} end
local G={}
for _,kind in ipairs({'text','bitmap','rect'}) do
    G[kind]=function(_,value)
        draws=draws+1
        primitives[draws]=kind
        if kind=='text' then text[value]=true end
        return draws
    end
    G['destroy_'..kind]=function(_,id) assert(primitives[id]==kind);primitives[id]=nil end
end
G.resolution=function() return 1920,1080 end
G.material=function() return 1 end
G.set_visible=function() end
G.reset=function() assert(not next(primitives)) end
G.text_extents=function() return {0},{30} end
env.stingray={Gui=G, Application={main_world=function() return 1 end,worlds=function()return {1,2} end,
    can_get=function(_,material) return material=='content/ui/shared/material/gui_blur' end},
    World={create_screen_gui=function(world)assert(world==2);return 1 end},
    Material={set_texture=function()return true end}, IdString64={from_hex=function(h)return h end},
    Vector2=vector, Vector3=setmetatable({x=function(v)return v[1] end},{__call=function(_,...)return vector(...)end}),
    Color=vector}
local b={base=0,valid=function(id)return id==root end,
    pointer=function(at) if at==dock_root+0xf8 then return 111 end;return pointer(at) end,
    read=function(_,size) return size==4 and 'span' or string.rep('\0',8) end,
    get=function(at,key)return widget(at)[key] end,
    set=function(at,key,v)widget(at)[key]=v end,
    dock_font=function()return {font='a',material='b',atlas='c'} end,
    dock_text_position=function(_,x,y)return x+960,y end,
    release_owned_ui=function(_,at,id,p)assert(id==root and parent[at]==p);cleanup=cleanup+1;return true end}
local d=module.cooldown_dock(b,{context_scope=function(_,fn)return fn(111)end},{})
local s={identity=root,dock_y=144,dock_parent=root+0x258,health_bounds=hp,stamina_bounds=bar,
    rows={{entry=1,kind=2,timer_seconds=122,timer_kind='cooldown',dock_source=7001,dock_payload=8001},
          {entry=2,kind=3,timer_seconds=5,timer_kind='incoming',dock_source=7002,dock_payload=8002}}}
local function step(style,ms,visible)
    env.radial.cooldown_display=style
    d.sample(s,ms);d.draw(ms,visible)
    assert(not d.timer_error,d.timer_error)
end
step(1,0);step(1,70);assert(widget(tile).opacity==0.5)
step(1,400)
assert(widget(tile).scale[1]==48/64 and widget(tile).position[1]==-30)
assert(widget(tile).state==4 and widget(tile+0x1500).state==3)
assert(widget(tile+0xa30).opacity==0 and text['2:02'] and text['5'] and text['2'])
local previous=ticks
step(1,450);assert(ticks==previous)
step(2,700);step(2,1100)
assert(text['Cooldowns'] and text['In Progress'] and widget(tile+0xce0).opacity==1)
assert(widget(tile+0x920).position[1]==5 and widget(tile).scale[1]==32/64)
step(3,1500);step(3,1900)
assert(widget(tile).position[1]==hp.left+16 and widget(tile).position[2]==hp.bottom-19)
assert(widget(tile+0x1500).position[1]==hp.left+16+56)
assert(widget(tile+0xce0).opacity==1)
step(3,1910,false);assert(widget(dock_root).visible==0 and not next(primitives))
step(3,1950,true);assert(widget(dock_root).visible==1)
s.rows={};step(1,2000);assert(widget(dock_root).visible==0 and not next(primitives))
assert(d.close());step(1,2500);assert(cleanup==1 and not next(primitives))
local panel=root+0x24e340+0x146dc0
local list=panel+0x1040
parent[list]=panel+0x220
local alpha,writes=1,0
local notices=module.cooldown_closed_notices({
    valid=b.valid,pointer=pointer,
    get_opacity=function(at)assert(at==list);return alpha end,
    set_opacity=function(at,v)assert(at==list);alpha=v;writes=writes+1 end,
})
notices.step({identity=root,open=false});assert(alpha==0)
notices.step({identity=root,open=false});assert(writes==1)
notices.step({identity=root,open=true});assert(alpha==1)
notices.step({identity=root,open=false})
alpha=0.5
notices.restore();assert(alpha==0.5)
print('Cooldown HUD: target bounds, three native layouts, timers, badges, visibility and cleanup passed')
