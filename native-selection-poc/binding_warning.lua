-- Read only the recognized MBM v3 registry/header, as the MCM binding page does.
local function dbf_binding_reader(host)
    local function up(fn,wanted)
        if type(fn)~='function' or not debug or not debug.getupvalue then return end
        for i=1,64 do local name,value=debug.getupvalue(fn,i);if not name then return end;if name==wanted then return value end end
    end
    if type(host)~='table' or host.api~=1 or type(host.version)~='number' or host.version<3 then return end
    local public=type(host.binding_info)=='function' and type(host.binding)=='function'
    local state=up(host.register_binding,'state')
    local header=up(host.is_down,'live_header')
    local read,words=up(header,'read_words'),up(header,'words')
    if type(state)~='table' or type(state.registry)~='table' or up(host.is_down,'state')~=state
        or up(header,'state')~=state or type(read)~='function' or (type(words)~='cdata' and type(words)~='table') then
        if public then return function(id)
            local info=host.binding_info(id)
            if info and info.backend=='extended' then local values=host.binding(id);if type(values)=='table' then return #values>0 end end
        end end
        return
    end
    return function(id)
        if public then local info=host.binding_info(id)
            if info and info.backend=='extended' then local values=host.binding(id);if type(values)=='table' then return #values>0 end;return end
        end
        if not state.build_rows then return end
        local record=state.registry[id];if type(record)~='table' then return end
        local bucket,count=header(record);count=tonumber(count)
        if not bucket or not count or count<0 or count>16 or count%1~=0 then return end
        if not read(bucket,8) or tonumber(words[0])~=record.code or tonumber(words[1])~=count then return end
        return count>0
    end
end
local function dbf_binding_warning_view()
    local gui,world,sr,text_id,background,signature
    local self={}
    local function live()
        if not sr or not world then return false end
        for _,w in pairs(sr.Application.worlds() or {}) do if w==world then return true end end
        return false
    end
    function self.hide()
        if gui and live() then pcall(sr.World.destroy_gui,world,gui) end
        gui,world,text_id,background,signature=nil,nil,nil,nil,nil
    end
    function self.show(text)
        if not text then self.hide();return end
        local current=rawget(_G,'stingray')
        if type(current)~='table' or not current.Gui or not current.World or not current.Application then return end
        if sr~=current or (gui and not live()) then self.hide();sr=current end
        sr=current
        local G,A=sr.Gui,sr.Application
        local w,h=G.resolution();if not w or not h or w<=0 or h<=0 then return end
        local next_signature=text..':'..w..':'..h
        if gui and signature==next_signature then return end
        if not gui then
            local main=A.main_world();world=main
            for _,candidate in pairs(A.worlds() or {}) do if candidate~=main then world=candidate;break end end
            if not world then return end
            gui=sr.World.create_screen_gui(world,'scale',1,1)
            if not gui then return end
        end
        if text_id then G.destroy_text(gui,text_id) end
        if background then G.destroy_rect(gui,background) end
        local font='core/performance_hud/debug'
        local size=math.max(14,math.min(20,w/75))
        local width=math.min(w-32,#text*size*0.62+28)
        local x=(w-width)/2
        background=G.rect(gui,sr.Vector3(x,16,950),sr.Vector2(width,size+20),sr.Color(210,15,15,15))
        text_id=G.text(gui,text,font,size,font,sr.Vector3(x+14,26,951),sr.Color(255,255,220,80))
        signature=next_signature
    end
    return self
end
local function dbf_binding_warning(view,reader_factory)
    view=view or dbf_binding_warning_view();reader_factory=reader_factory or dbf_binding_reader
    local owner,reader,next_check,requirements
    local self={}
    function self.hide() view.hide();next_check=nil end
    function self.step(enabled,host,ids,required,now)
        if not enabled then self.hide();return end
        local key=table.concat(required,',')
        if host~=owner or key~=requirements then
            owner,requirements=host,key;reader=reader_factory(host);next_check=nil
        end
        -- MBM exposes no mapping-change subscription. Check at most twice a second,
        -- reading only the three registered DBF action headers; unknown is not unbound.
        if next_check and now<next_check then return end
        next_check=now+500
        local missing={}
        for _,name in ipairs(required) do
            local ok,bound=pcall(function() return reader and reader(ids[name]) end)
            if ok and bound==false then missing[#missing+1]=({next='Next',previous='Previous',confirm='Confirm'})[name] end
        end
        local message=#missing>0 and ('DBF: Bind '..table.concat(missing,' / ')..' in MODS controls.') or nil
        local ok,why=pcall(view.show,message)
        self.status=ok and message or ('Binding warning unavailable: '..tostring(why))
    end
    return self
end
