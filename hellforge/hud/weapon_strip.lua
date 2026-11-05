local M={}
local fire={SEMI='3efff09cd12fb89a',AUTO='6115051c9558c50e',BURST='131742904d846798',VOLLEY='16413ee2e6725687'}
local ammo={FLAK='f8ede5f922c05cb6',APHET='9dcc0312a14e11e6'}
local rpm={'52bbfc5a70359393','c7546fc9c7b6db4e','f03c671b15d01a6b'}
local zoom={'6be28cced767bb52','46271d0b4ce4136c','a2ab43e85546f79a'}
-- Icon texture IDs as uint64 cdata, built once from the hex names above.
local asset_ids={}
do
 local ffi=require('ffi')
 for _,group in ipairs({fire,ammo,rpm,zoom})do
  for _,hex in pairs(group)do
   asset_ids[hex]=ffi.new('uint64_t',tonumber(hex:sub(1,8),16))*4294967296ULL+tonumber(hex:sub(9),16)
  end
 end
end
function M.icons(model)
 local result={};if not model then return result end
 local controls=model.changeable
 if type(controls)~='table'then return result end
 if controls.fire_mode==true and fire[model.fire_mode]then result[#result+1]={role='fire_mode',asset=fire[model.fire_mode],value=model.fire_mode}end
 local index=model.rpm_index
 if controls.rpm==true and model.rpm and type(index)=='number'and index%1==0 and index>=0 and index<=2 then
  result[#result+1]={role='rpm',asset=rpm[index+1],value=model.rpm}
 end
 if controls.ammo_mode==true and ammo[model.ammo_mode]then result[#result+1]={role='ammo_mode',asset=ammo[model.ammo_mode],value=model.ammo_mode}end
 local zi=model.zoom_index
 if controls.zoom==true and model.zoom and type(zi)=='number'and zi%1==0 and zi>=0 and zi<=2 then
  result[#result+1]={role='zoom',asset=zoom[zi+1],value=model.zoom}
 end
 return result
end
local function new_renderer(b,scope)
 local ffi=require('ffi')
 local function call(signature,offset)return ffi.cast(signature,b.base+offset)end
 local init=call('void (*)(uintptr_t,uint32_t)',0x1446840)
 local sprite=call('void (*)(uintptr_t)',0x143eab0)
 local asset=call('void (*)(uintptr_t,uint64_t,uint8_t)',0x144f800)
 local attach=call('void (*)(uintptr_t,uintptr_t)',0x144c5c0)
 local finish=call('void (*)(uintptr_t)',0x144c2c0)
 local opacity=call('void (*)(uintptr_t,float)',0x1448ad0)
 local order=call('void (*)(uintptr_t,uint32_t)',0x14491f0)
 local visible=call('void (*)(uintptr_t,uint8_t)',0x144cfb0)
 local uv=call('void (*)(uintptr_t, NSR_vec2, NSR_vec2)',0x143eef0)
 -- The icon textures carry a wide empty margin; show their centre so each glyph
 -- fills more of its tile (crop per side, in texture UV units).
 local zoom_crop=0.15
 local uv_min,uv_max=ffi.new('NSR_vec2',{zoom_crop,zoom_crop}),ffi.new('NSR_vec2',{1-zoom_crop,1-zoom_crop})
 local storage,address,identity,parent,key;local size=0x690
 -- Largest icon edge and spacing in HUD pixels (bottom-left pivot, Y up); on the
 -- weapon row the icons shrink to fit its height.
 local icon_size,icon_gap=48,10
 local self={status='closed',icons={}}
 local function owned()return address and b.valid(identity)and b.pointer(address+0xf0)==parent end
 local function bounds()
  assert(ffi.string(ffi.cast('const char *',address-16),16)==string.rep('\165',16),'Weapon status prefix overwritten')
  assert(ffi.string(ffi.cast('const char *',address+size),16)==string.rep('\165',16),'Weapon status suffix overwritten')
 end
 -- Frosted backing with corner trim behind the icons, styled like the Cooldowns
 -- overview panel. It lives on its own screen GUI (the dock owns the other one).
 local panel={}
 local function panel_hide()
  if panel.lease then assert(panel.lease.release(), "weapon GUI cleanup pending") end
  panel={}
 end
 local function panel_draw(v,x0,y0,x1,y1,seam)
  local sr=rawget(_G,'stingray');if not sr then return end
  if panel.lease and not panel.lease.valid()then panel={} end
  if not panel.lease then
   local A=sr.Application;local world=A.main_world()
   for _,candidate in pairs(A.worlds()or{})do if candidate~=world then world=candidate;break end end
   if not world then return end
   panel.owner={};panel.lease=cooldown_gui_pool(sr,'DBFWeaponStripGuiPool').acquire(world,panel.owner)
   panel.gui,panel.ui,panel.ids=panel.lease.gui,panel.lease.api,{}
   if type(A.can_get)=='function' and type(sr.Gui.bitmap)=='function' then
    for _,name in ipairs({'content/ui/shared/material/gui_blur','content/ui/shared/material/blur_background'})do
     local ok,available=pcall(A.can_get,'material',name)
     if ok and available then panel.blur_material=name;break end
    end
   end
  end
  local G,gui=panel.ui,panel.gui
  for _,item in ipairs(panel.ids)do G['destroy_'..item[1]](gui,item[2])end
  panel.ids={}
  -- Weapon HUD space (Y up) to screen GUI space through the container matrix.
  local function screen(x,y)return v[1]*x+v[3]*y+v[5],v[2]*x+v[4]*y+v[6]end
  local ax,ay=screen(x0,y0);local bx,by=screen(x1,y1)
  local left,bottom=math.min(ax,bx),math.min(ay,by)
  local width,height=math.abs(bx-ax),math.abs(by-ay)
  local unit=math.abs(bx-ax)/(x1-x0)
  local function add(kind,id)if id~=nil and id~=false then panel.ids[#panel.ids+1]={kind,id}end end
  local function color(name)
   local c=style.tokens.colors[name]
   return sr.Color(c[4],c[1],c[2],c[3])
  end
  if panel.blur_material then
   local ok,value=pcall(G.bitmap,gui,panel.blur_material,sr.Vector3(left,bottom,0x21f),sr.Vector2(width,height),color('text'))
   if ok then add('bitmap',value)end
  end
  add('rect',G.rect(gui,sr.Vector3(left,bottom,0x220),sr.Vector2(width,height),color('hud_plate')))
  local edge=math.max(1,unit*.65)
  -- Butted against the native box, the left edge is a seam marked by a vertical
  -- separator inset from top and bottom. No corner trims (they read as clutter
  -- once the panel continues the native row).
  if seam then
   local inset=math.min(height/4,8*unit)
   add('rect',G.rect(gui,sr.Vector3(left-edge/2,bottom+inset,0x221),sr.Vector2(edge,height-2*inset),color('line_strong')))
  end
  panel.lease.show()
 end
 function self.close()
  panel_hide()
  if not address then return true end
  local ok,why=b.release_owned_ui(storage,address,identity,parent,{})
  if not ok then self.status=why;return false,why end
  bounds();storage,address,identity,parent,key=nil,nil,nil,nil,nil;self.status='closed';return true
 end
 function self.hide()
  panel_hide()
  if owned()then visible(address,0)end;key=nil;self.status='hidden'
 end
 local node_floats,matrix_lanes=ffi.new('float[44]'),{0,2,8,10,12,14}
 local function geometry(node)
  local h=assert(b.read(node,0xb0));local v=node_floats;ffi.copy(v,h,#h)
  local width,height=v[9],v[10]
  local m={};for i,k in ipairs(matrix_lanes)do m[i]=v[25+k]end
  for _,n in ipairs(m)do assert(n==n and math.abs(n)<=100000,'Invalid weapon HUD transform')end
  assert(width>0 and width<10000 and height>0 and height<10000,'Invalid weapon HUD size')
  return width,height,m
 end
 function self.draw(root,model)
  local icons=M.icons(model);self.icons=icons
  if #icons==0 then self.hide();return end
  assert(b.valid(root),'Weapon status HUD changed')
  -- Same native current-weapon image used by the stock HUD; follow its matrix.
  local weapon=root+0x251468
  local context=assert(b.pointer(root+0x820+0xf8),'Weapon HUD context unavailable')
  local node,seen,frame,box=weapon,{},weapon,weapon
  for depth=1,24 do
   assert(node>=root and node<root+0x500000 and not seen[node],'Weapon HUD ancestry escaped or cycled')
   seen[node]=true
   local flags=b.u32(b.read(node,4),0)
   assert(flags and flags%2==1 and b.pointer(node+0xf8)==context,'Weapon HUD ancestry retired')
   if node==root+0x820 then break end
   box,frame=frame,node -- frame: last ancestor below the container; box: the weapon row inside it
   node=assert(b.pointer(node+0xf0),'Weapon HUD ancestry detached')
  end
  assert(node==root+0x820 and frame==root+0x24e3a0,'Weapon HUD frame mismatch')
  assert(box~=frame and box~=weapon,'Weapon row ancestry unavailable')
  geometry(weapon) -- validates the weapon image's transform
  local vw,vh,v=geometry(root+0x820)
  local det=v[1]*v[4]-v[2]*v[3];assert(math.abs(det)>0.01,'Weapon HUD transform degenerate')
  -- The weapon row's background box (the frame's child holding the weapon image)
  -- is the reference (container space, Y up).
  local bw,bh,bm=geometry(box);local box_top,box_bottom,box_left,box_right=-math.huge,math.huge,math.huge,-math.huge
  for _,c in ipairs({{0,0},{bw,0},{0,bh},{bw,bh}})do
   local ex,ey=bm[5]+bm[1]*c[1]+bm[3]*c[2]-v[5],bm[6]+bm[2]*c[1]+bm[4]*c[2]-v[6]
   local lx=(ex*v[4]-ey*v[3])/det
   local ly=(ey*v[1]-ex*v[2])/det
   box_top,box_bottom=math.max(box_top,ly),math.min(box_bottom,ly)
   box_left,box_right=math.min(box_left,lx),math.max(box_right,lx)
  end
  -- The panel sits on the weapon's own row, right of its box: flush with the
  -- box's top and bottom, a small gap from its right end. Icons scale to fit
  -- the row height (at most icon_size).
  local gap,pad=0,4 -- butted against the native box; the seam gets a separator
  local edge=math.max(8,math.min(icon_size,(box_top-box_bottom)-2*pad))
  local spacing=math.min(icon_gap,edge*0.25)
  local row=#icons*edge+(#icons-1)*spacing
  local x0=box_right+gap;local left=x0+pad
  local cy=box_bottom+((box_top-box_bottom)-edge)/2
  local parts={tostring(root),string.format('%.2f,%.2f,%.2f',left,cy,edge)}
  for _,item in ipairs(icons)do parts[#parts+1]=item.asset end
  local nextkey=table.concat(parts,':');if owned()and key==nextkey and panel.lease and panel.lease.valid() then return end
  if address and not owned()then assert(self.close())end
  scope.context_scope(root+0x820,function(resource)
   if not address then
    storage=ffi.new('uint8_t[?]',size+64);address=math.floor((tonumber(ffi.cast('uintptr_t',storage))+31)/16)*16
    ffi.fill(ffi.cast('void *',address-16),16,165);ffi.fill(ffi.cast('void *',address+size),16,165)
    identity,parent=root,root+0x820
    init(address,1);b.set(address,'size',{vw,vh});b.set(address,'anchor',{0,0});b.set(address,'pivot',{0,0});b.set(address,'position',{0,0});opacity(address,1)
    for i=1,4 do
     local p=address+0x110+(i-1)*0x160;sprite(p);assert(b.pointer(p+0xf8)==resource,'Weapon icon context changed')
     b.set(p,'anchor',{0,0});b.set(p,'pivot',{0,0});b.set(p,'size',{icon_size,icon_size});opacity(p,.92);order(p,0x400)
     attach(address,p);finish(address)
    end
    attach(parent,address);finish(parent);assert(owned(),'Weapon strip attachment failed')
   end
   for i=1,4 do local p=address+0x110+(i-1)*0x160;local item=icons[i]
    if item then asset(p,asset_ids[item.asset],0);uv(p,uv_min,uv_max);b.set(p,'size',{edge,edge});b.set(p,'position',{left+(i-1)*(edge+spacing),cy});visible(p,1)else visible(p,0)end
   end
   visible(address,1);bounds();key=nextkey;self.status='visible'
  end)
  local drawn,why=pcall(panel_draw,v,x0,box_bottom,left+row+pad,box_top,true)
  if not drawn then panel_hide();self.panel_error=tostring(why)end
 end
 return self
end

local function weapon_strip(backend, scope, bridge)
 local reader=weapon_reader(backend,bridge)
 local renderer=new_renderer(backend,scope)
 local elapsed,previous_root=0,nil
 local self={status='waiting for weapon HUD'}
 function self.hide()
  if previous_root then renderer.hide() end
  previous_root=nil
 end
 function self.update(snapshot,dt)
  elapsed=elapsed+math.max(0,math.min(dt or 0,1))
  if previous_root==snapshot.identity and elapsed<0.1 then return end
  elapsed,previous_root=0,snapshot.identity
  local model=reader.poll()
  if not model then renderer.hide();self.status=reader.status;return end
  local ok,why=pcall(renderer.draw,snapshot.identity,model)
  if not ok then renderer.hide();self.status=tostring(why);return end
  self.status=renderer.status
 end
 self.close=renderer.close
 return self
end
return {weapon_strip=weapon_strip, weapon_strip_icons=M.icons}
