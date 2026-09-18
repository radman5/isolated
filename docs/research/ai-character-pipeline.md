# AI character and animation generation pipeline

Research for radman5/isolated#15 (part of #1). The art direction comes from #11: a painterly world in the style of Yoshida's FFT art, lean bodies with oversized armour pieces, seen mostly from a top-down follow camera. #13 decided that characters come from AI generators, and kept KayKit's `Rig_Medium` and its clips as the fallback. This note builds on [`character-sourcing.md`](https://github.com/radman5/isolated/blob/research/character-sourcing/docs/research/character-sourcing.md) (branch `research/character-sourcing`) and doesn't repeat it. Sources were checked on 2026-09-18.

**What this note is based on:** vendor docs, pricing and terms pages, the Tripo SDK source, the Godot 4.7 docs and itch.io staff posts. **Nothing was generated or imported for it.** Anything that only a hands-on run can show is marked **[try it]**.

## TL;DR

- **Recommended pipeline: AI makes the mesh and texture. We own the rig and the clips.**
  1. Paint or generate one concept sheet per character.
  2. Use **Meshy Pro ($20/mo)** for image-to-3D, generating the body and each armour piece separately.
  3. In **Blender** (free): remesh, then skin the lean body to our re-proportioned `Rig_Medium`, and rigid-bind each armour piece to one bone, as in #13 Option 1.
  4. Paint over the texture.
  5. Play the **existing KayKit clips unchanged**, so `IMPACT`, `handslot` and `_strip_root_motion` all keep working.
  6. Fill gaps (heavy two-handers, boss moves) with **Uthana** text-to-motion on that same rig. It's pay-as-you-go at about $0.03 per second, and paid output is ours.
- **Running cost:** about **$20–25 a month** while characters are being made (Meshy Pro plus a few dollars of Uthana), and **$0** otherwise. Add **$14.99** once if you want KayKit's `.blend` rig. Meshy Pro's 1,000 credits cover about **3–4 characters a month** (see the budget below).
- **Why not use the generators' own auto-rigs?** They are humanoid rigs with Mixamo-style names, or unpublished ones. They don't have `handslot` bones, their rest rolls differ from KayKit's, and they skin armour smoothly across joints, so pauldrons would bend like cloth. They could still play KayKit clips through Godot's `RetargetModifier3D` (4.4+), but that isn't proven. Keep it as the plan-B spike, not the default.
- **Licences:** use **paid tiers for anything that ships**. Meshy Free is CC BY 4.0 and Meshy owns the output. Tripo Free is labelled non-commercial. DeepMotion Free is non-commercial. Cascadeur Free is non-commercial. **Hunyuan3D's open weights may not be used, and their outputs may not be distributed, in the EU, the UK or South Korea.**
- **itch.io:** on the game page, set *Generative AI disclosure* to **Yes → Graphics**. It is *required* only for asset pages, and optional but encouraged for games. Tick it anyway.

## The ticket's questions, per tool

### Model generators

| | **Meshy** | **Tripo** | **Rodin / Hyper3D** | **Hunyuan3D (Tencent)** |
|---|---|---|---|---|
| **Inputs** | Text, one image, multi-image | Text, image, multiview | Text, 1–5 images | Image (open weights, run it yourself) |
| **Topology controls** | Remesh (5 cr), Smart Topology models, face-count limits ([API pricing](https://docs.meshy.ai/en/api/pricing)) | `face_limit`, `quad`, `smart_low_poly`, `smart_lowpoly()` post-step ([SDK](https://github.com/VAST-AI-Research/tripo-python-sdk/blob/master/tripo3d/client.py)) | `mesh_mode` Raw/Quad, "Smart Low-Poly" on Creator, "High-Poly Quads" on Business ([pricing](https://hyper3d.ai/pricing), [API](https://docs.hyper3d.ai/en/api-specification/rodin-gen2-5)) | None built in. Remesh yourself. |
| **Separate parts** | *Auto Split* is aimed at 3D printing: it cuts along boundaries and caps the cuts ([docs](https://docs.meshy.ai/en/webapp/guides/3d-model/auto-split)). That isn't armour layered over a body. | `generate_parts`, `mesh_segmentation()`, `mesh_completion(part_names)` ([SDK](https://github.com/VAST-AI-Research/tripo-python-sdk/blob/master/tripo3d/client.py)) | *BANG* splits an asset into sub-models, with a strength parameter ([API](https://developer.hyper3d.ai/api-specification/bang_reset_v)) | *Hunyuan3D-Part*: P3-SAM segments, X-Part completes parts ([repo](https://github.com/Tencent-Hunyuan/Hunyuan3D-Part)) |
| **Re-texture / restyle** | Retexture from a text or image prompt, 10 cr ([API pricing](https://docs.meshy.ai/en/api/pricing)) | `texture_model(part_names=…)`. `stylize_model` only offers lego, voxel, voronoi and minecraft ([SDK models](https://github.com/VAST-AI-Research/tripo-python-sdk/blob/master/tripo3d/models.py)). | Texture tiers, `uhd_texture` | Separate paint model |
| **Auto-rig** | Humanoid, quadruped, "Smart Rig" beta. 5 cr. GLB/FBX. Needs a T-pose with feet apart, facing +Z, under 300k faces ([API](https://docs.meshy.ai/en/api/rigging-and-animation), [help](https://help.meshy.ai/en/articles/16231707-how-to-create-3d-animation-with-auto-rigging)). **Bone names aren't published**, though Meshy's marketing says "Mixamo-compatible". | `rig_type` biped…serpentine, `spec` **`mixamo`** or `tripo`, GLB/FBX. `check_riggable()` runs first ([SDK](https://github.com/VAST-AI-Research/tripo-python-sdk/blob/master/tripo3d/client.py)). | No rig in the generation API. The site only says outputs are "rigging-ready". | None |
| **Clips** | 590+ library clips, including sword slashes, parries and archery. 3 cr per clip. Text-to-motion 3–10 cr ([library](https://docs.meshy.ai/en/api/animation-library)). | 11 presets: idle, walk, run, slash, shoot, hurt… | None | None |
| **Price** | Free: 100 cr/mo. **Pro: $20/mo, 1,000 cr.** Studio from $70/mo ([pricing](https://www.meshy.ai/pricing), [help](https://help.meshy.ai/en/articles/12062933-meshy-pricing-plans-free-pro-studio-enterprise)) | Free: 300 cr/mo. Pro about $19.90/mo, 3,000 cr (Tripo's pricing page returns 403 to fetchers, so these figures come from search snippets and are **unverified**) | Free: pay $1.50 per credit. **Creator $30/mo** (about 60 models). Business $120/mo ([pricing](https://hyper3d.ai/pricing)) | Free weights plus your own GPU |
| **Who owns output** | **Free: Meshy owns it and you get CC BY 4.0.** Paid: you own it. Meshy may train on non-Enterprise inputs and outputs ([ToS §2.9, §3.2](https://www.meshy.ai/terms-of-use)). The pricing page claims no training without consent, which contradicts the ToS. The ToS governs. | Free: public, CC BY 4.0, labelled "Non-Commercial". Paid: private, commercial. Tripo's own blog calls the free-tier terms ambiguous ([search snippets of tripo3d.ai](https://www.tripo3d.ai/blog/ai-3d-commercial-use-license); the pages return 403, so **unverified**). | Rodin output: no usage limits stated. Private flag on paid plans ([ToS §5](https://hyper3d.ai/legal/terms)). | Tencent claims no rights in outputs (§6.d). **Territory excludes the EU, UK and South Korea (§1.l), and outputs may not be used or distributed outside the Territory (§5.c).** You may not use outputs to train other models (§5.b) ([licence](https://huggingface.co/tencent/Hunyuan3D-2.1/blob/main/LICENSE)). |

Notes:

- **Hunyuan3D:** "armour" and "licence" in the tickets suggest UK spelling. **If you are in the UK or EU, the open-weights licence rules Hunyuan3D out**, including its Part pipeline under a similar community licence. Tencent's hosted service has separate terms, which I didn't check.
- **Rodin** has the best part-splitting story (BANG) and quad output, but no rig or clips. Since the recommended pipeline rigs in Blender anyway, that doesn't matter. It is the swap-in if Meshy's armour pieces come out poorly. **[try it]**
- **Tripo** has the most controllable API on paper: a `mixamo` rig spec, `generate_parts` and `smart_low_poly`. I couldn't read its terms first-hand, though. Read [tripo3d.ai/terms](https://www.tripo3d.ai/terms) in a browser before paying.

### Motion generators and tools

| | **Uthana** | **Meshy clips** | **DeepMotion** | **Cascadeur** | **Mixamo** |
|---|---|---|---|---|---|
| What | Text-to-motion, video-to-motion, library, stitching and looping | Library plus text-to-motion on Meshy rigs | Video-to-mocap (Animate 3D), text-to-motion (SayMotion) | Keyframe animation tool with AutoPosing and AutoPhysics | Auto-rig plus free library |
| **Uses our rig?** | **Yes.** Upload an FBX/GLB humanoid under 30 MB, it auto-rigs, and it can export motion on that character as FBX/GLB ([docs](https://uthana.com/docs/api/capabilities/auto-rig-and-add-character)). **[try it]**: does it keep our bone names or impose its own skeleton? | Only on Meshy's own rig | Custom FBX/GLB upload. GLB export only for custom characters ([pricing](https://www.deepmotion.com/pricing-animate3d)) | Yes. Import FBX/glTF. Retargeting needs **Pro** ([plans](https://cascadeur.com/plans)). | Its own skeleton only |
| Price | Pay-as-you-go: text-to-motion $0.02–0.10/s, video $0.05/s, auto-rig $0.15 ([pricing](https://uthana.com/pricing)) | 3 cr per clip, 3–10 cr per text clip | From about $9/mo (pricing table didn't render, so unverified) | Free / Indie $14/mo / Pro $36/mo | Free |
| **Licence** | Paid: you own it. Free: Uthana owns it and you get CC BY 4.0 with the credit line "Animation generated with Uthana (uthana.com)". Uthana may train on customer data ([terms](https://uthana.com/terms)). | As for Meshy models | **Free is "personal, non-commercial"**. Commercial use needs a paid plan ([pricing](https://www.deepmotion.com/pricing-animate3d)). | **Free: no commercial use and no FBX/glTF export.** Indie: commercial only under $100k revenue or funding. Asks for a credit ([plans](https://cascadeur.com/plans), [licensing FAQ](https://cascadeur.com/blog/general/cascadeurs-new-licensing-structure-comprehensive-faq)). | Royalty-free, as covered in #13 |

DeepMotion needs someone filmed performing the move, which is poor for tuned sword timing. Cascadeur is the tool if a clip needs hand-fixing. Its free tier can't export, so budget **Indie at $14/mo only for the months you need it**.

## Q1: What rig do they export, and does it import cleanly into Godot 4.7?

- **Format:** use GLB throughout. Godot imports glTF natively, and FBX through ufbx. Meshy, Tripo and Uthana all export GLB.
- **Skeletons:** Tripo's `spec="mixamo"` and Meshy's claimed Mixamo naming both use common English bone names. Godot's BoneMap auto-mapping "uses pattern matching for the bone names", so these rigs should auto-map to `SkeletonProfileHumanoid` ([Godot 4.7 docs](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/retargeting_3d_skeletons.html)). Mixamo-style rigs have shoulder bones, so they avoid KayKit's missing-shoulder problem from #13. **[try it]**: Meshy's exact bone list isn't documented, so import one rig and read the BoneMap result.
- **Playing KayKit clips on a generator's rig** has two routes:
  - **Import-time BoneMap** on both KayKit and the generated rig. #13 already covers the costs: no KayKit shoulders, `handslot` dropped, renamed paths in `character_view.gd`.
  - **`RetargetModifier3D`** (added in Godot 4.4, [PR #97824](https://github.com/godotengine/godot/pull/97824), [class ref](https://docs.godotengine.org/en/latest/classes/class_retargetmodifier3d.html)). A hidden KayKit skeleton plays the clips, and the generated skeleton is a child of the modifier. It keeps its own rests. With `use_global_pose` off, the bodies can have different proportions. Its `SkeletonProfile` is "only a list of bone names", so both skeletons must share those names. You'd rename the generated bones to KayKit's in Blender, or use a humanoid-profile BoneMap on both. Weapons then need a `handslot` bone added to the generated rig, or a `BoneAttachment3D` offset on its hand.

  Both routes are **untested**, and they cost more than skinning to `Rig_Medium` in the first place.
- **Why the recommendation skips the AI rig:** we have to open Blender anyway to rigid-bind armour. Once we're there, binding the body to our own `Rig_Medium` is about an hour. It gives us KayKit's bone names, rolls and `handslot` bones for free, and needs no retargeting code.

  One known risk: Blender's *Automatic Weights* can fail on non-manifold AI meshes. Remesh first (Meshy Remesh, or Blender Voxel Remesh then Decimate).

## Q2: How do you keep a character consistent, and get separate armour?

- **Consistency:** the generators don't remember a character between runs. Keep a character consistent by fixing the input, not the prompt.
  - Make one **concept sheet** per character: front, side and back views of the lean body in a T-pose with feet apart, the stance Meshy asks for. Feed that to multi-image-to-3D (Meshy, Tripo multiview, Rodin with up to 5 images).
  - **Generate once, keep the file, and edit from there.** Don't regenerate a finished character.
  - For families (enemy variants), **share the body mesh and swap armour pieces**. Rigid pieces re-parent freely, as #13 noted.
- **Separate armour:** generate each piece on its own (pauldron, gauntlet, greave, cuirass) from a crop of the concept sheet, as an image-to-3D prop. Then place and rigid-bind it in Blender.

  Built-in splitters (Tripo `generate_parts`, Rodin BANG, Hunyuan3D-Part) cut up a *fused* mesh. They leave holes or guessed surfaces under each plate, and they tend to split along limbs rather than along armour layers. **[try it]** on one Tripo or Rodin generation. If the split comes out clean, it saves cropping work.

## Q3: Can the textures be made painterly, and is the topology usable?

- **Textures:** AI textures have lighting baked in and come on auto-unwrapped UVs, which are fragmented islands that are hard to paint across.
  - **Workflow:** remesh or decimate, auto-unwrap to clean islands in Blender, and bake the AI texture onto the new UVs. Then paint over it in Blender Texture Paint to flatten the baked light and push the palette.
  - The #12 post-process and outline pass does much of the "painterly" work, so the texture only needs flat, soft colour. One atlas of 1024² or smaller per character is plenty from the top-down camera.
  - Meshy's image-prompt retexture, fed a painted swatch, is worth one try before hand-painting. **[try it]**
- **Topology:** raw outputs are dense triangle soup, so all four tools add a reduction step (table above). For a top-down camera, aim for about **3–6k triangles for the body and 300–1,000 per armour piece**.
  - Armour is rigid and deforms nothing, so messy topology on it is harmless. Only the body's elbows, knees and hips need clean edge flow, and a quad remesh is usually enough there. **[try it]**

## Q4: Can the combat clips keep their tuned timing?

- **Keep the KayKit clips and retarget them. Don't replace them with generated ones.** `IMPACT` is a time in seconds, measured as the peak speed of `handslot.r` for each clip. `character_view.gd` then time-warps each swing around that moment.

  On a body skinned to re-proportioned `Rig_Medium`, the clips play unchanged. Only the ~10-line `_strip_root_motion` change from #13 is needed, and the `IMPACT` values stay valid because they're times, not positions.
- **Generated clips can join the same system.** Generate one on our rig (Uthana with our uploaded character), add it to an `AnimationLibrary`, and measure its `IMPACT` the same way (peak `handslot.r` speed). The time-warp works for any clip with a measured `IMPACT`.

  On a generator's own rig, there's no `handslot` bone to measure with or attach to. That's another reason to generate onto our rig.
- **Quality risk:** text-to-motion quality for readable, weighty sword swings is unproven. **[try it]**: generate two or three swings in Uthana and compare them against `Melee_1H_Attack_Chop` in the arena demo. Use generated clips for moves KayKit doesn't have (two-handers, the Heavy's slam, boss moves), not to replace tuned ones.

## Q5: Who owns the output?

| Tool | Free tier | Paid tier |
|---|---|---|
| Meshy | Meshy owns it. You get CC BY 4.0 and must credit Meshy. | You own it. Meshy may train on it. |
| Tripo | Public, CC BY 4.0, labelled non-commercial (**unverified**, terms page blocked) | Private, commercial (unverified) |
| Rodin | Public gallery unless marked private | "Unlimited export and any use" |
| Hunyuan3D | No rights claimed. **Territory-restricted: not EU, UK or South Korea.** | Needs a licence only above 1M monthly active users |
| Uthana | Uthana owns it. You get CC BY 4.0 with a credit line. | You own it. Uthana may train on it. |
| DeepMotion | Non-commercial | Commercial |
| Cascadeur | Non-commercial, no export | Indie: under $100k. Pro: unlimited. |
| Mixamo | Royalty-free | n/a |

Rule of thumb: **generate anything that ships on a paid month.** Separately, the Synty and Unity Asset Store EULAs forbid feeding their assets into generative AI (#13), so don't use them as generator inputs.

## Q6: What must itch.io disclosure cover?

The project edit page has a **Generative AI disclosure** field. If you answer yes, it asks which kinds: **Graphics, Sound, Text & Dialog, Code**. The page is then auto-tagged *AI Generated* plus sub-tags, and "no" gets tagged *No AI*.

The field is **required for asset creators**. Untagged AI assets, "even if modified afterwards", are removed from browse indexing. For games it is encouraged, not mandatory, and works as a filter tag ([staff post, 2024-11-20](https://itch.io/t/4309690/generative-ai-disclosure-tagging), [quality guidelines](https://itch.io/docs/creators/quality-guidelines)). Using AI "as an informational resource" doesn't count. AI output in the build does.

**For this game:** answer **Yes → Graphics** (models, textures, and generated motion if we use it). Add **Code** if AI-written code counts under your reading of "results of generative AI". Staff didn't address code-assist tools directly, so that one is a judgement call.

## Recommended pipeline and costs

Steps per character:

1. **Concept sheet:** hand-drawn or image-generated. Front, side and back views, lean body, T-pose with feet apart. Plus one crop per armour piece.
2. **Meshy Pro:** multi-image-to-3D for the body (30 cr), and image-to-3D for about 5 armour pieces (5 × 30 cr). Allow about 2 retries on the body (60 cr) and one retexture (10 cr). **About 250 credits, or 3–4 characters per 1,000-credit month.** This is an estimate. Plan for rerolls.
3. **Blender:**
   - Remesh or decimate the body to 3–6k triangles and re-unwrap.
   - Re-proportion `Rig_Medium` and skin the body with Automatic Weights. See #13 Option 1: keep bone names and rolls.
   - Rigid-bind each armour piece to one bone.
   - Bake the texture to the new UVs, then paint over it.
   - Export GLB with the armature named `Rig_Medium`.
4. **Godot:** make the ~10-line `_strip_root_motion` change from #13, then drop the model into `character_view.gd`'s `model` export. All KayKit clips, `IMPACT` values and `handslot` weapons work.
5. **Extra clips (optional):** upload the character to Uthana, generate the move, export GLB, and measure `IMPACT`.

| Item | Cost |
|---|---|
| Meshy Pro | $20/mo, only in months when characters are being made |
| Uthana | Pay-as-you-go. A 2 s clip at $0.03/s is about $0.06, plus a one-off $0.15 rig per character. Budget **$5**. |
| KayKit Character Animations SOURCE (`.blend` rig) | $14.99 once (optional, from #13) |
| Blender | Free |
| Cascadeur Indie | $14/mo, only if a clip needs hand-fixing |
| **Total** | **about $20–25/mo while producing characters, about $40 one-off overall to try it** |

Effort: about half a day of Blender per character on top of #13's estimate. #13 put a hand-built character at 1–3 days, and the AI mesh saves most of the block-out and modelling. **[try it]**

**First step (for #14):** a one-day bake-off using free tiers for *evaluation only* (free outputs are CC BY or non-commercial, so don't ship them).

1. Feed one concept sheet to Meshy, Tripo and Rodin.
2. Compare the body mesh, armour pieces, remesh quality and retexture.
3. Push the winner through steps 3–4 and play the arena demo.

If Meshy loses on armour pieces, switch that step to Rodin Creator ($30/mo) or Tripo Pro (about $20/mo, after reading its terms). Nothing else in the pipeline changes.

## Not verified

- No generation, rig or import was run. Every **[try it]** above needs a hands-on check.
- Meshy's skeleton bone list isn't in its docs.
- Tripo's pricing and terms, and DeepMotion's plan table, couldn't be fetched directly. Those figures are from search snippets.
- Whether Uthana keeps our bone names on export is untested.
- `RetargetModifier3D` from a KayKit source is a reasoned plan B, not a tested one.
