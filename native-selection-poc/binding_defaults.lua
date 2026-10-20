-- Keep controls on MBM's native MODS page, including v4 providers.
-- Author defaults are extended-only; do not trade away native UI/input for them.
local function dbf_binding_options(menu,key)
    local options={category="Diver's Best Friend"}
    if menu.version>=4 then options.backend='native' end
    return options
end
