local message, calls, visible = nil, 0, false
local game = {}
stingray = {
    Application = {main_world=function() return game end, worlds=function() return {game} end},
    Gui = {resolution=function() return 1920,1080 end}, Vector2=function() end, Vector3=function() end,
    Color=function(a,r,g,b) assert(a and r and g and b) end
}
style = dofile('hellforge/hud/hd2_ui_style.lua')
function cooldown_gui_pool()
    return {acquire=function(world)
        return {world=world, gui={}, valid=function() return true end,
            api={rect=function() end, text=function(_, text) message=text end},
            release=function() visible=false end, show=function() visible=true end}
    end}
end
local bound = {1,0,0}
local view = dofile('hellforge/hud/binding_warning.lua').binding_warning({
    dbf_hud_bound=function(i) calls=calls+1; return bound[i+1] end,
    dbf_hud_log=error,
})
view.step(true,2,false,1,0)
assert(visible and message:find('Previous / Confirm',1,true))
view.step(true,2,false,1,10)
assert(calls==3)
view.step(true,3,true,1,20)
assert(not visible)
view.step(true,3,true,2,30)
assert(visible and message:find('Previous',1,true) and not message:find('Confirm',1,true))
view.step(false,3,true,2,35)
assert(not visible)
print('PASS engine binding warning')
