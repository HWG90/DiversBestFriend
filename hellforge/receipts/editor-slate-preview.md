# Slate/gold editor preview — 2026-11-05

User-directed menu refresh following HellForge Editor: grouped category navigation,
icons and counts, collapsible sections, slate surfaces and gold headings/accents.
NEST palette comes from the Editor tokens; DBF consumes theme roles.

Controls: Q previous view, E next view, Tab applies, F7 opens DBF. Ctrl+F search
and Ctrl+E Review remain. Typing, binding capture and another focused NEST panel
suppress DBF navigation/apply shortcuts. F6/F9 no longer navigate/apply.

DBF source through 84c1081; NEST 8dd4940. Exact Editor Regular body and Medium
headings retained. Existing explicit theme preferences are preserved; the default
and configurations without a theme select HellForge.

Validation: 24 C test groups passed, Windows-target DLL builds with import checks,
wide and narrow real D3D11 headless Proton rendering passed with balanced ImGui.
Final heading-font preview also passed. This is not live in-game acceptance or a
new native-Windows visual test. No active game files or public release changed.

Preview images: /tmp/dbf-layout11.LfWA2r/shots/slate-final.png and slate-narrow.png.
One-import review package: /tmp/DBF-Reforged-slate-preview.zip (unreleased build;
not a replacement for the published .11 archive).
