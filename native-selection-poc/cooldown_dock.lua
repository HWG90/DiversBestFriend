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
    function self.layout(now,y,overview,placement,brief_limit,below_y,balanced)
        local result={};local n=#self.order
        local split=not overview and placement and placement>1
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
            local x=overview and -70 or (i-(n+1)/2)*60
            local target_y=overview and y+(n-i)*38 or y
            item.below_stamina=false
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
        if split and placement~=4 and main_n>0 and short_n>0 then
            local alpha=1;for _,item in ipairs(result)do alpha=math.min(alpha,item.alpha)end
            divider={x=(main_n*30+12)*(placement==2 and -1 or 1)+balance,y=y,alpha=alpha}
        end
        return result,divider
    end
    return self
end
-- Retained screen-GUI labels. No timer subscription exists; consume the dock's
-- existing timer updates and change retained text only when its value changes.
local function cooldown_dock_text(b)
    local self={};local gui,world,sr,font,identity,attempted;local labels={}
    local separator,separator_key
    local function destroy_label(label)
        if not label then return end
        sr.Gui.destroy_text(gui,label.id)
        sr.Gui.destroy_text(gui,label.shadow)
        if label.backdrop then sr.Gui.destroy_rect(gui,label.backdrop)end
    end
    local function world_live()
        if not world or not sr then return false end
        for _,candidate in pairs(sr.Application.worlds()or{})do if candidate==world then return true end end
        return false
    end
    function self.hide()
        -- A world destroys its GUI resources itself. Never pass a retired world
        -- or GUI to the engine; pcall cannot catch a native access violation.
        if gui and world_live() then pcall(sr.World.destroy_gui,world,gui)end
        gui,world,font,identity,attempted=nil,nil,nil,nil,nil;labels={};separator,separator_key=nil,nil
    end
    function self.draw(s,items,now,position,short_style,brief_limit,divider)
        local timers=position and position~=1
        local charges=false
        for _,item in ipairs(items)do if item.phase=='cooldown' and item.charge_count then charges=true;break end end
        if (not timers and not charges and not divider) or #items==0 then self.hide();return end
        local current=rawget(_G,'stingray');if not current or not b.dock_font then return end
        if sr~=current or identity~=s.identity then self.hide();sr=current;identity=s.identity end
        if gui and not world_live() then self.hide();identity=s.identity end
        if not gui then
            if attempted then return end;attempted=true
            font=b.dock_font(sr);if not font then return end
            local A,G=sr.Application,sr.Gui;world=A.main_world()
            for _,candidate in pairs(A.worlds()or{})do if candidate~=world then world=candidate;break end end
            if not world then return end
            gui=sr.World.create_screen_gui(world,'scale',1,1);if not gui then return end
            local ok,material=pcall(G.material,gui,sr.IdString64.from_hex(font.material))
            if not ok or not material then material=G.create_material(gui,sr.IdString64.from_hex(font.material))end
            if not material or sr.Material.set_texture(material,sr.IdString64.from_hex('88BAC99B00000000'),sr.IdString64.from_hex(font.atlas))==false then self.hide();attempted=true;return end
        end
        local G=sr.Gui;local width=G.resolution();local scale=(width or 1920)/1920
        for i=1,16 do
            local item,old=items[i],labels[i]
            if item and timers and item.phase~='unavailable' then
                local seconds=math.max(0,math.ceil(item.row.timer_seconds))
                local overview=position==5
                local incoming=item.phase=='incoming' or item.row.timer_kind=='incoming'
                local large=not overview and short_style==2 and (incoming or seconds<=(brief_limit or 10))
                local inside=large or position==4
                local size=math.max(14,(large and 36 or inside and 22 or 18)*scale)
                local text=large and tostring(seconds) or string.format('%d:%02d',math.floor(seconds/60),seconds%60)
                local above=position==2 and not item.below_stamina
                local x,y=b.dock_text_position(s,item.x,item.y+(inside and 0 or above and 30 or -42))
                if overview then
                    text=(incoming and 'INBOUND 'or 'COOLDOWN ')..text
                    x,y=b.dock_text_position(s,item.x+78,item.y-5)
                end
                if inside then y=y-size*.35 end
                local key=text..':'..x..':'..y..':'..item.alpha..':'..size..':'..tostring(overview)
                if not old or old.key~=key then
                    destroy_label(old)
                    local min,max=G.text_extents(gui,text,sr.IdString64.from_hex(font.font),size)
                    local extent=sr.Vector3.x(max)-sr.Vector3.x(min)
                    local backdrop
                    if overview then
                        local left,bottom=b.dock_text_position(s,item.x+22,item.y-12)
                        local right,top=b.dock_text_position(s,item.x+134,item.y+12)
                        backdrop=G.rect(gui,sr.Vector3(left,bottom,949),sr.Vector2(right-left,top-bottom),sr.Color(math.floor(item.alpha*150),0,0,0))
                    elseif inside then
                        local half=item.below_stamina and 16 or 24
                        local left,bottom=b.dock_text_position(s,item.x-half,item.y-half)
                        local right,top=b.dock_text_position(s,item.x+half,item.y+half)
                        backdrop=G.rect(gui,sr.Vector3(math.min(left,right),math.min(bottom,top),949),sr.Vector2(math.abs(right-left),math.abs(top-bottom)),sr.Color(math.floor(item.alpha*150),0,0,0))
                    end
                    local shadow_id=G.text(gui,text,sr.IdString64.from_hex(font.font),size,sr.IdString64.from_hex(font.material),sr.Vector3(x-extent/2+2*scale,y-2*scale,950),sr.Color(math.floor(item.alpha*210),0,0,0))
                    labels[i]={key=key,backdrop=backdrop,shadow=shadow_id,id=G.text(gui,text,sr.IdString64.from_hex(font.font),size,sr.IdString64.from_hex(font.material),sr.Vector3(x-extent/2,y,951),sr.Color(math.floor(item.alpha*255),255,255,255))}
                end
            elseif old then destroy_label(old);labels[i]=nil end
            local old_charge=labels[i+16]
            if item and item.phase=='cooldown' and item.charge_count then
                local text=tostring(item.charge_count);local size=18*scale
                local side=item.charge_side
                local x,y=b.dock_text_position(s,item.x+(side=='left'and -36 or 0),item.y+(side=='above'and 37 or side=='left'and 0 or -37))
                y=y-size*.35
                local key=text..':'..x..':'..y..':'..item.alpha..':'..size
                if not old_charge or old_charge.key~=key then
                    destroy_label(old_charge)
                    local min,max=G.text_extents(gui,text,sr.IdString64.from_hex(font.font),size)
                    local extent=sr.Vector3.x(max)-sr.Vector3.x(min)
                    local shadow=G.text(gui,text,sr.IdString64.from_hex(font.font),size,sr.IdString64.from_hex(font.material),sr.Vector3(x-extent/2+2*scale,y-2*scale,950),sr.Color(math.floor(item.alpha*210),0,0,0))
                    labels[i+16]={key=key,shadow=shadow,id=G.text(gui,text,sr.IdString64.from_hex(font.font),size,sr.IdString64.from_hex(font.material),sr.Vector3(x-extent/2,y,951),sr.Color(math.floor(item.alpha*255),255,255,255))}
                end
            elseif old_charge then destroy_label(old_charge);labels[i+16]=nil end
        end
        if divider then
            local left,bottom=b.dock_text_position(s,divider.x-1,divider.y-24)
            local right,top=b.dock_text_position(s,divider.x+1,divider.y+24)
            local key=left..':'..bottom..':'..right..':'..top..':'..divider.alpha
            if key~=separator_key then
                if separator then G.destroy_rect(gui,separator)end
                separator=G.rect(gui,sr.Vector3(left,bottom,952),sr.Vector2(right-left,top-bottom),sr.Color(math.floor(divider.alpha*210),255,255,255))
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
        if saved and b.valid(saved.identity)and b.get_opacity(saved.address)==saved.applied then
            -- Closed native lists can already have alpha zero. Replaying that
            -- value after the open transition makes the entire menu invisible.
            b.set_opacity(saved.address,open and saved.before==0 and 1 or saved.before)
        end
        saved=nil
    end
    function self.step(s)
        if not s or s.open~=false then self.restore(s and s.open==true);return end
        local address=s.identity+0x24e340+0x146dc0+0x1040
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
        snapshot=s
        local parts={tostring(s and s.identity),tostring(s and s.dock_y),tostring(radial.full_color),tostring(radial.cooldown_timer),tostring(radial.cooldown_display)}
        for _,row in ipairs(s and s.rows or {}) do
            if cooldown_dock_timed(row,radial.track_unavailable) then
                parts[#parts+1]=tostring(row.entry)..':'..tostring(row.kind)..':'..tostring(row.unavailable and 'unavailable' or row.timer_kind)
            end
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
        local items,divider=model.layout(now,s.dock_y,overview,radial.short_status_placement,radial.brief_timer_limit,s.dock_below_y,radial.balance_separated_dock)
        local label_key=tostring(s.identity)..':'..tostring(radial.cooldown_timer)..':'..tostring(overview)
        if timer_text_key~=label_key then timer_text_key=label_key;self.timer_error=nil end
        local function draw_labels()
        if not self.timer_error then
            local ok,why=pcall(timer_text.draw,s,items,now,overview and 5 or radial.cooldown_timer,radial.short_timer_style,radial.brief_timer_limit,divider)
            if not ok then timer_text.hide();self.timer_error=tostring(why)end
        end
        end
        local changed=not self.shown or timer_due
        for i=1,16 do
            local item,old=items[i],drawn[i]
            if item then
                local signature=item.key..':'..item.phase..':'..tostring(overview)..':'..tostring(item.below_stamina)
                if not old or old.signature~=signature or old.x~=item.x or old.y~=item.y or old.alpha~=item.alpha then changed=true end
            elseif old then changed=true end
        end
        self.settled=true
        for _,item in ipairs(items) do
            if item.x~=item.target_x or item.y~=item.target_y or item.alpha<1 then self.settled=false end
        end
        if not changed then draw_labels();return end
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
                    create(icon,0ULL,0ULL,0ULL,0x22b,0)
                    local size=assert(b.get(icon,'size'),'Native tile size unavailable')
                    assert(size[1]>0 and size[2]>0,'Invalid native tile dimensions')
                    local pixels=overview and 32 or 48
                    b.set(icon,'scale',{pixels/size[1],pixels/size[2]});b.set(icon,'pivot',{0.5,0.5})
                    b.set(icon,'anchor',{0,0});order(icon,0x22b)
                    attach(address,icon);finish(address)
                end
                attach(parent,address);finish(parent)
            end
            assert(owned(),'Cooldown dock ownership mismatch')
            for i=1,16 do
                local icon=address+0x110+(i-1)*0x1500
                assert(b.pointer(icon+0xf0)==address,'Cooldown dock child ownership changed')
                local item=items[i];local old=drawn[i]
                if item then
                    local signature=item.key..':'..item.phase..':'..tostring(overview)..':'..tostring(item.below_stamina)
                    local denominator=old and old.denominator
                    local large=radial.short_timer_style==2 and(item.phase=='incoming'or (item.row.timer_seconds or math.huge)<=(radial.brief_timer_limit or 10))
                    local charge_side=(overview or item.below_stamina)and 'left'or(not large and radial.cooldown_timer==3 and 'above'or 'below')
                    local charge_key=signature..':'..charge_side
                    if (not old and item.below_stamina)or(old and old.signature~=signature)then
                        local size=assert(b.get(icon,'size'));local pixels=(overview or item.below_stamina)and 32 or 48
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
                        if not old or old.charge_key~=charge_key or old.charge_count~=count then
                            b.set(badge,'anchor',{0.5,0.5});b.set(badge,'pivot',{0.5,0.5})
                            b.set(badge,'position',charge_side=='left'and{-36,0}or{0,charge_side=='above'and 37 or -37})
                        end
                        -- Native tick recolors/reveals these children. Suppress
                        -- AFTER it runs, at its existing bounded 4 Hz cadence.
                        opacity(icon+0xa30,0);opacity(icon+0xb88,0);opacity(icon+0xce0,0)
                        -- Native count cache, witnessed by 183AEF1's count-label
                        -- formatter. Read only our constructed/owned tile.
                        item.charge_count=item.phase=='cooldown' and count>0 and count<=99 and count or nil
                        item.charge_side=charge_side
                        if old then old.charge_count=count end
                    end
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
        self.hide()
        local ok,why=b.release_owned_ui(storage,address,identity,parent,retired)
        if not ok then return false,why end
        storage,address,identity,parent=nil,nil,nil,nil
        for i=#retired,1,-1 do retired[i]=nil end
        return true
    end
    return self
end
