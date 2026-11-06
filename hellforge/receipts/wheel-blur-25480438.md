# Expanded wheel blur material pass — build 25480438

## Evidence and scope

The live `.12-preview` trace in session `d1adf6260795478e85b44ee88da31dcc` reports expanded geometry, a non-main world, `gui_blur`, 3840x2160 resolution, 96 submitted triangles, successful binding and activation. The user still observed sharp scenery. Submission is not visual acceptance.

Proper shader-library resources in archive `ee6b1ba7e22d71ed` identify:

| Material | Shader resource | Variant | Pass |
| --- | --- | --- | --- |
| `gui_blur` | `5eadf77a020973fb` (`gui:layer_pre:blur_background`) | `05a4ca9e` | `transparent_pre` (`ea3c5154`) |
| `blur_background` | `bd986cb1705ff2dc` (`gui:blur_background`) | `47f7f610` | `transparent` (`6d0e732e`) |

The compiled shaders are identical. Pixel-shader disassembly `/tmp/dbf-blur-pixel.asm` samples `t0` (`hdr0_div4_fullres`) using `SV_Position.xy / screen resolution`. It ignores triangle UVs and performs no blur kernel; the sampled image must be prepared upstream. `cb2[3].y` controls desaturation, not blur strength. Material resources themselves have zero GPU payload; adjacent GPU slices must not be mistaken for their shaders.

Target EXE material setup at RVA `264620` requests `transparent` at `2649c7`, passing it to `112a30` at `2649d4`. `/tmp/dbf-gui-pass.bin` is the slice at RVA `264880`, length `210` hex. Confucius independently verified the bytes and call context. This is pipeline setup/cache evidence, not a captured per-frame dispatcher or proof of exclusive draw-pass behavior.

Native weapon backing at game.dll RVA `18167ce` sets scalar hash `4c680e90` (`desaturate`) to zero through `1449710`. `blur_background` defaults this scalar to one; explicitly setting zero preserves native color treatment.

Binary SHA-256:

- EXE `r6_reload_exe_20261017.bin`: `2b2c496218a5ce7e4f3453951acb8bd756bc4c2f281ce95eadef17b894e39c16`.
- game.dll `hob-game-6AB3B43F.bin`: `642b0aac0b4f577054993a965054827455ef143ced9895b2dfd09d1ecd433a37`.

## Change

Select only `blur_background`, matching the requested transparent pass; do not silently retry the incompatible prepass material. Apply `Material.set_scalar(handle, 'desaturate', 0)` before showing retained geometry. Missing APIs or failed material/parameter setup keep geometry hidden; cleanup and five-second retries remain available. Existing transition-deduplicated diagnostics report parameter setup. Geometry, XZ coordinates, UVs, draw layer, theme tint and opacity are unchanged.

## Validation and remaining gate

- `luajit hellforge/tests/wheel_blur.lua`: passed. Covers compatible-pass-only selection, prepass-only unavailability, scalar setup before visibility, partial mesh/binding/parameter failure cleanup and delayed recovery, transformed clipping, opacity, and diagnostic deduplication.
- `luajit hellforge/tests/test_hud_runtime.lua`: passed, including lifecycle/recovery behavior.
- `git diff --check`: passed.
- Confucius independent source review: clean; independently repeated both targeted fixtures successfully.

Next live acceptance must confirm expanded wedges visibly blur scenery, preserve color/brightness, and clean up on close/reopen. This patch corrects an evidenced material/pass mismatch; offline tests cannot establish that the upstream render target is populated at the required time or that the result is unobscured. No installation or publication performed by this task.
