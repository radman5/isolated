# Painterly stylized rendering in Godot 4.7 (web-safe)

Research for [#12](https://github.com/radman5/isolated/issues/12) (part of #1). It builds on the decision in #11: a painterly, stylized world heavily influenced by Akihiko Yoshida's FFT concept art, with lean bodies in bulky armour, a soft muted palette, soft ink-like outlines on characters, and a mostly top-down camera. This replaces the PS1 stack (#5).

I checked everything against the Godot 4.7 stable docs, the engine source on `master`, and the addon repos at their current HEAD on 2026-09-18. "By reading" means I read the code but did not run it. Every GPU cost below is **worked out from tap counts, not measured**. Measuring it is a job for the style test (#14).

## Short answer

Stack the three candidates in this order of value. Each layer is cheap and can be toggled on its own:

1. **Base (must-have): painted albedo, stylized lighting and a graded palette.** Use a small custom spatial shader with a half-Lambert diffuse and an artist ramp in `light()` (the TF2 recipe), or just `diffuse_mode = DIFFUSE_TOON` on StandardMaterial3D. Add Environment tonemap and a 1D/3D LUT for the muted earth palette. This is where most of the "Yoshida" read comes from, and it costs almost nothing on the GPU.
2. **Character outlines: inverted hull**, applied as `material_overlay` from `character_view.gd`. Extrude in clip space so the width stays constant on screen, and use a dark warm brown rather than black. **Don't use screen-space edge detection.** Compatibility has no normal buffer, and edge detection would ink the whole world, not just characters.
3. **Painterly post: light and optional.** Add paper grain plus a slight UV wobble (about 3 taps, basically free). If the style test wants more, add a **generalized (8-sector) Kuwahara at radius 2–3 on a full-screen spatial quad**, with `scaling_3d_scale` about 0.6 so it runs on roughly a third of the pixels. Leave anisotropic Kuwahara for last. Done properly it needs several passes, which on Compatibility means a SubViewport chain.

**Effort:** about 2½–3 engineering days for the whole stack, including the Web check. Painted textures are an art cost that depends on #13, and it is the biggest single item. See "Effort" at the end.

## Engine constraints that decide this (Compatibility / Web)

The project uses `renderer/rendering_method="gl_compatibility"` (`project.godot`). That is also the only Web-capable renderer. On Web it runs on WebGL 2.0 (`rendering/gl_compatibility/driver.web`, [ProjectSettings](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html)).

From the [renderers comparison](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html) and [screen-reading shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html):

| Feature | Compatibility | Consequence |
|---|---|---|
| Screen texture (`hint_screen_texture`) | Supported | Kuwahara, grain and wobble are all possible |
| Depth texture (`hint_depth_texture`) | Supported | Depth-only edge detection is possible. NDC z is `[-1,1]` here, so reconstruct with `vec3(SCREEN_UV, depth) * 2.0 - 1.0` ([advanced post-processing](https://docs.godotengine.org/en/stable/tutorials/shaders/advanced_postprocessing.html)) |
| Normal-roughness texture | **Not supported** (Forward+ only) | No normal-based screen-space edges, so crease lines inside a character are out |
| `CompositorEffect` | **Not supported** | No compute or RenderingDevice post chain. Post has to be a spatial full-screen quad, a canvas `ColorRect`, or a SubViewport chain |
| Adjustments (brightness/contrast/saturation/LUT), tonemap | Supported | The palette grade is free |
| Glow | Supported, simplified | Several glow knobs are hidden or ignored on Compatibility ([Environment](https://docs.godotengine.org/en/stable/classes/class_environment.html)). A soft bloom still works |
| FXAA / SMAA / TAA | Not supported | Only MSAA 3D. That's fine, because outlines are geometry and MSAA smooths them |
| FSR | Not supported, falls back to bilinear | `scaling_3d_scale < 1` still works (bilinear). Soft upscaling suits a painterly look |
| Stencil | Implemented in the GLES3 driver ([PR #80710](https://github.com/godotengine/godot/pull/80710) touches `drivers/gles3/*`); marked experimental | The built-in outline preset is an option (see below) |
| Toon diffuse/specular, custom `light()` | Supported (`DIFFUSE_TOON`, `SPECULAR_TOON`, `LIGHT_CODE_USED` in [`drivers/gles3/shaders/scene.glsl`](https://github.com/godotengine/godot/blob/master/drivers/gles3/shaders/scene.glsl)) | Candidate 3's lighting half is fully available |

The screen texture in 3D "is copied after the opaque geometry pass, but before the transparent geometry pass" ([screen-reading shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html)). That timing matters for ordering outlines and the debug overlay against the post quad (below).

## Candidate 1: painted textures under simple or stylized lighting

**What it gives:** most of the look. Yoshida's FFT pieces read as flat, muted washes with light form shading and a line on top. Valve reached the same conclusion for TF2, which was modelled on Leyendecker, Cornwell and Rockwell. The world detail came from hand-painted albedo with loose, visible brush strokes, some of it first painted in watercolour on canvas and scanned. Painted detail held up under magnification better than photo reference. Lighting was a half-Lambert term warped through a 1D ramp painted by an artist, and silhouettes were picked out with rim light rather than dark outlines ([Mitchell, Francke, Eng, *Illustrative Rendering in Team Fortress 2*, NPAR 2007](https://steamcdn-a.akamaihd.net/apps/valve/2007/NPAR07_IllustrativeRenderingInTeamFortress2.pdf), §4.3 and §5).

**In Godot 4.7 Compatibility:**

- **Zero-code:** StandardMaterial3D with `diffuse_mode = DIFFUSE_TOON` ("a hard cut for lighting, with smoothing affected by roughness") and `specular_mode = SPECULAR_DISABLED` or `SPECULAR_TOON` ([BaseMaterial3D](https://docs.godotengine.org/en/stable/classes/class_basematerial3d.html)). Raising roughness softens the terminator, so it doesn't read as hard anime cel.
- **Better (about 30 lines):** a spatial shader with `light()` that does `DIFFUSE_LIGHT += albedo * LIGHT_COLOR * texture(ramp, vec2(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0)).rgb * ATTENUATION`. That is TF2's warped half-Lambert. A `GradientTexture1D` ramp that runs from a warm mid-shadow to the lit colour gives the soft two- or three-tone wash. **Don't** enable `vertex_lighting`, because `light()` won't run with it ([spatial shader docs](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html)).
- **Unlit option:** `render_mode unshaded` with the lighting painted into the texture, the way PS1-era Yoshida games did it. It suits the fixed per-scene shots and static props, but characters look pasted-on under the follow cam once they move through lit and shadowed areas. Keep it as a per-prop choice, not the default.
- **Palette:** Environment `tonemap_mode` (Filmic or AgX to roll off highlights), `adjustment_enabled`, `adjustment_saturation` about 0.8, and `adjustment_color_correction` with a `GradientTexture1D` or a 3D LUT ([Environment](https://docs.godotengine.org/en/stable/classes/class_environment.html)). Keep ambient warm and bright so shadows stay readable from above. A shared `Environment` `.tres` gives you one knob for every scene. The arena currently uses a cool grey ambient (`demos/arena.tscn`, `ambient_light_color = Color(0.42, 0.45, 0.52)`), which is the opposite of an earth palette.
- **Lights:** `rendering/limits/opengl/max_lights_per_object` defaults to 8. Lowering it "may result in faster rendering on low-end, mobile, or web devices" ([ProjectSettings](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html)). One sun plus ambient is all this look needs.

**Web and texture notes:**

- On a top-down camera at `distance = 12.5`, `pitch_deg = 50` (`follow_camera.gd`), a character covers a few hundred pixels at most. A 512² painted atlas per character is plenty, and 256² will do for many props. `export_presets.cfg` has `vram_texture_compression/for_desktop=true`. S3TC/DXT bands soft painted gradients, so if banding shows, set the few hero textures to Lossless. At these sizes it's cheap.
- **Current assets:** the KayKit characters use gradient swatch atlases (`assets/kaykit/characters/*_texture.png`). There's nothing painterly in them to preserve, so candidate 1 means **new or repainted textures**. That ties this ticket to Character sourcing (#13).

**Verdict:** required, and cheap in code. The cost is art.

## Candidate 2: painterly screen post-process

### Options, cheapest first

| Effect | Taps per pixel | Passes | Notes |
|---|---|---|---|
| Paper grain (multiply by a tiling paper texture in screen space) | 1 | 1 | The cheapest "painted on something" cue. Screen-locked grain reads as paper. World-locked grain swims |
| UV wobble / edge jitter (offset screen UV by a low-frequency noise texture) | 1 + 1 | 1 | Makes hard polygon edges look hand-drawn. Keep the offset to 1–2 px or it reads as heat haze |
| Basic Kuwahara, radius *r* (4 square quadrants) | 4(r+1)² → r=2: 36, r=3: 64, r=4: 100 | 1 | Blocky artefacts at larger *r* |
| [PeterEve/godot-kuwahara](https://github.com/PeterEve/godot-kuwahara) (CC0, 2022) | 52 (4 quadrants × 13-tap circular kernel, `kernel4`) | 1 | Uses max−min as a stand-in for standard deviation. Ships canvas and spatial variants |
| Generalized Kuwahara, 8 sectors (Papari, Petkov, Campisi 2007, *Artistic edge and corner enhancing smoothing*, IEEE TIP 16(10)) | about (2r+1)² taps; each tap is weighted into overlapping sectors, so it's ALU-heavy → r=2: 25, r=3: 49 | 1 | [godotshaders "Generalized Kuwahara"](https://godotshaders.com/shader/generalized-kuwahara/) (Firerabbit, **MIT**, Godot 4.x, canvas, 8 sectors, default kernel size 2) |
| Anisotropic Kuwahara ([Kyprianidis, Kang, Döllner 2009](https://www.kyprianidis.com/p/pg2009/)) | structure tensor (Sobel, 9) + tensor blur + 8-sector elliptical filter | 3–4 when done properly | [godotshaders "Anisotropic Kuwahara Filter"](https://godotshaders.com/shader/anisotropic-kuwahara-filter/) (Calrsdr, **MIT**, 2024-11, a port of [Acerola's Unity code](https://github.com/GarrettGunnell/Post-Processing), MIT) squeezes it into **one** pass by computing the tensor per pixel. By reading, that means the tensor isn't blurred and each pixel pays for the Sobel again at every kernel tap. The reference [jkyprian/gpuakf](https://github.com/jkyprian/gpuakf) is **GPL-3.0**, so read it but don't copy it into this MIT repo |

Anisotropic Kuwahara gives the "oil paint strokes following the form" look, but it was not cheap even in the paper: 512×512 at 12 fps on a GTX 280 with r=3 and N=8. Dropping to N=4 sectors is the authors' own speed-up (paper, §4 Implementation).

### Cost at typical resolutions (arithmetic, not measured)

Pixels shaded per frame at scale 1.0:

| Output | Pixels | 52-tap pass (PeterEve) texel fetches per frame |
|---|---|---|
| 1280×720 | 0.92 M | 48 M |
| 1920×1080 | 2.07 M | 108 M |
| 2560×1440 | 3.69 M | 192 M |
| 2880×1800 (Retina laptop, full-window browser) | 5.18 M | 270 M |

The last row isn't hypothetical. `display/window/dpi/allow_hidpi` defaults to true and applies on Web ([ProjectSettings](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html)), and the Web preset uses `html/canvas_resize_policy=2` (fill the window). So on a MacBook the canvas is at device-pixel resolution.

**The lever is `scaling_3d_scale`.** A full-screen **spatial** quad (the [advanced post-processing](https://docs.godotengine.org/en/stable/tutorials/shaders/advanced_postprocessing.html) pattern: 2×2 `QuadMesh`, flip faces, `POSITION = vec4(VERTEX.xy, 1.0, 1.0)`, huge `extra_cull_margin`) is part of the 3D render, so it runs at the scaled 3D resolution. At 0.6 it shades 36% of the pixels (1080p → 0.75 M px → about 39 M fetches at 52 taps). The bilinear upscale afterwards softens the image further, which suits this look. A **canvas** `ColorRect` post runs at full window resolution whatever the 3D scale is. So use the spatial quad for Kuwahara, and keep canvas only for the 1–2-tap grain.

WebGL-specific risks (noted by reading, not measured):

- Big unrolled loops (8 sectors × 49 taps) can make first-use shader compilation slow in the browser, especially through ANGLE on Windows. One post shader means one hitch at scene load. Check it in the Web build.
- Kuwahara taps are neighbourhood reads with good cache locality, so on integrated GPUs fill rate rather than bandwidth tends to be the limit. Treat r ≤ 3 at scale ≈0.6 as the starting budget and measure on the weakest target laptop in #14.

### How it looks on this game (judgement)

- The characters are small on screen (see above). A radius-4 Kuwahara wipes faces and hand details at that size. **Keep r at 2–3**, or have the filter fade out near characters with a depth threshold, since the camera distance is known.
- With the current flat-swatch KayKit textures there's little texture detail for Kuwahara to "paint". It mostly rounds polygon edges and removes aliasing. The strokes come from painted textures (candidate 1), so the post is **a finish, not the source of the look**.
- Kuwahara is temporally stable on still frames, but it shimmers on moving thin geometry at low resolution. The follow cam moves constantly, so check it in motion, not in screenshots.

**Verdict:** grain plus wobble always (free). Generalized Kuwahara r=2–3 on a spatial quad at scale about 0.6 is optional, to be decided in #14. Anisotropic only if #14 shows the generalized version isn't enough, and then as a SubViewport chain (tensor → blur → filter), which costs 2–3 extra full-screen render targets.

## Candidate 3: toon shading and outlines

Toon lighting is covered in candidate 1 (`DIFFUSE_TOON` or a ramp in `light()`). For outlines:

| Method | Works in Compatibility? | Characters only? | Width | Notes |
|---|---|---|---|---|
| **Inverted hull**: second pass, `cull_front`, extruded along the normal | Yes, it's plain geometry | Yes, apply it per mesh | Constant on screen if extruded in clip space | Draws inner contours where one part overlaps another (arm over breastplate), which is exactly the ink look we want. Breaks at split normals (see below) |
| Built-in `stencil_mode = STENCIL_MODE_OUTLINE` (4.5+) | Yes. Stencil is implemented in `drivers/gles3` ([PR #80710](https://github.com/godotengine/godot/pull/80710)). **Experimental** | Yes | **World units.** The auto-created next pass uses `grow` = `stencil_outline_thickness` ([`material.cpp` `_prepare_stencil_effect`](https://github.com/godotengine/godot/blob/master/scene/resources/material.cpp)) | Zero code. **Silhouette only.** The next pass is drawn where stencil ≠ ref, so there are no inner lines between armour pieces. Open bugs: [#111482](https://github.com/godotengine/godot/issues/111482) (FOV override), [#107731](https://github.com/godotengine/godot/issues/107731) (custom read without alpha logs errors) |
| Screen-space edge detection on depth | Yes (depth texture) | **No.** It inks everything, including floor and walls, unless you mask it, and there's no per-object ID buffer | Constant | No normals buffer on Compatibility ([screen-reading shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html)), so it misses creases and catches depth steps on the floor. Sable- and Borderlands-style whole-world ink isn't the brief |
| Screen-space on normals | **No**. Normal-roughness is Forward+ only | | | |

**Recommendation: inverted hull.** [eldskald/godot4-cel-shader](https://github.com/eldskald/godot4-cel-shader) (**MIT**, 308★, updated 2025-10 "to latest Godot version") has a 20-line `src/outline.gdshader`: `render_mode cull_front, unshaded, depth_draw_never`. It projects the normal into clip space and offsets `clip_position.xy` by `normalize(clip_normal.xy) / VIEWPORT_SIZE * clip_position.w * outline_width`, so the width is in pixels. It uses nothing Forward+-only. Copy it with attribution. Changes:

- **Colour:** a dark warm brown with a hint of the albedo (sample the albedo and multiply by about 0.3) rather than flat black. That is what gives the "soft ink" in Yoshida's line work.
- **Width variation:** Guilty Gear Xrd controlled outline thickness per vertex through vertex colour, and drew inner lines into the textures ([Motomura, *GuiltyGearXrd's Art Style: The X Factor Between 2D and 3D*, GDC 2015](https://www.gdcvault.com/play/1022031/GuiltyGearXrd-s-Art-Style-The)). A single `outline_width` of about 1.5–2 px (in `VIEWPORT_SIZE` units) at scale 0.6 is enough for the prototype. Per-vertex width can come later with the new character art.
- **Split normals:** `BaseMaterial3D.grow`'s own doc warns that extruding along normals leaves gaps at sharp corners, and suggests smooth or face-weighted normals ([BaseMaterial3D](https://docs.godotengine.org/en/stable/classes/class_basematerial3d.html)). The KayKit Knight has 5,328 vertices on only 3,004 unique positions across its 9 parts (counted from `Knight.glb`), so it has plenty of split vertices and **will crack**. The fix is to extrude along an averaged normal instead: bake per-position averaged normals into `COLOR` or `CUSTOM0` with an `EditorScenePostImport` script (about 30 lines), or in Blender on the new art. The fallback is the stencil preset, which has no cracks but no inner lines.
- **Applying it:** `GeometryInstance3D.material_overlay` renders "on top of any other active material for all the surfaces" ([GeometryInstance3D](https://docs.godotengine.org/en/stable/classes/class_geometryinstance3d.html)). Set it on each `MeshInstance3D` under the model in `character_view.gd`. That's one loop and doesn't touch the imported materials. KayKit characters are split into parts (arm, body, helmet, visor…), so each armour piece gets its own outline, which is a good fit for "bulky armour pieces".

## Recommended stack and ordering against the post quad

Draw order for one frame:

1. **Opaque:** world and characters with the ramp or toon material and painted albedo.
2. **Screen copy** (automatic; it's what the post quad reads).
3. **Transparent pass**, ordered by `render_priority`:
   - **Kuwahara quad**: `render_priority = -100`, `render_mode unshaded, depth_test_disabled, depth_draw_never, fog_disabled`. Draws first.
   - **Outlines**: the inverted-hull overlay is opaque (`depth_draw_never` but no alpha), so it gets **filtered along with the characters**. The lines come out soft and brushy, which is arguably the "soft ink" look. If they turn out too mushy, give the outline shader `ALPHA = 1.0` so it moves to the transparent pass and draws after the quad at `render_priority` > -100, staying crisp.
   - **Debug overlay** (priority 0 mesh, labels 10): draws after the quad and is never filtered.
4. **Environment tonemap and LUT** on everything.
5. **Canvas:** paper grain + wobble `ColorRect` on a `CanvasLayer` **below** the HUD layer (the HUD is a `CanvasLayer` at the default layer 1 in `demos/*.tscn`; `demo_menu.gd` is at 100). Grain and wobble also hit the 3D debug overlay. See the next section.

Maintained sources to copy (all MIT-compatible):

| Source | Licence | Use |
|---|---|---|
| [eldskald/godot4-cel-shader](https://github.com/eldskald/godot4-cel-shader) | MIT | Outline shader. Ramp-lit base as a reference (it uses a `diffuse_curve` global sampler) |
| [godotshaders Generalized Kuwahara](https://godotshaders.com/shader/generalized-kuwahara/) | MIT | Port from canvas to a spatial quad (swap `SCREEN_UV` and the screen-texture uniform) |
| [godotshaders Anisotropic Kuwahara](https://godotshaders.com/shader/anisotropic-kuwahara-filter/) / [Acerola Post-Processing](https://github.com/GarrettGunnell/Post-Processing) | MIT / MIT | Only if #14 wants the stroke direction |
| [PeterEve/godot-kuwahara](https://github.com/PeterEve/godot-kuwahara) | CC0 | Simplest starting point. Has a spatial variant. Not updated since 2022, but the code is small and uses no deprecated API by reading |
| [GDQuest/godot-shaders](https://github.com/GDQuest/godot-shaders) | Code MIT, **art CC-BY-NC-SA 4.0** | "Advanced toon shader", "3D outline" and "Unlit directional tint" as references. Don't copy the art. The repo is still mid-port to Godot 4 per its README |
| [jkyprian/gpuakf](https://github.com/jkyprian/gpuakf) | **GPL-3.0** | Read only |

On [godotshaders.com](https://godotshaders.com/license/) each shader carries its own licence (CC0, MIT or GPL-3). Check each page before copying.

## Debug overlay (`debug_draw.gd`)

`debug_draw.gd` is one `MeshInstance3D` + `ImmediateMesh` with an unshaded, alpha, `no_depth_test` StandardMaterial3D in `material_override`, plus billboard `Label3D`s at `render_priority` 10. F1 or \` toggles it via `static var shown`.

- **Kuwahara quad:** because the debug material is transparent and at priority 0, it draws **after** a quad at -100, so it stays crisp. It is also missing from the screen copy, so it never gets smeared. **No change needed**, as long as the quad stays a spatial quad. If the filter is ever moved to a canvas `ColorRect`, the lines and labels would be filtered and unreadable. In that case hide the `ColorRect` in the F1 handler whenever `shown` is true.
- **Grain and wobble (canvas):** these sit above all 3D, so they do touch the overlay. Hide that `CanvasLayer` while `shown` is true. That's about 2 lines in the existing `_unhandled_input`, via a group lookup.
- **Outlines:** the overlay is added by `character_view.gd` only to character meshes, so the debug mesh never gets one. Any future auto-apply over the whole tree must skip nodes with `material_override`, as #5 found.
- **Palette grade:** tonemapping and LUT apply to the whole 3D buffer, the unshaded debug colours included. A warm, desaturated LUT will dull `CYAN` and `MAGENTA` (`debug_draw.gd` constants) a little. That's acceptable for a dev view. If it hurts readability, bump their saturation rather than bypassing the grade.
- **Scale:** at `scaling_3d_scale` 0.6, Label3D text renders at 3D resolution and gets softer. If that matters, set `get_viewport().scaling_3d_scale = 1.0` while `shown` (1 line).

## Reference games (3D, similar goals)

| Game | What to take | Primary source |
|---|---|---|
| Team Fortress 2 (Valve, 2007) | Painterly look from painted albedo and a warped half-Lambert ramp. Rim light instead of outlines. Reads well at distance | [NPAR 2007 paper](https://steamcdn-a.akamaihd.net/apps/valve/2007/NPAR07_IllustrativeRenderingInTeamFortress2.pdf) |
| Guilty Gear Xrd (Arc System Works, 2014) | Inverted-hull outlines with per-vertex width, hand-tuned normals for clean shading, inner lines in texture | [GDC 2015 talk](https://www.gdcvault.com/play/1022031/GuiltyGearXrd-s-Art-Style-The) (free on GDC's YouTube: [video](https://www.youtube.com/watch?v=yhGjCzxJV3E)) |
| Valkyria Chronicles (SEGA, 2008) | Closest overall: a tactics game in 3D with the CANVAS engine's watercolour washes, sketchy outlines, hatching and a paper feel | [SEGA product page](https://valkyria.sega.com/vcswitch/information.php) (returned 503 when I checked, so the description comes from its search-index snippet) |
| Triangle Strategy (Square Enix/Artdink, 2022, UE4) | A modern FFT-lineage tactics game. HD-2D is sprites on 3D dioramas, so it's a reference for mood and palette, not for 3D character rendering | [Producer interview, Nintendo Life](https://www.nintendolife.com/news/2022/05/triangle-strategy-producers-talk-hd-2d-and-why-other-devs-havent-used-it) (secondary: a press interview) |

Vagrant Story and FFXII (both Yoshida character designs) are the obvious in-house precedents: painted textures and light lighting on low-poly 3D. I found no first-party technical write-up for either, so they're listed for mood only.

## Effort (rough)

| Step | Estimate |
|---|---|
| Shared `Environment` `.tres`: warm ambient, tonemap, saturation, 1D LUT; swap it into the 3 demo scenes | 1–2 h |
| `painted.gdshader`: albedo + half-Lambert ramp `light()` + optional rim; applied to characters via `character_view.gd` | 2–3 h |
| Outline: copy eldskald's `outline.gdshader`, warm tinted colour, `material_overlay` loop in `character_view.gd` | 1–2 h |
| Smoothed-normal bake (`EditorScenePostImport`) to fix hull cracks on split-normal meshes | 2–4 h |
| Grain + wobble canvas layer + F1 hook | 1–2 h |
| Generalized Kuwahara spatial quad + `scaling_3d_scale` setting + F1 check | 2–3 h |
| Web export check: shader compile hitch, frame time on a Retina laptop at scale 0.6/0.8/1.0, r=2/3 | 2–3 h |
| **Engineering total** | **about 2½–3 days** |
| Painted textures (art) | Depends on #13. Roughly ½–1 day per character atlas at 512² if repainting over existing UVs. The largest item |

Skipped on purpose: anisotropic Kuwahara (multi-pass SubViewport chain, add it if #14 asks for stroke direction), whole-world screen-space ink (off-brief), watercolour edge darkening and pigment turbulence (add after #14 if the look reads as "digital"), and per-vertex outline width (do it with the new character art).
