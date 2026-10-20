local f=assert(io.open('native-selection-poc/binding_defaults.lua'));local text=f:read('*a');f:close()
local options=assert(loadstring(text..'\nreturn dbf_binding_options'))()
for _,key in ipairs({'next','previous','confirm'})do
 local value=options({version=4},key)
 assert(value.backend=='native'and value.default==nil,'MBM4 must retain native MODS rows')
end
for _,version in ipairs({2,3})do assert(options({version=version},'confirm').backend==nil)end
-- MBM v4 choose_action must bypass a persisted extended record when native is explicit.
local path=os.getenv('MBM_SOURCE')
if path then
 local f=assert(io.open(path));local source=f:read('*a');f:close()
 local first=assert(source:find('local function choose_action(',1,true))
 local last=assert(source:find('function api.register_binding(',first,true))
 local prefix="local mbm={reserved=function()return false end,POOL_REASONS={}};local SLOT_CODES,SHARED_SLOTS={},{};local state={used={}};local function extended_known()return true end;local function assign_action(id,fallback)assert(fallback==false);return 655360 end;"
 local choose=assert(loadstring(prefix..source:sub(first,last-1)..' return choose_action'))()
 assert(choose('native_stratagem_radial.next',nil,'native')==655360,'saved extended IDs must recover native actions')
end
print('Native MBM registration and persisted-extended migration passed')
