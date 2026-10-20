local f=assert(io.open('native-selection-poc/binding_warning.lua'));local source=f:read('*a');f:close()
local factory,make_reader,make_view=assert(loadstring(source..'\nreturn dbf_binding_warning,dbf_binding_reader,dbf_binding_warning_view'))()
local messages,reads,hidden={},0,0
local bound={n=false,p=true,c=false}
local view={show=function(text)messages[#messages+1]=text or '';end,hide=function()hidden=hidden+1 end}
local host={};local ids={next='n',previous='p',confirm='c'}
local w=factory(view,function()return function(id)reads=reads+1;return bound[id]end end)
w.step(true,host,ids,{'next','previous','confirm'},0)
assert(messages[1]:find('Next / Confirm',1,true) and not messages[1]:find('Previous',1,true))
for i=1,499 do w.step(true,host,ids,{'next','previous','confirm'},i) end
assert(reads==3 and #messages==1,'bounded header checks')
bound.n,bound.c=true,true;w.step(true,host,ids,{'next','previous','confirm'},500);assert(messages[2]=='')
bound.c=false;w.step(true,host,ids,{},501);assert(messages[3]=='','release selection requires no confirm')
w.step(false,host,ids,{'confirm'},502);assert(hidden==1)
local unknown=factory(view,function()return function()return nil end end)
unknown.step(true,host,ids,{'confirm'},0);assert(messages[#messages]=='','unknown is not unbound')
-- Real upvalue names/signature matching; header count is authoritative.
local state={registry={c={code=123}},build_rows=true}
local words={};local count=0
local function read_words()words[0],words[1]=123,count;return true end
local function live_header(record)if state and read_words and words and record then return 4096,count end end
local function register_binding()return state end
local function is_down()if state then return live_header(state.registry.c)end end
local provider={api=1,version=3,register_binding=register_binding,is_down=is_down}
local reader=assert(make_reader(provider));assert(reader('c')==false)
count=1;assert(reader('c')==true)
state.build_rows=false;assert(reader('c')==nil)
assert(make_reader({api=1,version=3,register_binding=function()end,is_down=function()end})==nil)
-- Persistent screen commands are reused and cleared after binding fixes.
local calls,destroyed=0,0;local current_world={}
local env=setmetatable({}, {__index=_G});env._G=env
env.stingray={Application={worlds=function()return {current_world}end,main_world=function()return current_world end},
 World={create_screen_gui=function()calls=calls+1;return {} end,destroy_gui=function()destroyed=destroyed+1 end},
 Vector3=function(...)return {...}end,Vector2=function(...)return {...}end,Color=function(...)return {...}end,
 Gui={resolution=function()return 1920,1080 end,rect=function()calls=calls+1;return 1 end,text=function(_,text)assert(text:find('DBF',1,true));calls=calls+1;return 2 end,
 destroy_text=function()end,destroy_rect=function()end}}
local chunk=assert(loadstring(source..'\nreturn dbf_binding_warning_view'));setfenv(chunk,env)
local screen=chunk()();screen.show('DBF: Bind Confirm in MODS controls.')
local baseline=calls
for i=1,1000 do screen.show('DBF: Bind Confirm in MODS controls.')end
assert(calls==baseline,'unchanged warning does not rebuild screen commands')
screen.show(nil);assert(destroyed==1)
print('Binding warning: required controls, repair, unknown/provider guards, 500ms bound and persistent screen cleanup passed.')

local rows={one={{device='mouse',button='left',trigger='press'}},two={}}
local v4={api=1,version=4,binding_info=function()return {backend='extended'}end,binding=function(id)return rows[id]end}
local public=assert(make_reader(v4));assert(public('one')==true and public('two')==false and public('unknown')==nil)
assert(make_reader({api=1})==nil)
print('MBM v4 extended warning uses public binding metadata; absent and unknown remain distinct.')
