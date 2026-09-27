# r23 — Wedge Appearance

Expanded wedges are darker and less transparent by default, with independent controls in **MODS > Native Stratagem Radial**:

- **Expanded wedge darkness (%)**: 0 original gray to 100 black; default **70**.
- **Expanded wedge opacity (%)**: 0 transparent to 100 opaque; default **75**.

Press Apply. To restore the previous appearance, set darkness **0** and opacity **30**. The selected wedge stays yellow and at least 95% opaque; icons retain their visibility and empty sectors remain fainter. Other layouts are unchanged.

Row-card blur was investigated but is not included: its native material has no texture binding for the sector mask. A direct swap is not a demonstrated wedge-shaped blur solution.

Retains r22 centering, all selection modes, cursor tracking, and existing settings/bindings. Replace the previous addon ZIP in Arsenal while the game is closed, deploy, and restart. The stable GUID is unchanged.

Requirements remain **Bingus Shared Loader v18 / API 1**, **Mod Bindings Menu v2.0**, and **Mod Options Menu v1.0.1 / API 1**, by CowboyBingus. Target: Windows/Steam build **25480438**.

Validation: isolated Lua fixtures and deterministic package checks pass, including appearance endpoints, invalid settings, live updates, and selection preservation. In-game appearance still needs a visual check.
