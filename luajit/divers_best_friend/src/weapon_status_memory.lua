-- Private FFI symbols prevent collisions with other addons' declarations.
local M={}
-- Every cdef, even of an already declared name, allocates C types that are never
-- freed (one shared 65536-entry table); each declaration runs once per load.
local declared={}
local function cdef_once(ffi,text)
    if not declared[text] then pcall(ffi.cdef,text);declared[text]=true end
end
function M.native()
    local ffi=require('ffi')
    cdef_once(ffi, [[
    void *dbf_hud_module(const char*) __asm__("GetModuleHandleA");
    void *dbf_hud_process(void) __asm__("GetCurrentProcess");
    int dbf_hud_read(void*,const void*,void*,size_t,size_t*) __asm__("ReadProcessMemory");
    unsigned long dbf_hud_filename(void*,char*,unsigned long) __asm__("GetModuleFileNameA");
    unsigned long dbf_hud_pid(void) __asm__("GetCurrentProcessId");
    void *dbf_hud_foreground(void) __asm__("GetForegroundWindow");
    unsigned long dbf_hud_window_pid(void*,unsigned long*) __asm__("GetWindowThreadProcessId");
    short dbf_hud_key(int) __asm__("GetAsyncKeyState");
    uint64_t dbf_hud_ticks(void) __asm__("GetTickCount64");
    ]])
    local k=ffi.load('kernel32'); local process=k.dbf_hud_process()
    local buffer=ffi.new('uint8_t[4096]');local got=ffi.new('size_t[1]')
    local file,log_size;local log_attempted=false
    local backend={
        module=function(name) local p=k.dbf_hud_module(name); if p~=nil then return tonumber(ffi.cast('uintptr_t',p)) end end,
        read=function(address,size)
            if address<65536 or address+size>=2^47 or size<1 or size>4096 then return nil end
            got[0]=0
            if k.dbf_hud_read(process,ffi.cast('const void*',address),buffer,size,got)==0 or tonumber(got[0])~=size then return nil end
            return ffi.string(buffer,size)
        end
    }
    function backend.clock()return tonumber(k.dbf_hud_ticks())/1000 end
    local input=ffi.load('user32');local window_pid=ffi.new('unsigned long[1]')
    local input_probe={polls=0,focused=0,f6_high=0,f6_tap=0,right_high=0,right_tap=0}
    local process_id=tonumber(k.dbf_hud_pid())
    local frame_focused
    local function input_focused()
        local loader=rawget(_G,'LiveLuaLoader');local service=loader and loader.input_service
        if service and service.status then local ok,state=pcall(service.status);if not ok or state.owner or state.pending_restore then return false end end
        local window=input.dbf_hud_foreground();if window==nil then return false end
        input.dbf_hud_window_pid(window,window_pid)
        return tonumber(window_pid[0])==process_id
    end
    function backend.begin_editor_input()frame_focused=input_focused()end
    function backend.end_editor_input()frame_focused=nil end
    function backend.editor_key(code)
        local focused=frame_focused
        if focused==nil then focused=input_focused()end
        local state=tonumber(input.dbf_hud_key(code))
        if code==117 or code==39 then
            if code==117 then input_probe.polls=input_probe.polls+1;if focused then input_probe.focused=input_probe.focused+1 end end
            local name=code==117 and 'f6' or 'right'
            if state<0 then input_probe[name..'_high']=input_probe[name..'_high']+1 end
            if state%2~=0 then input_probe[name..'_tap']=input_probe[name..'_tap']+1 end
        end
        return focused and state<0
    end
    function backend.editor_input_diagnostic(active)
        backend.log(string.format('EDITOR_INPUT active=%s polls=%d focused=%d f6_held=%d f6_taps=%d right_held=%d right_taps=%d',
            tostring(active),input_probe.polls,input_probe.focused,input_probe.f6_high,input_probe.f6_tap,input_probe.right_high,input_probe.right_tap))
        for key in pairs(input_probe) do input_probe[key]=0 end
    end
    function backend.log(line)
        if not log_attempted then
            log_attempted=true
            local buf=ffi.new('char[4096]');local n=tonumber(k.dbf_hud_filename(nil,buf,4096))
            if n and n>0 and n<4096 then
                local exe=ffi.string(buf,n):gsub('\\','/')
                local root=exe:match('^(.*)/[Bb][Ii][Nn]/[^/]+$')
                if root then backend.log_path=root..'/DBF-HUD.log';file=io.open(backend.log_path,'w') end
            end
            log_size=0
        end
        if file and log_size<512*1024 then
            file:write(line..'\n');file:flush();log_size=log_size+#line+1
        end
    end
    local function legacy_tuning_path()
        local buf=ffi.new('char[4096]');local n=tonumber(k.dbf_hud_filename(nil,buf,4096))
        assert(n>0 and n<4096,'executable path unavailable')
        local root=ffi.string(buf,n):gsub('\\','/'):match('^(.*)/[Bb][Ii][Nn]/[^/]+$')
        assert(root,'game installation root unavailable')
        return root..'/DBF-HUD-tuning.lua'
    end
    local function config_folder()
        local root=assert(os.getenv('LOCALAPPDATA'),'Local AppData unavailable')..'/DBF'
        cdef_once(ffi,'int CreateDirectoryA(const char*, void*);')
        k.CreateDirectoryA(root,nil)
        return root
    end
    local function tuning_path()return config_folder()..'/DBF-HUD-tuning.lua' end
    local function read_config(name,legacy_name)
        local path=config_folder()..'/'..name
        local f=io.open(path,'r');local migrate=false
        if not f then
            local old=legacy_tuning_path():gsub('DBF%-HUD%-tuning.lua$',name)
            f=io.open(old,'r')
            if not f and legacy_name then f=io.open(old:gsub(name:gsub('([^%w])','%%%1')..'$',legacy_name),'r') end
            migrate=f~=nil
        end
        if not f then return nil end
        local body=f:read(65537);f:close();assert(#body<=65536,'config file too large')
        local chunk=assert(loadstring(body,'@'..path));setfenv(chunk,{})
        local values=chunk();assert(type(values)=='table','config must return a table')
        if migrate then
            local out=assert(io.open(path..'.tmp','w'));assert(out:write(body));assert(out:close())
            assert(os.rename(path..'.tmp',path));backend.log('CONFIG migrated '..name..' to Local AppData')
        end
        backend.log('CONFIG reading '..path..' ('..#body..' bytes)')
        return values
    end
    function backend.camera_log_path() return legacy_tuning_path():gsub('DBF%-HUD%-tuning.lua$','DBF-HUD-camera.log') end
    function backend.camera_request()
        local path=legacy_tuning_path():gsub('DBF%-HUD%-tuning.lua$','DBF-HUD-camera-request.txt')
        local file=io.open(path,'r');if not file then return nil end
        local label=file:read(65);file:close();assert(os.remove(path),'camera request acknowledgement failed')
        assert(#label<=64 and label:match('^[%w_%-]+%s*$'),'invalid camera snapshot label')
        return label:match('^[%w_%-]+')
    end
    function backend.read_tuning()
        return read_config('DBF-HUD-tuning.lua','AstraAmmo-tuning.lua')
    end
    function backend.read_weapon_offsets()
        return read_config('DBF-HUD-weapon-offsets.lua')
    end
    function backend.write_tuning(body)
        local path=tuning_path();local tmp=path..'.tmp'
        local f=assert(io.open(tmp,'w'));local ok,err=f:write(body);local closed,cerr=f:close()
        assert(ok and closed,err or cerr)
        -- Windows rename cannot replace an existing file; keep a recoverable backup.
        local previous=io.open(path,'r')
        if previous then previous:close();os.remove(path..'.bak');assert(os.rename(path,path..'.bak')) end
        local moved,why=os.rename(tmp,path)
        if not moved then os.rename(path..'.bak',path);error(why) end
        return path
    end
    local function preset_folder()
        local root=assert(os.getenv('LOCALAPPDATA'),'Local AppData unavailable')..'/DBF'
        cdef_once(ffi,'int CreateDirectoryA(const char*, void*);')
        local win=ffi.load('kernel32');win.CreateDirectoryA(root,nil)
        root=root..'/Presets';win.CreateDirectoryA(root,nil)
        return root
    end
    local seeded_presets=false
    local find_first,find_next
    function backend.list_presets()
        if not seeded_presets and HUD.bundled_defaults then
            local folder=preset_folder()
            for filename,body in pairs(HUD.bundled_defaults.presets) do
                local path=folder..'/'..filename
                local existing=io.open(path,'rb')
                if existing then existing:close() else
                    local file=assert(io.open(path,'wb'));assert(file:write(body));file:close()
                end
            end
            seeded_presets=true
        end
        cdef_once(ffi,[[typedef struct { unsigned long attributes; unsigned long times[6]; unsigned long sizeHigh,sizeLow,reserved0,reserved1; char name[260]; char alternate[14]; } DBF_PRESET_FIND_DATA;
        void* FindFirstFileA(const char*, DBF_PRESET_FIND_DATA*); int FindNextFileA(void*,DBF_PRESET_FIND_DATA*); int FindClose(void*);]])
        local win=ffi.load('kernel32');local data=ffi.new('DBF_PRESET_FIND_DATA[1]')
        local mask=preset_folder()..'/DBF-HUD-preset-*.*'
        -- Anonymous function types are new C types on every parse; cast once.
        find_first=find_first or ffi.cast('void *(*)(const char *, void *)',win.FindFirstFileA)
        find_next=find_next or ffi.cast('int (*)(void *, void *)',win.FindNextFileA)
        local handle=find_first(mask,data);local names={}
        if handle==ffi.cast('void*',-1) then return names end
        repeat local filename=ffi.string(data[0].name);local name=filename:match('^DBF%-HUD%-preset%-(.+)%.layout$') or filename:match('^DBF%-HUD%-preset%-(.+)%.lua$')
            if name and #name<=48 and name:match('^[%w _-]+$') then local exists=false;for _,v in ipairs(names)do if v==name then exists=true end end;if not exists then names[#names+1]=name end end
        until find_next(handle,data)==0
        win.FindClose(handle);table.sort(names);return names
    end
    function backend.read_preset(name)
        assert(type(name)=='string' and #name<=48 and name:match('^[%w _-]+$'),'Invalid preset filename')
        local stem=name:gsub('^%s+',''):gsub('%s+$','');assert(#stem>0,'Preset name is empty')
        local path=preset_folder()..'/DBF-HUD-preset-'..stem..'.layout'
        local f=io.open(path,'rb') or io.open(path:gsub('%.layout$','.lua'),'rb');assert(f,'Preset not found');local body=f:read(131073);f:close();assert(#body<=131072,'Preset too large')
        local chunk=assert(loadstring(body,'DBF-HUD preset'));setfenv(chunk,{})
        local value=chunk();assert(type(value)=='table' and type(value.settings)=='table' and type(value.layouts)=='table','Invalid preset format');return value
    end
    function backend.delete_preset(name)
        assert(type(name)=='string' and #name<=48 and name:match('^[%w _-]+$'),'Invalid preset filename')
        local stem=name:gsub('^%s+',''):gsub('%s+$','');assert(#stem>0,'Preset name is empty')
        local base=preset_folder()..'/DBF-HUD-preset-'..stem
        local found=false
        for _,extension in ipairs({'.layout','.lua'})do
            local path=base..extension;local f=io.open(path,'rb')
            if f then f:close();assert(os.remove(path));found=true end
        end
        assert(found,'Preset not found');return true
    end
    function backend.write_preset(name,body)
        assert(type(name)=='string' and #name<=48 and name:match('^[%w _-]+$'),'Invalid preset filename')
        local stem=name:gsub('^%s+',''):gsub('%s+$','');assert(#stem>0,'Preset name is empty')
        assert(not stem:upper():match('^(CON)$') and not stem:upper():match('^(NUL)$'),'Reserved filename')
        local path=preset_folder()..'/DBF-HUD-preset-'..stem..'.layout'
        local f=assert(io.open(path..'.tmp','wb'));assert(f:write(body));assert(f:close())
        local existing=io.open(path,'rb');local had_previous=existing~=nil
        if existing then
            existing:close();os.remove(path..'.bak');assert(os.rename(path,path..'.bak'))
        end
        local moved,why=os.rename(path..'.tmp',path)
        if not moved then if had_previous then os.rename(path..'.bak',path)end;error(why)end
        return path
    end
    function backend.write_weapon_offsets(body)
        assert(type(body)=='string' and #body<=65536,'weapon offsets file too large')
        local path=tuning_path():gsub('DBF%-HUD%-tuning.lua$','DBF-HUD-weapon-offsets.lua')
        local tmp=path..'.tmp';local f=assert(io.open(tmp,'w'))
        local ok,err=f:write(body);local closed,cerr=f:close();assert(ok and closed,err or cerr)
        local previous=io.open(path,'r')
        if previous then previous:close();os.remove(path..'.bak');assert(os.rename(path,path..'.bak')) end
        local moved,why=os.rename(tmp,path)
        if not moved then os.rename(path..'.bak',path);error(why) end
        return path
    end
    -- Read-only projection call. The caller must validate the native wrapper and
    -- camera owner immediately before use. x64 disassembly confirms explicit
    -- result buffer, camera pointer and input-vector pointer (three arguments).
    -- Native SIMD vectors require 16-byte alignment. Keep the owning allocations
    -- with this backend; derived FFI pointers alone do not retain their storage.
    local project_in_storage=ffi.new('uint8_t[32]');local project_out_storage=ffi.new('uint8_t[32]')
    backend.projection_buffers={project_in_storage,project_out_storage}
    local function aligned_vector(storage)
        local address=tonumber(ffi.cast('uintptr_t',storage))
        assert(address>=65536 and address<2^47,'projection buffer address')
        return ffi.cast('float*',math.floor((address+15)/16)*16)
    end
    local project_in=aligned_vector(project_in_storage);local project_out=aligned_vector(project_out_storage)
    -- Anonymous function signatures create a new LuaJIT CType each time they
    -- are parsed. Cache both the type and callable, rather than parsing per point.
    -- Initialize lazily so an already exhausted VM can still draw its fallback.
    local project_type,project_fn,project_call
    function backend.project_camera(fn,camera,x,y,z)
        if project_fn~=fn then
            project_type=project_type or ffi.typeof('float* (*)(float*, const void*, const float*)')
            project_call=ffi.cast(project_type,fn);project_fn=fn
        end
        project_in[0],project_in[1],project_in[2]=x,y,z
        project_call(project_out,ffi.cast('const void*',camera),project_in)
        return tonumber(project_out[0]),tonumber(project_out[1]),tonumber(project_out[2])
    end
    function backend.close() if file then file:close();file=nil end end
    return backend
end
function M.new(backend)
    local r={reads=0,bytes=0}
    function r.reset() r.reads,r.bytes=0,0 end
    function r.read(a,n)
        assert(type(a)=='number' and a==a and a%1==0 and a>=65536 and a+n<2^47,'invalid address')
        assert(n>0 and n<=4096,'invalid read size')
        r.reads,r.bytes=r.reads+1,r.bytes+n
        assert(r.reads<=512 and r.bytes<=65536,'read budget exceeded')
        local s=backend.read(a,n); assert(s and #s==n,'unreadable memory');return s
    end
    function r.u(s,o)
        local a,b,c,d=s:byte(o+1,o+4);assert(d,'short uint32');return a+b*256+c*65536+d*16777216
    end
    function r.i(s,o) local v=r.u(s,o);return v>=2^31 and v-2^32 or v end
    function r.f(s,o)
        local v=r.u(s,o);local sign=v>=2^31 and -1 or 1
        local e=math.floor(v/2^23)%256;local m=v%2^23
        assert(e~=255,'nonfinite float')
        return sign*(e==0 and m*2^-149 or (1+m/2^23)*2^(e-127))
    end
    function r.pointer(s,o)
        o=o or 0;local p=r.u(s,o)+r.u(s,o+4)*2^32
        assert(p>=65536 and p<2^47,'invalid pointer');return p
    end
    function r.p(a)return r.pointer(r.read(a,8),0)end
    function r.map(a,key,limit)
        local h=r.read(a,20);local n,empty,mult=r.u(h,8),r.u(h,12),r.u(h,16)
        if n==0 or key==empty or key==0xffffffff then return nil end
        assert(n<=limit and n>0,'invalid map capacity')
        local pow=n;while pow>1 and pow%2==0 do pow=pow/2 end
        assert(pow==1,'invalid map capacity')
        local p=r.p(a)
        -- Split multiplication keeps the low 32 bits exact under Lua doubles.
        local start=((key%65536)*(mult%65536)+((math.floor(key/65536)*(mult%65536)+(key%65536)*math.floor(mult/65536))%65536)*65536)%2^32
        for probe=0,math.min(n,128)-1 do
            local row=r.read(p+((start+probe)%n)*8,8);local k=r.u(row,0)
            if k==empty then return nil end
            if k==key then local index=r.u(row,4);if index~=0xffffffff then return index end;return nil end
        end
        error('map probe limit')
    end
    return r
end
return M
