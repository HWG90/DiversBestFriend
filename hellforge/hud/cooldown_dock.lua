-- State and geometry are independent of native ownership and rendering.
local function cooldown_dock_timed(row,track_unavailable)
    return (track_unavailable and row.unavailable==true) or not row.unavailable and (row.timer_kind=='incoming' or row.timer_kind=='cooldown')
        and type(row.timer_seconds)=='number' and row.timer_seconds>0
end
local function cooldown_dock_model()
    local self={items={},order={},identity=nil}
    function self.reset() self.items={};self.order={};self.identity=nil end
    function self.sample(snapshot,now,track_unavailable)
        if not snapshot then self.reset();return end
        if self.identity~=snapshot.identity then self.reset();self.identity=snapshot.identity end
        local wanted={}
        for _,row in ipairs(snapshot.rows or {}) do
            if cooldown_dock_timed(row,track_unavailable) then
                local key=tostring(row.entry)..':'..tostring(row.kind)
                wanted[key]=true
                local item=self.items[key]
                if not item then
                    item={key=key,kind=row.kind,born=now}
                    self.items[key]=item;self.order[#self.order+1]=key
                end
                -- Incoming -> cooldown updates the same docked icon, without a second flight.
                local phase=row.unavailable and 'unavailable' or row.timer_kind
                if item.phase~=phase then item.cooldown_span=nil end
                item.phase=phase;item.row=row
            end
        end
        for i=#self.order,1,-1 do
            local key=self.order[i]
            if not wanted[key] then self.items[key]=nil;table.remove(self.order,i) end
        end
    end
    function self.layout(now,y,overview,placement,brief_limit,below_y,balanced,stamina,row)
        local result={};local n=#self.order
        local panels
        -- Compact row: 32 px tiles in one line under the health bar's row box,
        -- left-aligned with the bar; cooldowns, then a padded vertical
        -- separator, then incoming. Dock coordinates (x from centre, Y up).
        local row_y,row_divider
        if row then
            local size,pitch,pad=32,40,12
            -- 3 px under the health row: room for the timers below plus ~4 px of
            -- padding above the screen edge.
            row_y=row.bottom-3-size/2
            local x=row.left+size/2;local cooling,incoming={},{}
            for _,key in ipairs(self.order)do
                local item=self.items[key]
                local group=item.phase=='incoming' and incoming or cooling
                group[#group+1]=item
            end
            for _,item in ipairs(cooling)do item.row_x=x;x=x+pitch end
            if #cooling>0 and #incoming>0 then
                row_divider=x-pitch+size/2+pad
                x=row_divider+pad+size/2
            end
            for _,item in ipairs(incoming)do item.row_x=x;x=x+pitch end
        end
        if overview then
            local groups={{title='Cooldowns',items={}},{title='In Progress',items={}}}
            for _,key in ipairs(self.order)do
                local item=self.items[key]
                item.short_status=item.phase=='incoming' or item.phase~='unavailable' and math.max(item.cooldown_span or 0,item.row.timer_seconds or 0)<=(brief_limit or 10)
                local group=groups[item.short_status and 2 or 1]
                group.items[#group.items+1]=item
            end
            panels={};local bottom=stamina and stamina.bottom or y-24
            for index=2,1,-1 do
                local group=groups[index];local count=#group.items
                if count>0 then
                    local top=bottom+count*36+40
                    local offset=index==1 and ((stamina and stamina.left or -110)-12-56) or ((stamina and stamina.right or 110)+12+56)
                    panels[#panels+1]={title=group.title,left=offset-56,right=offset+56,bottom=bottom,top=top}
                    for i,item in ipairs(group.items)do item.overview_y=top-50-(i-1)*36;item.overview_offset=offset end
                end
            end
        end
        local split=not overview and not row and placement and placement>1
        local short_n=0
        if split then for _,key in ipairs(self.order)do
            local item=self.items[key]
            -- Remaining charges survive a full Eagle rearm. They do not prove
            -- this is the brief between-run cooldown; classify by native time.
            item.short_status=item.phase=='incoming'or item.phase~='unavailable' and math.max(item.cooldown_span or 0,item.row.timer_seconds or 0)<=(brief_limit or 10)
            if item.short_status then short_n=short_n+1 end
        end end
        local main_n=n-short_n;local main_i,short_i=0,0
        local balance=balanced~=false and split and placement~=4 and main_n>0 and short_n>0 and (short_n*30+12)*(placement==2 and 1 or -1)or 0
        for i,key in ipairs(self.order) do
            local item=self.items[key]
            local x=row and item.row_x or overview and item.overview_offset+28 or (i-(n+1)/2)*60
            local target_y=row and row_y or overview and item.overview_y or y
            item.below_stamina=false;item.compact_row=row~=nil
            if split then
                if item.short_status then
                    short_i=short_i+1
                    if placement==4 then
                        x=(short_i-(short_n+1)/2)*60;target_y=below_y or y-62;item.below_stamina=true
                    elseif main_n==0 then x=(short_i-(short_n+1)/2)*60
                    elseif placement==2 then x=-(main_n*30+54)-(short_n-short_i)*60
                    else x=main_n*30+54+(short_i-1)*60 end
                else main_i=main_i+1;x=(main_i-(main_n+1)/2)*60 end
            end
            x=x+balance
            if item.target_x~=x or item.target_y~=target_y then
                item.start_x,item.start_y=item.x or x,item.y or target_y
                item.target_x,item.target_y=x,target_y;item.moved=now
            end
            local t=math.min(1,math.max(0,(now-item.moved)/350));local ease=1-(1-t)^3
            item.x=item.start_x+(x-item.start_x)*ease;item.y=item.start_y+(target_y-item.start_y)*ease
            item.alpha=math.min(1,math.max(0,(now-item.born)/140))
            result[i]=item
        end
        local divider
        if row_divider then
            local alpha=1;for _,item in ipairs(result)do alpha=math.min(alpha,item.alpha)end
            divider={x=row_divider,y=row_y,alpha=alpha,half=16}
        elseif split and placement~=4 and main_n>0 and short_n>0 then
            local alpha=1;for _,item in ipairs(result)do alpha=math.min(alpha,item.alpha)end
            divider={x=(main_n*30+12)*(placement==2 and -1 or 1)+balance,y=y,alpha=alpha}
        end
        return result,divider,panels
    end
    return self
end
-- Called by wheel_native.snapshot with the validated root and its matrix reader.
-- 25480438 gameplay constructor: 12f0c17 -> 12e96d0, 12e9726 adds
-- 0x60 before calling 1816a60. 1818b9e constructs frame+0x3e70;
-- 1818c53..60 attaches it to frame+0xb30. Verify the live edges as well.
local function cooldown_bounds(root, pointer, geometry, viewport)
    local v = viewport.matrix
    local det = v[1]*v[4] - v[2]*v[3]
    if math.abs(det) <= 0.000001 then return end

    local function bounds(node, max_width, max_height)
        local ok, g = pcall(geometry, node)
        if not ok or not g or g.width <= 0 or g.width > max_width
            or g.height <= 0 or g.height > max_height then return end
        local m = g.matrix
        local left, right, bottom, top = math.huge, -math.huge, math.huge, -math.huge
        for _, corner in ipairs({{0,0}, {g.width,0}, {0,g.height}, {g.width,g.height}}) do
            local x = m[1]*corner[1] + m[3]*corner[2] + m[5] - v[5]
            local y = m[2]*corner[1] + m[4]*corner[2] + m[6] - v[6]
            local px = (x*v[4] - y*v[3])/det - viewport.width/2
            local py = (y*v[1] - x*v[2])/det
            left, right = math.min(left, px), math.max(right, px)
            bottom, top = math.min(bottom, py), math.max(top, py)
        end
        return {left=left, right=right, bottom=bottom, top=top}
    end

    local gameplay = root + 0x24e340
    local stamina = gameplay + 0x5778
    local stamina_bar = stamina + 0x110
    local stamina_bounds, health_bounds
    if pointer(stamina+0xf0) == root+0x820 and pointer(stamina_bar+0xf0) == stamina then
        stamina_bounds = bounds(stamina_bar, 1200, 100)
    end
    local frame = gameplay + 0x60
    local row, bar = frame+0xb30, frame+0x3e70
    if pointer(frame+0xf0) == root+0x820 and pointer(row+0xf0) == frame and pointer(bar+0xf0) == row then
        local box, fill = bounds(row, 2000, 500), bounds(bar, 2000, 500)
        if box and fill then
            health_bounds = {left=fill.left, right=fill.right, bottom=box.bottom, top=box.top,
                box_left=box.left, box_right=box.right}
        end
    end
    return stamina_bounds, health_bounds
end
-- Retained screen-GUI labels. No timer subscription exists; consume the dock's
-- existing timer updates and change retained text only when its value changes.
local function cooldown_dock_text(b)
    local self={};local gui,world,sr,font,identity,attempted,lease,ui;local labels={}
    local owner={}
    local separator,separator_key
    local overview_panels={};local overview_key;local blur_material
    local function text_width(min,max)
        return sr.Vector3.x(max)-sr.Vector3.x(min)
    end
    local function color(name, opacity)
        local rgba = cooldown_tokens.colors[name]
        return sr.Color(math.floor(rgba[4] * (opacity or 1)), rgba[1], rgba[2], rgba[3])
    end
    local function destroy_label(label)
        if not label then return end
        ui.destroy_text(gui,label.id);ui.destroy_text(gui,label.shadow)
        if label.backdrop then ui.destroy_rect(gui,label.backdrop)end
    end
    local function destroy_panel(panel)
        ui.destroy_rect(gui,panel.rect);destroy_label(panel.label)
        if panel.blur then ui.destroy_bitmap(gui,panel.blur)end
        for _,id in ipairs(panel.trim or {})do ui.destroy_rect(gui,id)end
    end
    function self.hide()
        if not lease and not gui and not attempted and identity==nil then return end
        if lease then lease.release()end
        lease,ui,gui,world,font,identity,attempted=nil,nil,nil,nil,nil,nil,nil
        labels={};overview_panels={};separator,separator_key,overview_key,blur_material=nil,nil,nil,nil
    end
    function self.close()
        self.closed=true
        self.hide()
    end
    function self.draw(s,items,now,position,short_style,brief_limit,divider,panels)
        if self.closed or owner.retired then return end
        local timers=position and position~=1
        local charges=false
        for _,item in ipairs(items)do if item.phase=='cooldown' and item.charge_count then charges=true;break end end
        if (not timers and not charges and not divider) or #items==0 then self.hide();return end
        local current=rawget(_G,'stingray');if not current or not b.dock_font then return end
        if sr~=current or identity~=s.identity then self.hide();sr=current;identity=s.identity end
        if lease and not lease.valid() then self.hide();identity=s.identity end
        if not gui then
            if attempted then return end;attempted=true
            font=b.dock_font(sr);if not font then return end
            local A,G=sr.Application,sr.Gui;world=A.main_world()
            for _,candidate in pairs(A.worlds()or{})do if candidate~=world then world=candidate;break end end
            if not world then return end
            lease=cooldown_gui_pool(sr).acquire(world,owner)
            gui,ui=lease.gui,lease.api
            G=ui
            -- Probe native HUD materials once per GUI lifetime, never each tick.
            if type(A.can_get)=='function' and type(G.bitmap)=='function' then
                for _,name in ipairs({'content/ui/shared/material/gui_blur','content/ui/shared/material/blur_background'})do
                    local ok,available=pcall(A.can_get,'material',name)
                    if ok and available then blur_material=name;break end
                end
            end
            local ok,material=pcall(G.material,gui,sr.IdString64.from_hex(font.material))
            if not ok or not material then material=G.create_material(gui,sr.IdString64.from_hex(font.material))end
            if not material or sr.Material.set_texture(material,sr.IdString64.from_hex('88BAC99B00000000'),sr.IdString64.from_hex(font.atlas))==false then self.hide();attempted=true;return end
        end
        local G=ui;lease.show();local width=G.resolution();local scale=(width or 1920)/1920
        -- Panel geometry is retained separately from ticking labels. Only a
        -- membership/layout change rebuilds backgrounds and headings.
        local panel_parts={}
        for _,panel in ipairs(panels or {})do panel_parts[#panel_parts+1]=panel.title..':'..panel.left..':'..panel.right..':'..panel.bottom..':'..panel.top end
        local origin_x,origin_y=b.dock_text_position(s,0,0)
        local unit_x,unit_y=b.dock_text_position(s,1,1)
        local panel_key=table.concat(panel_parts,'|')..':'..origin_x..':'..origin_y..':'..unit_x..':'..unit_y
        if panel_key~=overview_key then
            for _,panel in ipairs(overview_panels)do destroy_panel(panel)end
            overview_panels={};overview_key=panel_key
            for _,panel in ipairs(panels or {})do
                local left,bottom=b.dock_text_position(s,panel.left,panel.bottom)
                local right,top=b.dock_text_position(s,panel.right,panel.top)
                local unit=math.abs(right-left)/(panel.right-panel.left)
                local size=12*unit
                local x,y=b.dock_text_position(s,panel.left+10,panel.top-19)
                local text=panel.title
                local min,max=G.text_extents(gui,text,sr.IdString64.from_hex(font.font),size)
                local extent=text_width(min,max)
                if extent>92*unit then size=size*92*unit/extent end
                local id=G.text(gui,text,sr.IdString64.from_hex(font.font),size,sr.IdString64.from_hex(font.material),sr.Vector3(x,y,951),color('text'))
                local shadow=G.text(gui,text,sr.IdString64.from_hex(font.font),size,sr.IdString64.from_hex(font.material),sr.Vector3(x+unit,y-unit,950),color('hud_shadow'))
                -- Frost, tint and trim remain below native icons (0x22b).
                local panel_left,panel_bottom=math.min(left,right),math.min(bottom,top)
                local panel_width,panel_height=math.abs(right-left),math.abs(top-bottom)
                local frost
                if blur_material then
                    local ok,value=pcall(G.bitmap,gui,blur_material,sr.Vector3(panel_left,panel_bottom,0x21f),sr.Vector2(panel_width,panel_height),color('text',210/255))
                    if ok then frost=value end
                end
                local trim={}
                local function line(x,y,w,h,alpha)
                    trim[#trim+1]=G.rect(gui,sr.Vector3(x,y,0x221),sr.Vector2(w,h),color('line_strong',alpha/255))
                end
                local edge=math.max(1,unit*.65);local arm=6*unit
                for _,cx in ipairs({panel_left,panel_left+panel_width-arm})do
                    line(cx,panel_bottom,arm,edge,155)
                    line(cx,panel_bottom+panel_height-edge,arm,edge,155)
                end
                for _,cx in ipairs({panel_left,panel_left+panel_width-edge})do
                    line(cx,panel_bottom,edge,arm,155)
                    line(cx,panel_bottom+panel_height-arm,edge,arm,155)
                end
                line(panel_left+10*unit,panel_bottom+panel_height-26*unit,panel_width-20*unit,edge,90)
                overview_panels[#overview_panels+1]={rect=G.rect(gui,sr.Vector3(panel_left,panel_bottom,0x220),sr.Vector2(panel_width,panel_height),color('hud_plate',(frost and 95 or 155)/204)),label={id=id,shadow=shadow},blur=frost,trim=trim}
            end
        end
        for i=1,16 do
            local item,old=items[i],labels[i]
            if item and timers and (item.phase~='unavailable' or position==5) then
                local seconds=math.max(0,math.ceil(item.row.timer_seconds or 0))
                local overview=position==5
                local incoming=item.phase=='incoming' or item.row.timer_kind=='incoming'
                local large=not overview and short_style==2 and (incoming or seconds<=(brief_limit or 10))
                local inside=large or position==4
                -- Compact-row tiles are 32 px: smaller timers fit them.
                local size=math.max(14,(large and 36 or item.compact_row and 15 or inside and 22 or 18)*scale)
                local text=large and tostring(seconds) or string.format('%d:%02d',math.floor(seconds/60),seconds%60)
                local above=position==2 and not item.below_stamina
                -- Compact row: below the 32 px tile (16 px half, 2 px gap, 15 px text).
                local x,y=b.dock_text_position(s,item.x,item.y+(inside and 0 or above and 30 or item.compact_row and -33 or -42))
                if overview then
                    local left=b.dock_text_position(s,(item.overview_offset or 0)-46,item.y)
                    local right=b.dock_text_position(s,(item.overview_offset or 0)+4,item.y)
                    size=16*math.abs(right-left)/50
                    text=item.phase=='unavailable' and 'Unavailable' or text
                    x,y=b.dock_text_position(s,(item.overview_offset or 0)+4,item.y-5)
                end
                if inside then y=y-size*.35 end
                local key=text..':'..x..':'..y..':'..item.alpha..':'..size..':'..tostring(overview)
                if not old or old.key~=key then
                    destroy_label(old)
                    local min,max=G.text_extents(gui,text,sr.IdString64.from_hex(font.font),size)
                    local extent=text_width(min,max)
                    if overview then
                        local left=b.dock_text_position(s,(item.overview_offset or 0)-46,item.y)
                        local available=math.abs(x-left)
                        if extent>available then size=size*available/extent;extent=available end
                    end
                    local backdrop
                    if inside then
                        local half=(item.below_stamina or item.compact_row) and 16 or 24
                        local left,bottom=b.dock_text_position(s,item.x-half,item.y-half)
                        local right,top=b.dock_text_position(s,item.x+half,item.y+half)
                        backdrop=G.rect(gui,sr.Vector3(math.min(left,right),math.min(bottom,top),949),sr.Vector2(math.abs(right-left),math.abs(top-bottom)),color('hud_plate',item.alpha*150/204))
                    end
                    local text_x=overview and x-extent or x-extent/2
                    local shadow_id=G.text(gui,text,sr.IdString64.from_hex(font.font),size,sr.IdString64.from_hex(font.material),sr.Vector3(text_x+2*scale,y-2*scale,950),color('hud_shadow',item.alpha))
                    labels[i]={key=key,backdrop=backdrop,shadow=shadow_id,id=G.text(gui,text,sr.IdString64.from_hex(font.font),size,sr.IdString64.from_hex(font.material),sr.Vector3(text_x,y,951),color('text',item.alpha))}
                end
            elseif old then destroy_label(old);labels[i]=nil end
            local old_charge=labels[i+16]
            if item and item.phase=='cooldown' and item.charge_count then
                local text=tostring(item.charge_count);local size=18*scale
                if position==5 then size=12*math.abs(unit_x-origin_x)end
                local side=item.charge_side
                local x,y=b.dock_text_position(s,item.x+(position==5 and 20 or side=='left'and -36 or 0),item.y+(side=='above'and 37 or side=='left'and 0 or -37))
                y=y-size*.35
                local key=text..':'..x..':'..y..':'..item.alpha..':'..size
                if not old_charge or old_charge.key~=key then
                    destroy_label(old_charge)
                    local min,max=G.text_extents(gui,text,sr.IdString64.from_hex(font.font),size)
                    local extent=text_width(min,max)
                    local shadow=G.text(gui,text,sr.IdString64.from_hex(font.font),size,sr.IdString64.from_hex(font.material),sr.Vector3(x-extent/2+2*scale,y-2*scale,950),color('hud_shadow',item.alpha))
                    labels[i+16]={key=key,shadow=shadow,id=G.text(gui,text,sr.IdString64.from_hex(font.font),size,sr.IdString64.from_hex(font.material),sr.Vector3(x-extent/2,y,951),color('text',item.alpha))}
                end
            elseif old_charge then destroy_label(old_charge);labels[i+16]=nil end
        end
        if divider then
            local half=divider.half or 24
            local left,bottom=b.dock_text_position(s,divider.x-1,divider.y-half)
            local right,top=b.dock_text_position(s,divider.x+1,divider.y+half)
            local key=left..':'..bottom..':'..right..':'..top..':'..divider.alpha
            if key~=separator_key then
                if separator then G.destroy_rect(gui,separator)end
                separator=G.rect(gui,sr.Vector3(left,bottom,952),sr.Vector2(right-left,top-bottom),color('text',divider.alpha*210/255))
                separator_key=key
            end
        elseif separator then G.destroy_rect(gui,separator);separator,separator_key=nil,nil end
    end
    return self
end
-- Consume the dock's existing native snapshots; never start another reader.
local function cooldown_closed_notices(b)
    local self={};local saved
    function self.restore(open)
        if saved and b.valid(saved.identity) and b.pointer(saved.address+0xf0)==saved.identity+0x24e340+0x146dc0+0x220 and b.get_opacity(saved.address)==saved.applied then
            -- Closed native lists can already have alpha zero. Replaying that
            -- value after the open transition makes the entire menu invisible.
            b.set_opacity(saved.address,open and saved.before==0 and 1 or saved.before)
        end
        saved=nil
    end
    function self.step(s)
        if not s or s.open~=false then self.restore(s and s.open==true);return end
        local panel=s.identity+0x24e340+0x146dc0
        local address=panel+0x1040
        assert(b.pointer(address+0xf0)==panel+0x220,'Closed status list parent changed')
        if saved and saved.identity==s.identity then return end
        self.restore();assert(b.valid(s.identity),'Closed status HUD changed')
        local before=assert(b.get_opacity(address),'Closed status opacity unavailable')
        b.set_opacity(address,0)
        saved={identity=s.identity,address=address,before=before,applied=assert(b.get_opacity(address))}
    end
    return self
end
local function cooldown_dock(b,scope,input)
    local ffi=require('ffi')
    local init=ffi.cast('void (*)(uintptr_t, uint32_t)',b.base+0x1446840)
    local create=ffi.cast('void (*)(uintptr_t, uint64_t, uint64_t, uint64_t, int32_t, uint32_t)',b.base+0x1839520)
    local tick=ffi.cast('void (*)(uintptr_t, float, uint32_t, uintptr_t)',b.base+0x1839fd0)
    local attach=ffi.cast('void (*)(uintptr_t, uintptr_t)',b.base+0x144c5c0)
    local finish=ffi.cast('void (*)(uintptr_t)',b.base+0x144c2c0)
    local visible=ffi.cast('void (*)(uintptr_t, uint8_t)',b.base+0x144cfb0)
    local order=ffi.cast('void (*)(uintptr_t, uint32_t)',b.base+0x14491f0)
    local opacity=ffi.cast('void (*)(uintptr_t, float)',b.base+0x1448ad0)
    local model=cooldown_dock_model()
    local timer_text=cooldown_dock_text(b)
    local storage,address,identity,parent,snapshot
    local retired,drawn={},{}
    -- Constructor placement of each tile's count badge, so the overview can keep
    -- the game's own corner badge and backing.
    local badge_home={}
    local self={}
    local sampled_signature,timer_text_key
    local function owned() return address and b.valid(identity) and b.pointer(address+0xf0)==parent end
    function self.hide()
        timer_text.hide()
        if not snapshot and not self.shown and #model.order==0 then return end
        if self.shown and owned() then
            for i=1,16 do if drawn[i] then visible(address+0x110+(i-1)*0x1500,0) end end
            visible(address,0)
        end
        model.reset();snapshot=nil;drawn={};self.shown=false;sampled_signature=nil
    end
    function self.sample(s,now)
        if self.closed then return end
        snapshot=s
        local parts={tostring(s and s.identity),tostring(s and s.dock_y),tostring(radial.full_color),tostring(radial.cooldown_timer),tostring(radial.cooldown_display)}
        for _,row in ipairs(s and s.rows or {}) do
            if cooldown_dock_timed(row,radial.track_unavailable) then
                parts[#parts+1]=tostring(row.entry)..':'..tostring(row.kind)..':'..tostring(row.unavailable and 'unavailable' or row.timer_kind)
            end
        end
        if s and s.stamina_bounds then
            local bar=s.stamina_bounds;parts[#parts+1]=bar.left..':'..bar.right..':'..bar.bottom..':'..bar.top
        end
        if s and s.health_bounds then
            local bar=s.health_bounds;parts[#parts+1]=bar.left..':'..bar.bottom
        end
        local signature=table.concat(parts,'|')
        if signature~=sampled_signature or not self.next_sample or now>=self.next_sample then
            model.sample(s,now,radial.track_unavailable);self.next_sample=now+250
        end
        if signature~=sampled_signature then
            sampled_signature=signature;self.animate_until=now+350;self.settled=false
        end
    end
    function self.draw(now,hud_visible)
        if self.closed then return end
        local display_style=radial.cooldown_display or 1
        if self.display_style~=display_style then
            -- A style owns its whole retained GUI, including headings/panels.
            -- Retire it explicitly before the idle gate or timer-Off paths can
            -- skip label drawing; the new style starts with a clean GUI.
            timer_text.hide();self.timer_error=nil;timer_text_key=nil
            self.display_style=display_style;self.settled=false
        end
        if hud_visible==false then
            timer_text.hide()
            if self.shown and owned() then visible(address,0)end
            self.shown=false;self.settled=false
            return
        end
        local timer_due=not self.next_tick or now>=self.next_tick
        if self.animate_until and now>self.animate_until and self.shown and self.settled and not timer_due then return end
        local s=snapshot
        if not s or not s.dock_parent then self.hide();return end
        if #model.order==0 then self.hide();return end
        if address and (identity~=s.identity or parent~=s.dock_parent or not owned()) then
            if b.read(address+0xf0,8)~=string.rep('\0',8) then
                assert(#retired<8,'Too many cooldown dock HUD generations; restart game')
                retired[#retired+1]=storage
            end
            address,storage=nil,nil;drawn={};self.shown=false
        end
        local overview=radial.cooldown_display==2
        -- Compact row needs the health bar; without it the normal dock is used.
        local row=radial.cooldown_display==3 and s.health_bounds or nil
        local items,divider,panels=model.layout(now,s.dock_y,overview,radial.short_status_placement,radial.brief_timer_limit,s.dock_below_y,radial.balance_separated_dock,s.stamina_bounds,row)
        local label_key=tostring(s.identity)..':'..tostring(radial.cooldown_timer)..':'..tostring(overview)..':'..tostring(row~=nil)
        -- Compact row: timers below the tiles (or off), never the large style; no
        -- inside backdrop, so the native charge badge stays uncovered.
        local timer_position=overview and 5 or row and (radial.cooldown_timer==1 and 1 or 3) or radial.cooldown_timer
        local timer_style=row and 1 or radial.short_timer_style
        if timer_text_key~=label_key then timer_text_key=label_key;self.timer_error=nil end
        local function draw_labels()
        if not self.timer_error then
            local ok,why=pcall(timer_text.draw,s,items,now,timer_position,timer_style,radial.brief_timer_limit,divider,panels)
            if not ok then timer_text.hide();self.timer_error=tostring(why)end
        end
        end
        local changed=not self.shown or timer_due
        for i=1,16 do
            local item,old=items[i],drawn[i]
            if item then
                local signature=item.key..':'..item.phase..':'..tostring(overview)..':'..tostring(item.below_stamina)..':'..tostring(item.compact_row)
                if not old or old.signature~=signature or old.x~=item.x or old.y~=item.y or old.alpha~=item.alpha then changed=true end
            elseif old then changed=true end
        end
        self.settled=true
        for _,item in ipairs(items) do
            if item.x~=item.target_x or item.y~=item.target_y or item.alpha<1 then self.settled=false end
        end
        if not changed then draw_labels();return end
        -- A cached snapshot can outlive its HUD. Validate its viewport before
        -- pushing the context or constructing/attaching any native child.
        if s.dock_parent ~= s.identity+0x258 or not b.valid(s.identity) then
            self.hide()
            return
        end
        scope.context_scope(s.dock_parent,function(resource)
            if not address then
                storage=ffi.new('uint8_t[?]',0x15150)
                address=math.floor((tonumber(ffi.cast('uintptr_t',storage))+31)/16)*16
                identity,parent=s.identity,s.dock_parent
                init(address,1);b.set(address,'size',{0,0});b.set(address,'anchor',{0.5,0})
                b.set(address,'pivot',{0.5,0});b.set(address,'position',{0,0})
                assert(b.pointer(address+0xf8)==resource,'Dock resource context mismatch')
                for i=1,16 do
                    local icon=address+0x110+(i-1)*0x1500
                    create(icon,0,0,0,0x22b,0)
                    local badge=icon+0x920
                    local anchor,pivot,position=b.get(badge,'anchor'),b.get(badge,'pivot'),b.get(badge,'position')
                    badge_home[i]=anchor and pivot and position and {anchor=anchor,pivot=pivot,position=position} or nil
                    local size=assert(b.get(icon,'size'),'Native tile size unavailable')
                    assert(size[1]>0 and size[2]>0,'Invalid native tile dimensions')
                    local pixels=(overview or row) and 32 or 48
                    b.set(icon,'scale',{pixels/size[1],pixels/size[2]});b.set(icon,'pivot',{0.5,0.5})
                    b.set(icon,'anchor',{0,0});order(icon,0x22b)
                    attach(address,icon);finish(address)
                end
                attach(parent,address);finish(parent)
            end
            assert(identity==s.identity and parent==s.dock_parent and b.pointer(address+0xf0)==parent,'Cooldown dock ownership mismatch')
            for i=1,16 do
                local icon=address+0x110+(i-1)*0x1500
                assert(b.pointer(icon+0xf0)==address,'Cooldown dock child ownership changed')
                local item=items[i];local old=drawn[i]
                if item then
                    local signature=item.key..':'..item.phase..':'..tostring(overview)..':'..tostring(item.below_stamina)..':'..tostring(item.compact_row)
                    local denominator=old and old.denominator
                    local large=not item.compact_row and radial.short_timer_style==2 and(item.phase=='incoming'or (item.row.timer_seconds or math.huge)<=(radial.brief_timer_limit or 10))
                    -- The overview keeps the native corner badge; other layouts move it aside.
                    local charge_side=(overview or item.compact_row) and 'native' or item.below_stamina and 'left' or(not large and radial.cooldown_timer==3 and 'above'or 'below')
                    local charge_key=signature..':'..charge_side
                    if (not old and item.below_stamina)or(old and old.signature~=signature)then
                        local size=assert(b.get(icon,'size'));local pixels=(overview or item.below_stamina or item.compact_row)and 32 or 48
                        b.set(icon,'scale',{pixels/size[1],pixels/size[2]})
                    end
                    if timer_due or not old or old.signature~=signature then
                        local row=item.row
                        assert(row and row.dock_payload and row.entry,'Native dock record unavailable')
                        ffi.cast('uint32_t *',icon+0x14b8)[0]=row.entry
                        tick(icon,0.25,item.phase=='incoming' and 3 or item.phase=='unavailable' and 5 or 4,row.dock_payload)
                        -- Native initialization can reset the span. Restore the game's
                        -- original denominator afterwards, then refresh without elapsed time.
                        if item.phase~='unavailable' then
                        denominator=assert(b.read(row.dock_source+0x14c4,4),'Native tile timer span unavailable')
                        if not old or old.signature~=signature or old.denominator~=denominator then
                            ffi.copy(ffi.cast('void *',icon+0x14c4),denominator,4)
                            tick(icon,0,item.phase=='incoming' and 3 or item.phase=='unavailable' and 5 or 4,row.dock_payload)
                        end
                        local span=tonumber(ffi.cast('float *',icon+0x14c4)[0])
                        span=span==span and span>0 and span<=86400 and span or 0
                        item.cooldown_span=math.max(span,item.row.timer_seconds,item.cooldown_span or 0)
                        end
                    end
                    if timer_due or not old or old.charge_key~=charge_key then
                        -- Native tile constructor owns the count group at +920,
                        -- its two backing sprites and the count text at +CE0.
                        local badge=icon+0x920
                        assert(b.pointer(badge+0xf0)==icon,'Dock charge group ownership changed')
                        local count=tonumber(ffi.cast('uint32_t *',icon+0x14bc)[0])
                        if charge_side=='native' then
                            -- Constructor placement; the native tick shows and styles
                            -- the badge, its backing and the count itself.
                            local home=badge_home[i]
                            if home and(not old or old.charge_key~=charge_key)then
                                b.set(badge,'anchor',home.anchor);b.set(badge,'pivot',home.pivot);b.set(badge,'position',home.position)
                            end
                        else
                        if not old or old.charge_key~=charge_key or old.charge_count~=count then
                            b.set(badge,'anchor',{0.5,0.5});b.set(badge,'pivot',{0.5,0.5})
                            b.set(badge,'position',charge_side=='left'and{-36,0}or{0,charge_side=='above'and 37 or -37})
                        end
                        -- Native tick recolors/reveals these children. Suppress
                        -- AFTER it runs, at its existing bounded 4 Hz cadence.
                        opacity(icon+0xa30,0);opacity(icon+0xb88,0);opacity(icon+0xce0,0)
                        end
                        -- Native count cache, witnessed by 183AEF1's count-label
                        -- formatter. Read only our constructed/owned tile. No ASS
                        -- label is drawn while the native badge shows the count.
                        item.charge_count=charge_side~='native' and item.phase=='cooldown' and count>0 and count<=99 and count or nil
                        item.charge_side=charge_side
                        if old then old.charge_count=count end
                    end
                    local size=assert(b.get(icon,'size'),'Native tile size unavailable')
                    assert(size[1]>0 and size[2]>0,'Invalid native tile dimensions')
                    local pixels=(overview or item.below_stamina or item.compact_row)and 32 or 48
                    b.set(icon,'scale',{pixels/size[1],pixels/size[2]})
                    local position=timer_due and b.get(icon,'position') or nil
                    if not old or old.x~=item.x or old.y~=item.y or (position and (position[1]~=item.x or position[2]~=item.y)) then
                        b.set(icon,'position',{item.x,item.y})
                    end
                    if not old or old.alpha~=item.alpha then opacity(icon,item.alpha) end
                    if not old then visible(icon,1) end
                    local retained=old or {}
                    retained.signature,retained.x,retained.y=signature,item.x,item.y
                    retained.alpha,retained.denominator=item.alpha,denominator
                    retained.charge_key=charge_key
                    retained.charge_count=tonumber(ffi.cast('uint32_t *',icon+0x14bc)[0])
                    drawn[i]=retained
                elseif old then visible(icon,0);drawn[i]=nil
                elseif not drawn.initialized then visible(icon,0) end
            end
            self.next_tick=now+250
            drawn.initialized=true
            if not self.shown then visible(address,1);self.shown=true end
        end)
        draw_labels()
    end
    function self.close()
        -- Closing is terminal. Old update/menu closures must never resurrect
        -- a GUI after loader cleanup has relinquished this owner.
        self.closed=true
        timer_text.close()
        self.hide()
        local ok,why=b.release_owned_ui(storage,address,identity,parent,retired)
        if not ok then return false,why end
        storage,address,identity,parent=nil,nil,nil,nil
        for i=#retired,1,-1 do retired[i]=nil end
        return true
    end
    return self
end

return {cooldown_bounds=cooldown_bounds,cooldown_dock_timed=cooldown_dock_timed,cooldown_dock_model=cooldown_dock_model,cooldown_dock_text=cooldown_dock_text,cooldown_closed_notices=cooldown_closed_notices,cooldown_dock=cooldown_dock}
