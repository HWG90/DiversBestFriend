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

## Live rejection of .13-preview

User reported no visible blur after loading .13-preview. Session
`3ec6c7fcec5d4bb4a2fe292221036ba1` confirms that version loaded and that expanded
and native wheel routes both submitted 96 triangles, bound blur_background,
set desaturate=0 and activated. The pass change did not resolve the visible
issue. Do not describe .13 as a visually accepted blur fix.

A read-only process inspection checked the mapped game's timestamp before
reading the HUD fields. At 3840x2160, the native viewport is 1920x1080 with
scale 2; the list matrix has scale 1.8 and translation (-639,1162.8).
The native transforms therefore already include physical pixel scaling.
The separate retained screen-Gui projection/context and its sampled scene
texture still need direct raster comparison with the working native backing.
