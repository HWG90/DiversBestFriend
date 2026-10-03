# R41 - Streamlined Options

I forgot that not everyone has MCM yet. The Bingus menu was overcrowded, so this revision suppresses appearance controls to make room for the blacklist. MCM support is upcoming; it is not a requirement.

Kept: Enable Mod, Mode, Sound feedback, Experimental layout, Preset, Controller Select on Release, Input interval and the three mission-only blacklist entries.

Suppressed: wheel size, icon size, center-label size, native opacity, full-color icons, wedge darkness and wedge opacity. Existing saved appearance values are retained and presets still work. Vertical offset is disabled at zero without deleting its saved value.

Retains R40 selection fixes and persistent blacklist IDs, including equipped-stratagem protection. Restart after deployment so old session registrations disappear. Offline package and LuaJIT contracts pass; the reduced menu still needs a fresh-session visual check.
