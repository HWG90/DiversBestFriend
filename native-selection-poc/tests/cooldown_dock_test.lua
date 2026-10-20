local f=assert(io.open('native-selection-poc/cooldown_dock.lua'));local source=f:read('*a');f:close()
local make=assert(loadstring(source..'\nreturn cooldown_dock_model'))()
local m=make()
local incoming={entry=0,kind=1,timer_kind='incoming',timer_seconds=12,dock_from={-500,600}}
local cooldown={entry=1,kind=2,timer_kind='cooldown',timer_seconds=60,dock_from={-400,700}}
local unavailable={entry=2,kind=3,unavailable=true,timer_kind='cooldown',timer_seconds=60}
local s={identity=1,rows={incoming,cooldown,unavailable,{entry=3,kind=4}}}
m.sample(s,0);assert(#m.order==2)
local items=m.layout(0,144);assert(items[1].x==-30 and items[1].y==144 and items[1].alpha==0,'new tile starts transparent in its dock slot')
items=m.layout(70,144);assert(items[1].alpha==0.5 and items[1].x==-30,'half-faded tile stays in its assigned spot')
items=m.layout(140,144);assert(items[1].alpha==1,'quick fade completes in 140ms')
items=m.layout(350,144);assert(items[1].x==-30 and items[2].x==30 and items[1].y==144 and items[1].alpha==1)
local first=items[1];incoming.timer_kind='cooldown';incoming.timer_seconds=120
m.sample(s,400);assert(m.layout(400,144)[1]==first and first.phase=='cooldown' and first.born==0)
s.rows={incoming};m.sample(s,500);m.layout(500,144);assert(m.layout(850,144)[1].x==0)
local moved=first.moved
for i=1,10000 do m.sample(s,1000+i);assert(m.layout(1000+i,144)[1].moved==moved) end
incoming.timer_kind=nil;incoming.timer_seconds=nil;m.sample(s,12000);assert(#m.order==0)
s.identity=2;s.rows={cooldown};m.sample(s,13000);assert(#m.order==1 and m.identity==2)
m.sample(nil,14000);assert(#m.order==0)
print('Cooldown dock: filtering, inbound handoff, centered reflow, stable idle and HUD reset passed.')

-- Native calls are mocked: validate lifecycle, reappearance and idle write cost.
local ffi=require('ffi');local props,parents={},{};local calls=0
local tick_calls=0
local parent=4096
local function prop(at) props[at]=props[at] or {};return props[at] end
local natives={
 [0x1446840]=function(at) prop(at) end,
 [0x1839520]=function(at) prop(at).native_tile=true;parents[at+0x920]=at end,
 [0x1839fd0]=function(at,dt,state,record)
  assert(prop(at).native_tile and record==9000);tick_calls=tick_calls+1;prop(at).cooling=state==4
  prop(at+0xa30).alpha=1;prop(at+0xb88).alpha=1;prop(at+0xce0).alpha=1
  ffi.cast('uint32_t *',at+0x14bc)[0]=2
  if prop(at).state~=state then ffi.cast('float *',at+0x14c4)[0]=999;prop(at).state=state end
  if dt==0 then assert(ffi.cast('float *',at+0x14c4)[0]==120,'native source span must be restored AFTER initialization')end
 end,
 [0x144c5c0]=function(p,c) parents[c]=p end,
 [0x144c2c0]=function() end,
 [0x144cfb0]=function(at,v) calls=calls+1;prop(at).visible=v end,
 [0x14491f0]=function() end,
 [0x1448ad0]=function(at,value)calls=calls+1;prop(at).alpha=value end,
}
local fake=setmetatable({cast=function(kind,value)
 if type(value)=='number' and natives[value] then return natives[value] end
 return ffi.cast(kind,value)
end},{__index=ffi})
local env=setmetatable({radial={full_color=true},require=function(name) if name=='ffi' then return fake end;return require(name) end,
 configure_stratagem_icon=function(b,at,info,cooling) calls=calls+1;prop(at).cooling=cooling end},{__index=_G})
local chunk=assert(loadstring(source..'\nreturn cooldown_dock'));setfenv(chunk,env)
local b={base=0,valid=function() return true end,pointer=function(at)
 return parents[at-0xf0] or (at%16==8 and 8192) end,
 read=function(at)if at==8000+0x14c4 then return ffi.string(ffi.new('float[1]',120),4)end;return string.rep('\0',8)end,
 set=function(at,key,value) calls=calls+1;prop(at)[key]=value end,get=function(at,key)if key=='position' then return prop(at).position end;return {64,64}end}
-- Context pointers are at widget+F8 and all allocations are 16-aligned.
b.pointer=function(at) if at%16==8 then return 8192 end;return parents[at-0xf0] end
local dock=chunk()(b,{context_scope=function(_,fn) return fn(8192) end},{presentation=function() return {} end})
local snap={identity=1,dock_parent=parent,dock_y=144,rows={{entry=0,kind=1,timer_kind='incoming',timer_seconds=12,dock_from={-700,850},dock_source=8000,dock_payload=9000}}}
dock.sample(snap,0);dock.draw(0);dock.draw(366)
local baseline=calls
for i=1,10000 do dock.sample(snap,366+i);dock.draw(366+i) end
assert(calls-baseline<=43*3,'settled layout is idle; only native-reset child suppression runs at bounded ticks')
assert(tick_calls<=43,'native card timers tick at most four times per second')
local root;for child,p in pairs(parents) do if p==parent then root=child end end
assert(root and props[root].visible==1)
local ticks_before_hide=tick_calls
dock.draw(10400,false);assert(props[root].visible==0,'HUD hide also hides owned dock')
dock.draw(10500,false);assert(tick_calls==ticks_before_hide,'hidden HUD does not tick native dock')
dock.draw(10600,true);assert(props[root].visible==1,'HUD restore resumes existing dock')

assert(props[root+0x110+0x920].position[1]==0 and props[root+0x110+0x920].position[2]==-37,'charge badge centered below timer')
assert(props[root+0x110+0xa30].alpha==0 and props[root+0x110+0xb88].alpha==0,'charge badge backings removed')
assert(props[root+0x110+0xce0].alpha==0,'native count cannot reappear after timer ticks')
env.radial.cooldown_timer=3;dock.draw(10900)
assert(props[root+0x110+0x920].position[2]==37,'below timer moves charge badge above icon')
snap.rows[1].timer_kind='cooldown';dock.sample(snap,11000);dock.draw(11000)
assert(props[root+0x110].cooling==true,'inbound changes to cooldown appearance')
snap.rows={};dock.sample(snap,12000);dock.draw(12000);assert(props[root].visible==0 and props[root+0x110].visible==0,'empty dock hides its card children explicitly')
snap.rows={{entry=0,kind=1,timer_kind='incoming',timer_seconds=12,dock_from={-700,850},dock_source=8000,dock_payload=9000}}
dock.sample(snap,13000);dock.draw(13000);assert(props[root].visible==1 and props[root+0x110].alpha==0,'new icon fades in after empty state')
prop(root+0x110).position={999,999};dock.draw(13250)
assert(props[root+0x110].position[1]==0 and props[root+0x110].position[2]==144,'native tick cannot leave a tile floating outside its slot')
dock.hide();assert(props[root].visible==0 and props[root+0x110].visible==0)
print('Dock native mock: ownership, inbound appearance, ready removal, reappearance and 10000 settled frames without layout writes and bounded native timer ticks passed.')

local created,destroyed,last_y=0,0,nil
local V=setmetatable({x=function(v)return v[1]end},{__call=function(_,...)return{...}end})
local panels,removed=0,0
local sr={Vector3=V,Vector2=function(...)return{...}end,Color=function(...)return{...}end,IdString64={from_hex=function(s)return s end},Material={set_texture=function()return true end}}
sr.Application={main_world=function()return 1 end,worlds=function()return{1}end}
sr.World={create_screen_gui=function()return 2 end,destroy_gui=function()end}
sr.Gui={resolution=function()return 1920,1080 end,material=function()return 3 end,
 text_extents=function()return{0},{40}end,text=function(gui,text,font,size,material,pos)assert(font=='game-font'and material=='game-material');created=created+1;last_y=pos[2];return created end,
 destroy_text=function()destroyed=destroyed+1 end,
 rect=function(_,pos,size,color)assert(pos[3]==949 and pos[1]==-24 and pos[2]==120 and size[1]==48 and size[2]==48 and color[1]==150,'full icon translucent backdrop beneath text');panels=panels+1;return panels end,
 destroy_rect=function()removed=removed+1 end}
local env=setmetatable({stingray=sr},{__index=_G});env._G=env
local chunk=assert(loadstring(source..'\nreturn cooldown_dock_text'));setfenv(chunk,env)
local view=chunk()({dock_font=function()return{font='game-font',atlas='atlas',material='game-material'}end,dock_text_position=function(s,x,y)return x,y end})
local items={{x=0,y=144,alpha=1,row={timer_seconds=10}}}
view.draw({identity=1},items,0,2);assert(created==2 and last_y==174,'above timer draws text and shadow')
for i=1,999 do view.draw({identity=1},items,i,2)end
assert(created==2 and destroyed==0,'unchanged displayed second must retain text and shadow')
view.draw({identity=1},items,1000,3);assert(created==4 and destroyed==2 and last_y==102)
local n=created
view.draw({identity=1},items,3600000,3);assert(created==n,'wall time must not run a separate countdown')
items[1].row.timer_seconds=4;view.draw({identity=1},items,3600001,3);assert(created==n+2,'native remaining time changes text and shadow')
view.draw({identity=1},items,3600002,4);assert(last_y==144-22*.35 and panels==1,'inside timer centered over compact backdrop')
items[1].phase='incoming';view.draw({identity=1},items,3600003,3,2,10)
assert(last_y==144-36*.35,'incoming countdown stays large and inside even with below style')
assert(panels==removed+1,'incoming/impact retains the full icon backdrop independently of charges')
items[1].phase=nil
items[1].row.timer_seconds=11;view.draw({identity=1},items,3600004,3,2,10);assert(last_y==102,'long cooldown stays below')
assert(removed==panels,'switching below removes inside backdrop')
items[1].row.timer_seconds=10;view.draw({identity=1},items,3600005,3,2,10);assert(last_y==144-36*.35,'threshold switches to large countdown')
view.draw({identity=1},items,3600006,3,1,10);assert(last_y==102,'short style can follow regular position')
view.draw({identity=1},items,1001,1)
items[1].phase='cooldown';items[1].charge_count=2;items[1].charge_side='above'
local charge_start=created
view.draw({identity=1},items,1002,1)
assert(created==charge_start+2,'charges render foreground plus shadow even with timer Off')
for i=1,1000 do view.draw({identity=1},items,1002+i,1)end
assert(created==charge_start+2,'unchanged charge retains text and shadow')
items[1].phase='incoming';view.draw({identity=1},items,2003,1)
assert(destroyed>=2,'incoming clears retained charge text and shadow')
items[1].charge_count=nil
print('Game-font dock labels: above/below, Off and unchanged-second retained text passed')

local active_worlds={1};local gui_worlds={};local next_gui=10;local released=0
sr.Application.worlds=function()return active_worlds end
sr.Application.main_world=function()return active_worlds[1]end
sr.World.create_screen_gui=function(w)next_gui=next_gui+1;gui_worlds[next_gui]=w;return next_gui end
sr.World.destroy_gui=function(w,g)
 assert(w==active_worlds[1] and gui_worlds[g]==w,'must never destroy GUI through a retired world')
 released=released+1
end
local old_text=sr.Gui.text
sr.Gui.text=function(g,...)
 assert(gui_worlds[g]==active_worlds[1],'must never draw through retired GUI')
 return old_text(g,...)
end
view.draw({identity=1},items,0,2)
active_worlds={2} -- world changed while native HUD identity stayed the same
view.draw({identity=1},items,1,2)
assert(released==0,'engine-owned retired GUI must be forgotten without native destruction')
active_worlds={};view.hide();assert(released==0)
active_worlds={3};view.draw({identity=1},items,2,2);view.hide();assert(released==1)
print('Dock text world retirement: unchanged HUD identity and safe unload passed')

local forbidden=setmetatable({},{__index=function()error('Timer Off entered native GUI/font API')end})
local off_env=setmetatable({stingray=forbidden},{__index=_G});off_env._G=off_env
local off_chunk=assert(loadstring(source..'\nreturn cooldown_dock_text'));setfenv(off_chunk,off_env)
local off_view=off_chunk()({dock_font=function()error('Timer Off resolved a font')end})
for i=1,10000 do off_view.draw({identity=1},items,i,1)end
off_view.hide()
print('Timer Off: 10000 updates without native GUI or font calls passed')

local frame=1
sr.IdString64.from_hex=function(hex)return{hex=hex,frame=frame}end
local function fresh(id)assert(type(id)=='table' and id.frame==frame,'retained frame-local resource ID')end
sr.Material.set_texture=function(_,slot,atlas)fresh(slot);fresh(atlas);return true end
sr.Gui.material=function(_,id)fresh(id);return 3 end
sr.Gui.text_extents=function(_,_,id)fresh(id);return{0},{40}end
sr.Gui.text=function(_,_,id,_,material)fresh(id);fresh(material);return 1 end
active_worlds={3}
view.draw({identity=1},items,1,2)
frame=2;items[1].row.timer_seconds=3;view.draw({identity=1},items,2,2)
frame=3;items[1].row.timer_seconds=2;view.draw({identity=1},items,3,2)
view.hide()
print('Game-font resource IDs: recreated at API calls across frames passed')

local value,writes=1,0
local make=assert(loadstring(source..'\nreturn cooldown_closed_notices'))()
local status=make({valid=function()return true end,get_opacity=function()return value end,set_opacity=function(_,v)value=v;writes=writes+1 end})
local closed={identity=1,open=false}
status.step(closed);assert(value==0)
local n=writes;for i=1,10000 do status.step(closed)end;assert(writes==n,'unchanged closed status group stays idle')
closed.open=true;status.step(closed);assert(value==1,'open list is complete')
closed.open=false;status.step(closed);status.restore();assert(value==1,'toggle off restores native notices')
status.step(closed);value=.5;status.restore();assert(value==.5,'foreign opacity preserved')
value=0;closed.open=false;status.step(closed);closed.open=true;status.step(closed)
assert(value==1,'opening a naturally transparent closed list must reveal its stratagems')
value=0;closed.open=false;status.step(closed);status.restore();assert(value==0,'unload while closed preserves native closed opacity')
print('All closed-menu notices: whole list group, open/toggle restoration and 10000 idle frames passed')

local model_factory=assert(loadstring(source..'\nreturn cooldown_dock_model'))()
local list=model_factory();list.sample({identity=2,rows={{entry=1,kind=1,timer_kind='incoming',timer_seconds=15},cooldown}},0)
local vertical=list.layout(400,144,true)
assert(vertical[1].x==-70 and vertical[2].x==-70 and vertical[1].y==182 and vertical[2].y==144,'overview stacks timed entries above stamina')
sr.Gui.rect=function(_,pos,size,color)assert(size[1]==112 and size[2]==24);return 1 end
local last_text
sr.Gui.text=function(_,text,id,_,material)fresh(id);fresh(material);last_text=text;return 1 end
items[1].row.timer_seconds=61;items[1].phase='incoming'
view.draw({identity=1,dock_y=144},items,400,5,2,10)
assert(last_text=='INBOUND 1:01','overview renders authoritative status and time without a separate countdown')
view.hide()

local separate=model_factory()
separate.sample({identity=3,rows={
 {entry=1,kind=3,timer_kind='incoming',timer_seconds=20},
 {entry=2,kind=4,timer_kind='cooldown',timer_seconds=120},
 {entry=3,kind=25,timer_kind='cooldown',timer_seconds=300},
 {entry=4,kind=33,timer_kind='cooldown',timer_seconds=5},
}},0)
separate.items[separate.order[2]].charge_count=2
separate.items[separate.order[2]].cooldown_span=120
local placed,divider=separate.layout(0,120,false,2,10,58)
assert(divider.x==0 and placed[2].x==42 and placed[3].x==102 and placed[1].x==-102 and placed[4].x==-42,'left short group has a distinct divider and no icon overlap')
separate.layout(400,120,false,3,10,58);placed,divider=separate.layout(800,120,false,3,10,58)
assert(divider.x==0 and placed[1].x==42 and placed[4].x==102 and placed[2].x==-102,'right short group mirrors left')
separate.layout(900,120,false,4,10,58);placed,divider=separate.layout(1300,120,false,4,10,58)
assert(not divider and placed[3].y==120 and placed[1].y==58 and placed[1].below_stamina,'stamina separates main and smaller short-status row')
separate.items[separate.order[2]].row.timer_seconds=5
separate.layout(1400,120,false,3,10,58);local full=separate.layout(1800,120,false,3,10,58)
assert(not full[2].short_status,'full Eagle cooldown stays main even with charges and five seconds left')
local lo,hi=math.huge,-math.huge;for _,v in ipairs(full)do lo=math.min(lo,v.x-24);hi=math.max(hi,v.x+24)end
assert(math.abs(lo+hi)<.0001,'entire separated bar remains centered')
separate.layout(1900,120,false,3,10,58,false);local unbalanced=separate.layout(2300,120,false,3,10,58,false)
assert(unbalanced[2].x==-30 and unbalanced[3].x==30,'balance Off keeps main group centered')
local rects=0
sr.Gui.rect=function(_,pos,size,color)assert(pos[3]==952 and size[1]==2 and size[2]==48);rects=rects+1;return 10 end
items[1].phase='incoming';items[1].charge_count=nil
view.draw({identity=1},items,1400,1,2,10,{x=42,y=120,alpha=1})
view.draw({identity=1},items,1500,1,2,10,{x=42,y=120,alpha=1})
assert(rects==1,'divider remains visible with timers Off and unchanged geometry stays retained')
view.hide()
print('Short-status separator: left/right, per-charge classification, stamina split and retained divider with timers Off passed')

local blocked=assert(loadstring(source..'\nreturn cooldown_dock_model'))()();local state={identity=1,rows={{entry=1,kind=33,unavailable=true}}}
blocked.sample(state,0);assert(#blocked.order==0)
blocked.sample(state,1,true);assert(#blocked.order==1 and blocked.layout(1,100,false,3,10)[1].phase=='unavailable')
blocked.sample(state,2,false);assert(#blocked.order==0)

