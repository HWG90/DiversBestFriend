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
 local backing=call('void (*)(uintptr_t,uint32_t,uint8_t)',0x18166c0)
 local texture=call('void (*)(uintptr_t,uint32_t,uint64_t)',0x1450120)
 local material=call('uintptr_t (*)(uintptr_t)',0x144f6e0)
 local param4=call('void (*)(uintptr_t,uint32_t,const float *)',0x14498c0)
 local param2=call('void (*)(uintptr_t,uint32_t,const float *)',0x14497a0)
 local order=call('void (*)(uintptr_t,uint32_t)',0x14491f0)
 local visible=call('void (*)(uintptr_t,uint8_t)',0x144cfb0)
 local uv=call('void (*)(uintptr_t, NSR_vec2, NSR_vec2)',0x143eef0)
 local uv_min,uv_max=ffi.new('NSR_vec2',{.15,.15}),ffi.new('NSR_vec2',{.85,.85})
 -- One DBF-owned subtree: container, stock backing (including its sprite), four glyphs.
 local backing_offset,icons_offset=0x110,0x380
 local size=icons_offset+4*0x160
 local storage,address,identity,parent
 local assets,layout={},nil
 local self={status='closed',icons={}}
 local function owned()return address and b.valid(identity)and b.pointer(address+0xf0)==parent end
 local function bounds()
  assert(ffi.string(ffi.cast('const char *',address-16),16)==string.rep('\165',16),'Weapon status prefix overwritten')
  assert(ffi.string(ffi.cast('const char *',address+size),16)==string.rep('\165',16),'Weapon status suffix overwritten')
 end
 function self.close()
  if not address then return true end
  local ok,why=b.release_owned_ui(storage,address,identity,parent,{})
  if not ok then self.status=why;return false,why end
  bounds();storage,address,identity,parent=nil,nil,nil,nil
  assets,layout={},nil
  self.status='closed';return true
 end
 function self.hide()
  if owned()then visible(address,0)end
  self.status='hidden'
 end
 local function attach_child(owner,child)
  attach(owner,child);finish(owner)
 end
 local function create(root,row,resource)
  storage=ffi.new('uint8_t[?]',size+64)
  address=math.floor((tonumber(ffi.cast('uintptr_t',storage))+31)/16)*16
  ffi.fill(ffi.cast('void *',address-16),16,165);ffi.fill(ffi.cast('void *',address+size),16,165)
  identity,parent=root,row
  init(address,1)
  b.set(address,'anchor',{1,0});b.set(address,'pivot',{0,0});b.set(address,'position',{0,0})
  visible(address,0)
  local plate=address+backing_offset
  backing(plate,0x226,1) -- same stretch wrapper and gui_blur_curved as frame+0x8c0
  assert(b.pointer(plate+0xf8)==resource and b.pointer(plate+0x110+0xf0)==plate,'Weapon backing layout changed')
  attach_child(address,plate)
  for i=0,3 do
   local p=address+icons_offset+i*0x160
   sprite(p);assert(b.pointer(p+0xf8)==resource,'Weapon icon context changed')
   -- Stock option sprite constructor (1828c26) and diffuse_map update (1829219).
   -- Preserve all DDS channels; the native shader interprets their masks.
   asset(p,0x358512d85e35b47dULL,0)
   assert(tonumber(material(p))~=0,'Weapon icon material unavailable')
   param4(p,0x7701209e,ffi.cast('const float *',b.base+0x21e2d60))
   param2(p,0xe13777ce,ffi.cast('const float *',b.base+0x21e53c0))
   b.set(p,'anchor',{0,0});b.set(p,'pivot',{0,0});order(p,0x228)
   visible(p,0);attach_child(address,p)
  end
  attach_child(row,address);assert(owned(),'Weapon strip attachment failed')
 end
 local dimensions=ffi.new('float[2]')
 function self.draw(root,model)
  local icons=M.icons(model);self.icons=icons
  if #icons==0 then self.hide();return end
  assert(b.valid(root),'Weapon status HUD changed')
  local frame,container=root+0x24e3a0,root+0x820
  local row,plate,holder,glyph=frame+0x7b0,frame+0x8c0,frame+0x2fb8,frame+0x30c8
  local context=assert(b.pointer(container+0xf8),'Weapon HUD context unavailable')
  local function child(p,owner)
   local flags=b.u32(b.read(p,4),0)
   assert(flags and flags%2==1 and b.pointer(p+0xf8)==context and b.pointer(p+0xf0)==owner,'Weapon HUD row changed')
  end
  child(frame,container);child(row,frame);child(plate,row);child(plate+0x110,plate);child(holder,row);child(glyph,holder)
  if address and (identity~=root or not owned())then assert(self.close())end
  ffi.copy(dimensions,assert(b.read(row+0x24,8)),8)
  local height=tonumber(dimensions[1])
  assert(height>8 and height<10000,'Invalid weapon row height')
  local edge=math.min(48,height-8)
  local spacing=math.min(10,edge*.25)
  local resized=not layout or layout.height~=height or layout.count~=#icons
  local wrapper_style=b.get_text_style(plate)
  local backing_style=b.get_text_style(plate+0x110)
  local glyph_style,holder_style=b.get_text_style(glyph),b.get_text_style(holder)
  for i=1,4 do glyph_style[i]=glyph_style[i]*holder_style[i]end
  local style_key=table.concat(wrapper_style,',')..':'..table.concat(backing_style,',')..':'..table.concat(glyph_style,',')
  local changed=resized or self.status~='visible' or layout.style~=style_key
  for i,item in ipairs(icons)do if assets[i]~=item.asset then changed=true end end
  if not changed then return end
  scope.context_scope(row,function(resource)
   if not address then create(root,row,resource)end
   local owned_plate=address+backing_offset
   b.set_text_style(owned_plate,wrapper_style);b.set_text_style(owned_plate+0x110,backing_style)
   if resized then b.set(address,'size',{8+#icons*edge+(#icons-1)*spacing,height})end
   for i=1,4 do
    local p=address+icons_offset+(i-1)*0x160
    local item=icons[i]
    if item then
     if assets[i]~=item.asset then
      texture(p,0x3aa8b87e,asset_ids[item.asset]);uv(p,uv_min,uv_max);assets[i]=item.asset
     end
     if resized then
      b.set(p,'size',{edge,edge});b.set(p,'position',{4+(i-1)*(edge+spacing),(height-edge)/2})
     end
     b.set_text_style(p,glyph_style)
    end
    if resized then visible(p,item and 1 or 0)end
   end
   bounds();visible(address,1);layout={height=height,count=#icons,style=style_key};self.status='visible'
  end)
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
