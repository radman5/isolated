# PS1 shader stack in Godot 4.7

Research for [#5](https://github.com/radman5/isolated/issues/5) (part of #1). The target look is GDD §11: vertex snapping, affine texture mapping, a ~320×240 render that gets upscaled, dithering, and hard distance fog.

Researched 2026-09-18 against Godot 4.7 stable docs and the addon repos at their current HEAD. "By reading" means I read the source but did not run it.

## Short answer

**Don't add an addon. Write one small spatial shader and one small post shader (about 80 lines together), and get the rest from built-in settings.**

| Piece | Cheapest reliable way | Source of truth |
|---|---|---|
| ~320×240, upscaled | Project setting `display/window/stretch/mode="viewport"`, base size 320×240 (or 426×240 for 16:9), `scale_mode="integer"` | [Resolution scaling docs](https://docs.godotengine.org/en/stable/tutorials/3d/resolution_scaling.html) |
| Hard distance fog | `Environment.fog_mode = FOG_MODE_DEPTH` with `fog_depth_begin`/`fog_depth_end`/`fog_depth_curve` | [Environment docs](https://docs.godotengine.org/en/stable/classes/class_environment.html) |
| Vertex snapping | Custom spatial shader. Write `POSITION` snapped to the 320×240 grid in NDC | MenacingMecha shader (MIT), [spatial shader docs](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html) |
| Affine texture mapping | Same shader: a `UV*w` varying plus a `w` varying, divided in `fragment()` | [shading language docs](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html) |
| Dithering | Full-screen `ColorRect` with a canvas_item shader: 4×4 Bayer plus 5-bit quantise via `hint_screen_texture` | Pattern used by every repo below |
| Gouraud look (bonus) | `render_mode vertex_lighting` in the same shader | spatial shader docs |

**Effort:** about half a day for a working stack across all demo scenes, plus about half a day of tuning (snap resolution, fog distances, dither strength) and a Web build check.

## What the engine gives you for free (Godot 4.7, Compatibility)

The project runs the Compatibility renderer (`project.godot`: `renderer/rendering_method="gl_compatibility"`, features `"4.7", "GL Compatibility"`). That is also the only renderer the Web export can use: the [renderers page](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html) marks Compatibility as the only Web-capable one. So "Forward+ vs Compatibility" is really a Compatibility-only question here, which keeps things simple.

- **Low resolution.** The [resolution scaling docs](https://docs.godotengine.org/en/stable/tutorials/3d/resolution_scaling.html) list only Bilinear as "available in all renderers". FSR 1.0 and FSR 2.2 are Forward+ only, and there is no nearest-neighbour 3D scaling mode. `Viewport.scaling_3d_scale` would therefore give a blurry image, not a chunky one. The route that works is the `viewport` stretch mode, which the same page points to. The upstream PSX addon (snotbane) uses exactly this in its own `project.godot`: `stretch/mode="viewport"`, `scale_mode="integer"`, Compatibility.
- **Fog.** `FOG_MODE_DEPTH` is "a simple fog model defined by start and end positions and a custom curve" ([Environment](https://docs.godotengine.org/en/stable/classes/class_environment.html)). The renderers table lists depth/height fog as supported in all three renderers. Volumetric fog is Forward+ only, but we don't need it. A steep `fog_depth_curve` gives the hard wall. `fog_sky_affect = 1.0` lets fog fully hide the sky, which gives the "hides the edge of the world" effect.
- **Screen texture reads** (needed for the dither pass) are supported in all renderers (renderers table).
- **Opting out of fog:** `BaseMaterial3D.disable_fog` (StandardMaterial3D) and `render_mode fog_disabled` (shaders).
- **What the engine lacks:** nothing built in does vertex snapping or affine mapping. `varying` only supports `flat` and `smooth` (perspective-correct); there is no `noperspective` ([shading language](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html)). So both effects need a custom spatial shader.

## Maintained open-source options

| Repo | Licence | Last push | Godot / renderer | Verdict |
|---|---|---|---|---|
| [MenacingMecha/godot-psx-style-demo](https://github.com/MenacingMecha/godot-psx-style-demo) | MIT | 2023-09 | 4.0, shaders only (`.gdshader`/`.gdshaderinc`) | **Best reference.** Correct clip-space snap. Few knobs. Not a plugin, you copy the files. |
| [snotbane/psx_visuals](https://github.com/snotbane/psx_visuals) (Asset Library [#4557](https://godotengine.org/asset-library/asset/4557)) | Unlicense | 2026-04 | 4.6, Compatibility, stretch=viewport | Active and full-featured (conversion dialog, `PsxMaterial3D`, vertex fog). **By reading, the affine and vertex-fog code is a no-op** (see below). |
| [scolastico/psx_visuals_gd4](https://github.com/scolastico/psx_visuals_gd4) (Asset Library [#4687](https://godotengine.org/asset-library/asset/4687)) | MIT | 2026-04 (code 2026-01) | 4.1+ | **Avoid.** Snapping is done on the wrong space. Open [issue #6](https://github.com/scolastico/psx_visuals_gd4/issues/6) reports it "doesn't actually seem to apply any vertex snapping" and that AutoApply crashes on Sprite3D/CSG. |
| [Rytelier/Godot-PSX-Visuals](https://github.com/Rytelier/Godot-PSX-Visuals) | MIT | 2024-10 | 4.4+ | Good feature list (per-vertex fog, triangle sorting, near-triangle pushback). Its screen downscale ships as a `CompositorEffect` (RenderingDevice, so Forward+/Mobile only, **no Web**), but it also has a canvas variant (`Shaders/Canvas/PSX screen.gdshader`). Uses its own vertex fog, not Environment fog. |
| [marmitoTH/godot-psx-shaders](https://github.com/marmitoTH/godot-psx-shaders) | MIT | 2021, archived | 3.1 | Historical. The origin of MenacingMecha's shaders. |

Notes, by reading the source:

- **scolastico `psx.gdshaderinc`** snaps `VERTEX` with the comment "VERTEX is already in View Space". The 4.7 docs say `VERTEX` in `vertex()` is "Position of the vertex, in model space" ([spatial shader](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html)), and the opaque shader uses no `skip_vertex_transform`. The snap therefore happens in object units, and `length(vertex)` (used for fog and the affine divisor) is distance from the model origin, not from the camera. That matches issue #6.
- **snotbane `psx.gdshaderinc`** builds `v_clip = MODELVIEW_MATRIX * vec4(VERTEX, 1.0)`. That is a view-space point, so `v_clip.w == 1.0`, and `v_uv = UV * v_clip.w` / `v_uv / v_clip.w` gives back plain `UV`. The vertex fog also uses `v_clip.w` as its distance. The xy snap is fine. I did not run it; a 10-minute check in the editor would confirm.
- **MenacingMecha `psx_base.gdshaderinc`** snaps in NDC to a 160×120 grid (scaled by a global `precision_multiplier`). It then does `POSITION /= abs(POSITION.w)` to kill perspective correction. That is cheap, but it also makes lighting and fog varyings affine, and it breaks near-plane clipping (large triangles crossing the camera plane misdraw). The `UV*w` varying trick below avoids both problems.

**Why not just take an addon:** the two maintained plugins both have core-math bugs in exactly the effects we can't get from the engine. Both also ship an **auto-apply** system that walks the tree and replaces materials on every `GeometryInstance3D`, which is more machinery than this repo needs (see "debug overlay" below). The shader we need is about 40 lines, so copying MenacingMecha's MIT snap function (with attribution) and writing the affine part ourselves costs less than auditing and patching a plugin.

## Interactions with this repo

### KayKit glTF assets (StandardMaterial3D)

- The characters and weapons import as glTF with a single `StandardMaterial3D` per model: `baseColorTexture`, metallic 0, roughness 0.5 (e.g. `assets/kaykit/weapons/Skeleton_Axe.gltf`). That is easy to convert: copy `albedo_texture` (and `albedo_color`) into a ShaderMaterial. This is the same thing scolastico's `AutoApply.gd` does.
- **The textures are 1024² gradient palette atlases** (`assets/kaykit/characters/knight_texture.png`: vertical gradient swatches, no detail). Affine warp is therefore **almost invisible on KayKit models**; it will only show on detailed environment textures added later. On these assets, vertex snap, low resolution and dithering (which will band the gradients nicely) do the work. Don't spend tuning time on affine for characters.
- Set `filter_nearest` on the sampler in the shader. A 1024² atlas sampled at 320×240 with nearest filtering and no mipmaps will shimmer slightly on distant swatch edges. That is acceptable and period-correct. If it's too much, fix it with `filter_nearest_mipmap`, not linear filtering.
- Skinned characters: Godot applies skinning before the user `vertex()` function, so snapping a skinned mesh is no different from snapping a static one. That's how every repo above works.
- How to apply it: the lowest-effort path is one autoload, about 25 lines. On `node_added`, for a `MeshInstance3D` whose surface material is a `StandardMaterial3D`, it swaps in a cached `ShaderMaterial` per `albedo_texture` (6 atlases, so 6 materials, which also means one compiled shader). It skips anything with `material_override` or meta `psx_off`. The alternative is setting an external material per surface in each `.glb` import dialog. That avoids runtime work but means clicking through about 15 imports and redoing it for every new asset.

### Web export

- Everything above is plain Compatibility-renderer shader code: `POSITION`, varyings, `hint_screen_texture`, depth fog. No CompositorEffect, no RenderingDevice, no compute. The one thing to avoid is Rytelier's Compositor path.
- Rendering at 320×240 makes the Web build cheaper, not dearer: fewer fragments, and the full-screen dither pass runs at 320×240 too.
- WebGL compiles shaders on first use. One shared spatial shader means one compile hitch at scene load, not one per material.
- `export_presets.cfg` needs no change. `web.yml` already exports headless, so a broken shader shows up as an export or import error in CI.

### Debug overlay (`debug_draw.gd`)

`debug_draw.gd` draws one `MeshInstance3D` + `ImmediateMesh`, rebuilt every frame, with an unshaded `StandardMaterial3D` set via `material_override` (`no_depth_test`, alpha, vertex colours). It also draws several `Label3D`s (`no_depth_test`, billboard, `render_priority` 10). F1 or \` toggles it via `static var shown`.

- **Material swap:** skip nodes with `material_override`. Then the debug mesh is never converted, and it doesn't need snapping anyway. Note that scolastico's AutoApply only checks for Label3D and particles and would try to convert this node too.
- **Fog:** depth fog applies to unshaded materials unless disabled ([`disable_fog`](https://docs.godotengine.org/en/stable/classes/class_basematerial3d.html)). Add `m.disable_fog = true` in `_ready()` (one line). `Label3D` has no fog opt-out property. Labels only fog if they sit past `fog_depth_begin`, which in an arena seen from the follow camera they won't. Worth a glance once fog is tuned.
- **Resolution:** with stretch mode `viewport` at 320×240, the Label3D text and `debug_hud.gd` become unreadable. The cheapest fix is to change `get_window().content_scale_mode` to `CONTENT_SCALE_MODE_CANVAS_ITEMS` whenever debug is shown, and back to `VIEWPORT` when hidden (about 3 lines in the existing F1 handler). Debug view then renders at native resolution, which is what you want when reading frame timers. Also hide the dither `ColorRect` in debug mode so the overlay colours stay exact.
- The alternative, a second viewport that renders only the debug layer at native resolution over a low-res game layer, is more nodes and camera syncing than it's worth for a dev tool.

## Recommended approach

1. **Engine settings (≈30 min):** stretch mode `viewport` at 320×240 (or 426×240 for 16:9), `scale_mode=integer`, aspect `keep`/`keep_height`. Add a `WorldEnvironment` with depth fog to the arena and demo scenes; a shared `Environment` `.tres` means one place to tune it. This already delivers about 60% of the look.
2. **`psx.gdshader` (≈1–2 h):** `render_mode vertex_lighting, specular_disabled`. Snap `POSITION` in NDC to the render grid (after MenacingMecha, MIT, credited in a comment). For affine, use `varying vec2 uv_w; varying float w;` with `uv_w = UV * clip.w; w = clip.w;` in `vertex()` and `mix(UV, uv_w / w, affine)` in `fragment()`. Perspective-correct interpolation of `UV·w` divided by that of `w` cancels out to screen-linear UV, so clipping and lighting stay correct. Use a `sampler2D albedo : filter_nearest` and an `albedo_color`.
3. **`psx_apply.gd` autoload (≈1 h):** the StandardMaterial3D → cached ShaderMaterial swap described above, skipping `material_override` and `psx_off`.
4. **Dither pass (≈30 min):** a `CanvasLayer` with a full-rect `ColorRect` (`mouse_filter = IGNORE`) and a canvas_item shader: 4×4 Bayer + quantise to 5 bits per channel (the matrix from any repo above), reading `hint_screen_texture`.
5. **Debug overlay (≈15 min):** `disable_fog` on its material. In the F1 handler, switch `content_scale_mode` and hide the dither layer.
6. **Verify (≈1 h):** run the arena locally and a Web export. Check that snapping visibly wobbles on a moving camera, that fog hides the far edge, and that the debug text is readable with F1.

Total is roughly one working day. There are no new dependencies and no plugin to keep in step with engine updates.

Skipped on purpose: 15-bit colour texture posterising at import time, per-vertex fog, triangle depth-sort jitter, and near-triangle pushback (Rytelier does these). Add them if the look reads as "too clean" after step 6.
