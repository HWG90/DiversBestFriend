# Wheel blur .13-preview installation

Source fix: `bf6af7d`; independently reviewed. The screen-Gui pipeline setup
requests transparent, while the previous gui_blur material belongs to
transparent_pre. The new blur_background material uses transparent; its
otherwise identical shader is initialized with desaturate=0, matching native
HUD backing. Geometry, tint and configured opacity are unchanged.

Targeted blur and HUD runtime tests passed; DLL SDK/import checks and combined
package verification passed. Installed one root-manifest bundle as
`mods/divers-best-friend-R50-hellforge.13-preview.zip` in the active HellForge
prefix. Public releases were not changed.

Bundle SHA-256: `f24a8bc674fbaa9e25b5ff2045a9451642b04e47ee28a217bb8ac6209a2c11ae`.
Verified previous bundle and receipt:
`backport-backups/dbf-blur-pass-20261106T025612Z/`.

Activation requires a new game launch. Visible wedge blur remains unverified;
source pipeline evidence and offline tests do not establish live appearance.
