-- R50's bottom-centre warning, backed by the bindings in HellForge's settings.
local function binding_warning(bridge)
    local lease, signature, next_check, last_requirement
    local self = {}
    function self.hide()
        if lease then lease.release(); lease = nil end
        signature, next_check = nil, nil
    end
    local function show(text)
        local sr = rawget(_G, 'stingray')
        if not text or not sr or not sr.Application or not sr.Gui then self.hide(); return end
        local world = sr.Application.main_world()
        for _, candidate in pairs(sr.Application.worlds() or {}) do
            if candidate ~= world then world = candidate; break end
        end
        local w, h = sr.Gui.resolution()
        if not world or not w or not h or w <= 32 or h <= 0 then self.hide(); return end
        local key = text..':'..w..':'..h
        if lease and lease.world == world and lease.valid() and signature == key then return end
        self.hide()
        lease = cooldown_gui_pool(sr, 'DBFBindingWarningGuiPool').acquire(world, {})
        local function color(name)
            local c = style.tokens.colors[name]
            return sr.Color(c[4], c[1], c[2], c[3])
        end
        local size = math.max(14, math.min(20, w / 75))
        local width = math.min(w - 32, #text * size * 0.62 + 28)
        local x = (w - width) / 2
        local font = 'core/performance_hud/debug'
        lease.api.rect(lease.gui, sr.Vector3(x, 16, 950), sr.Vector2(width, size + 20), color('hud_plate'))
        lease.api.text(lease.gui, text, font, size, font, sr.Vector3(x + 14, 26, 951), color('yellow'))
        lease.show()
        signature = key
    end
    function self.step(visible, mode, on_release, pages, now)
        if not visible then self.hide(); return end
        local navigation = mode == 2 or mode == 3 and pages > 1
        local confirm = mode == 2 or not on_release
        local requirement = tostring(navigation)..tostring(confirm)
        if last_requirement == requirement and next_check and now < next_check then return end
        local missing = {}
        for i, name in ipairs({'Next', 'Previous', 'Confirm'}) do
            if ((i < 3 and navigation) or (i == 3 and confirm)) and bridge.dbf_hud_bound(i - 1) == 0 then
                missing[#missing + 1] = name
            end
        end
        local message
        if #missing > 0 then message = 'DBF: Bind '..table.concat(missing, ' / ')..' in DBF Controls.' end
        local ok, why = pcall(show, message)
        if not ok then
            self.hide()
            if self.error ~= tostring(why) then
                self.error = tostring(why)
                bridge.dbf_hud_log('Binding warning unavailable: '..self.error)
            end
        end
        next_check, last_requirement = now + 500, requirement
    end
    return self
end
return {binding_warning=binding_warning}
