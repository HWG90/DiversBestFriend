local file=assert(io.open('native-selection-poc/settings.lua'));local source=file:read('*a');file:close()
local configure=assert(loadstring(source..'\nreturn canary_settings'))()
local specs,values={},{}
local menu={register_option=function(id,s)specs[id]=s;values[id]=s.default;return true end,get=function(id)return values[id]end,on_change=function()return true end}
configure(menu,{}, {},0)
local prefix='native_stratagem_radial.'
local function set(key,v)values[prefix..key]=v end
local function enabled(key)local c=assert(specs[prefix..key]);return not c.enabled_if or c.enabled_if(menu.get)end
assert(enabled('experimental_layout') and enabled('wedge_opacity'))
set('selection_mode_ordered',2);assert(not enabled('experimental_layout') and not enabled('wedge_opacity') and enabled('hide_blacklisted_list'))
set('selection_mode_ordered',1);assert(enabled('experimental_layout') and enabled('wedge_opacity') and not enabled('hide_blacklisted_list'))
set('experimental_layout',1);assert(not enabled('wedge_darkness'));set('experimental_layout',2);assert(enabled('wedge_darkness'))
set('selection_mode_ordered',3);assert(enabled('native_opacity') and not enabled('experimental_layout'))
set('randomize_input_delay',true);assert(not enabled('input_interval_ms'));set('randomize_input_delay',false);assert(enabled('input_interval_ms'))
set('appearance_preset',2);assert(not enabled('wheel_size'));set('appearance_preset',1);assert(enabled('wheel_size'))
set('cooldown_icons',false);assert(not enabled('cooldown_display') and not enabled('cooldown_timer'))
set('cooldown_icons',true);set('cooldown_timers',false);assert(not enabled('cooldown_timer') and enabled('brief_timer_limit'))
set('cooldown_timers',true);assert(enabled('cooldown_timer'))
set('cooldown_display',2);assert(not enabled('short_status_placement'))
set('cooldown_display',1);set('short_status_placement',4);assert(not enabled('balance_separated_dock'))
set('short_status_placement',3);assert(enabled('balance_separated_dock'))
print('DBF-declared conditions: modes, wheel layout/presets, randomized delay, dock, timers and separator passed')
