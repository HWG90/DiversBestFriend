local function canary_settings(menu,api,radial)
    local prefix='native_stratagem_radial.'
    local specs={
        {'enabled','Selection','Enable Mod','toggle',true},
        {'selection_mode','Selection','Mode','choice',1,{'Native wheel','Keybindings - list','Experimental'}},
        {'selection_sounds','Selection','Sound feedback','toggle',true},
        {'experimental_layout','Appearance','Experimental layout','choice',1,{'Cards - copied list rows','Expanded wedges'},nil,nil,'Experimental mode only.'},
        {'appearance_preset','Appearance','Preset','choice',1,{'Custom','Compact','Standard','Large'},nil,nil,'Custom uses the size sliders below. Other presets override sizes; opacity and colors stay independent.'},
        {'wheel_size','Appearance','Wheel size (%)','slider',100,70,130,5,'All radial layouts. Custom preset only.'},
        {'icon_size','Appearance','Icon size (%)','slider',100,70,130,5,'Native and expanded wheels. Relative to wheel size; Custom preset only.'},
        {'label_size','Appearance','Center label size (%)','slider',100,70,130,5,'Native and expanded wheels. Relative to wheel size; Custom preset only.'},
        {'native_opacity','Appearance','Native wheel opacity (%)','slider',100,0,100,5,'Native wheel only; background opacity. Selected highlight stays visible.'},
        {'full_color_icons','Appearance','Full-color stratagem icons','toggle',true},
        {'wedge_darkness','Appearance','Expanded wedge darkness (%)','slider',70,0,100,5,'Expanded wedges only.'},
        {'wedge_opacity','Appearance','Expanded wedge opacity (%)','slider',75,0,100,5,'Expanded wedges only; selected highlight stays visible.'},
        {'select_on_release','Controller','Select on Release','toggle',false,nil,nil,nil,'Radial modes with a Hold menu binding: point then release. Center before releasing to cancel. Also works with mouse.'},
        {'input_interval_ms','Advanced','Input interval (ms)','slider',70,0,250,5,'Delay between directions. 0 sends one per frame; applies to the next code.'},
        {'vertical_offset','Advanced','Radial vertical offset (down)','slider',0,-600,600,25,'Radial layouts: positive moves down. Leave at 0 for automatic centering.'},
    }
    specs[#specs+1]={'hide_sos','Blacklist','Hide SOS Beacon','toggle',false,nil,nil,nil,
        'Exclude SOS Beacon from every DBF selection layout. Manual vanilla stratagem input remains available.'}
    for i=1,8 do
        specs[#specs+1]={'blacklist_kind_'..i,'Blacklist','Extra stratagem ID '..i,'slider',0,0,149,1,
            '0 = empty. Exclude this native stratagem ID in every DBF layout. Examples: 145 SOS Beacon, 33 Resupply, 124 Reinforce. See docs/BLACKLIST.md for the ID reference. Duplicates are harmless.'}
    end
    local values={}
    api.values=api.values or {}
    local previous
    for _,s in ipairs(specs) do
        local spec={mod="Diver's Best Friend",label=s[2]..' / '..s[3],type=s[4],default=s[5],gap=previous~=s[2],description=s[9] or s[3]}
        if s[4]=='choice' then spec.choices=s[6] end
        if s[4]=='slider' then spec.min=s[6];spec.max=s[7];spec.step=s[8] end
        if not api.registered[s[1]] then api.registered[s[1]]=menu.register_option(prefix..s[1],spec)==true end
        local v=menu.get(prefix..s[1]);local valid=false
        if s[4]=='toggle' then valid=type(v)=='boolean'
        elseif type(v)=='number' and v==v then
            if s[4]=='choice' then valid=v%1==0 and v>=1 and v<=#s[6]
            else valid=v>=s[6] and v<=s[7]
                if s[1]:find('blacklist_kind_',1,true) then valid=valid and v%1==0 end
            end
        end
        if valid then api.values[s[1]]=v end
        if api.values[s[1]]==nil then api.values[s[1]]=s[5] end
        values[s[1]]=api.values[s[1]]
        previous=s[2]
    end
    local presets={{values.wheel_size,values.icon_size,values.label_size},{85,100,95},{100,100,100},{115,110,110}}
    local sizes=presets[values.appearance_preset]
    radial.wheel_scale,radial.icon_scale,radial.label_scale=sizes[1]/100,sizes[2]/100,sizes[3]/100
    radial.native_opacity=values.native_opacity/100
    radial.full_color=values.full_color_icons
    radial.wedge_darkness,radial.wedge_opacity=values.wedge_darkness,values.wedge_opacity
    radial.vertical_offset=values.vertical_offset
    return values
end
