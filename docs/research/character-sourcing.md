# Character sourcing: lean bodies, bulky armour

Research for radman5/isolated#13 (part of #1). Art direction is from #11: lean bodies with oversized armour pieces, in the style of Yoshida's FFT art, seen mostly from a top-down follow camera. Sources checked 2026-09-18.

## TL;DR

- **Recommended: reskin the rig we already have.** Build new lean characters in Blender on KayKit's own `Rig_Medium` armature. Keep the same bone names, hierarchy and rest orientations, and change only the bone lengths. Make each armour piece a separate rigid mesh bound 100% to one bone. Every current clip, the `IMPACT` timings and the `handslot` weapon mounts keep working. The code change is about 10 lines in `character_view.gd`, which drops KayKit's baked bone-length keys. **Cost: $0**, or $14.99 if you want KayKit's `.blend` rig. **Effort: about 1–3 days per character** in Blender, plus a one-off half day to prove the pipeline.
- **Godot's own retargeting (BoneMap + SkeletonProfileHumanoid) also works, but costs more here.** KayKit has no shoulder bones, and the profile marks those as required. It also has `handslot` bones that the profile doesn't know about, and renaming breaks the bone and node names the code looks up. Use it only if a character arrives on a different skeleton (Mixamo, Quaternius, Synty).
- **Off-the-shelf packs don't match the silhouette.** KayKit is chunky, Synty and Quaternius are close to realistic, and none of them has *oversized* armour on a *lean* body. Buy packs for bodies and parts to kitbash, not finished characters.
- **Commissioning** a low-poly rigged character runs from about **$350–400** (hobby/freelance posting) to **$2,000–5,000** (studio guide). Ask the artist to skin to our `Rig_Medium`, and the animations come free.

## What the prototype has

- `character_view.gd` loads six KayKit clip files (`assets/kaykit/animations/Rig_Medium_*.glb`). It plays them on a model at `Rig_Medium/Skeleton3D`, attaches weapons with `BoneAttachment3D` to `handslot.r` / `handslot.l`, and strips sideways root motion from tracks ending in `:root`. Swing timing depends on the measured `IMPACT` seconds per clip.
- Clips in use: `Idle_A`, `Walking_A`, `Running_A`, `Dodge_*`, `Hit_A`, `Death_A`, five `Melee_1H_Attack_*`, `Melee_Blocking`, `Ranged_Bow_Draw/Release/Aiming_Idle`, and `Skeletons_*`.
- **The skeleton** (read from `Knight.glb`) has 23 bones: `root, hips, spine, chest, head`, plus per side `upperarm, lowerarm, wrist, hand, handslot, upperleg, lowerleg, foot, toes`. **It has no neck, no shoulder/clavicle and no fingers.**
- **Track contents** (parsed from the glb files): each clip has rotation, translation *and* scale channels on every bone. Most translation keys are constant, so they just bake in KayKit's bone lengths. The translations that actually move are on `hips`, `root`, `upperarm.*`, `upperleg.*` and `handslot.*`. KayKit uses those to fake a shoulder shrug and hip shift, because it has no clavicles. A few `General`/`Special` clips also animate scale.
- Licence: KayKit Character Animations 1.1 and the Adventurers pack are **CC0** (`assets/kaykit/licenses/`, [KayKit Adventurers](https://kaylousberg.itch.io/kaykit-adventurers)).

That last point decides the question. **The clips are only rotation data plus a few offsets.** Any mesh skinned to a skeleton with the same names and rest rotations will play them.

## Option 1 (recommended): new meshes on KayKit's `Rig_Medium`

How:

1. Import `Knight.glb` into Blender, or use the `.blend` from KayKit Character Animations **SOURCE ($14.99+)**. That page also says the clips "will work on other humanoid characters too, use your engine's retargeting functions for that." ([itch page](https://kaylousberg.itch.io/kaykit-character-animations))
2. In Edit Mode, move bone heads and tails to lean FFT proportions: longer legs and forearms, narrower hips and chest, a smaller head. **Don't change bone roll or rotation, and don't rename anything.**
3. Body: start from Blender Studio's **Human Base Meshes** (CC0, 17 meshes, stylized and realistic, Blender 3.2+) and decimate, or box-model a simple one. The camera is top-down, so a 2–4k-triangle body is plenty. ([Blender dev docs](https://developer.blender.org/docs/features/asset_system/asset_bundles/human_base_meshes/), [release notes](https://developer.blender.org/docs/release_notes/3.6/asset_bundles/))
4. Armour: make pauldrons, gauntlets, greaves and breastplates as separate chunky meshes, each weighted **100% to one bone**. Pauldron goes to `upperarm`, gauntlet to `lowerarm`/`wrist`, greave to `lowerleg`, cuirass to `chest`. Rigid pieces are the look we want, and they need no weight painting. This is also the easiest way to kitbash: reuse a piece on several characters by re-parenting it.
5. Hand-paint one small atlas (the painterly direction in #11/#12). Export glb with the armature still named `Rig_Medium`.
6. In `_strip_root_motion`, drop the translation and scale tracks on every bone except `root`/`hips`, and scale the `hips` Y keys by (new leg length ÷ KayKit leg length). This is what Godot's import option *Remove Tracks > Unimportant Positions* does, since only `root_bone` and `scale_base_bone` keep position tracks. Without this, the baked KayKit offsets "change the body shape unpredictably". ([Godot: Retargeting 3D skeletons](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/retargeting_3d_skeletons.html))

What it costs:

- **Losing the upperarm/upperleg translation keys** removes KayKit's shoulder shrug and hip shift. Top-down, that barely shows. If it does, add *(key − KayKit rest)* to the new rest instead of dropping the keys, which is a few more lines.
- **Different limb lengths change contact poses.** Two-hand grips and the bow draw can have the off hand miss the weapon by a few cm, and feet can slide slightly at the old stride. `run_speed`/`walk_speed` in `character_view.gd` are the knobs for the slide. Recheck the bow in #14.
- **`IMPACT` timings stay valid** because they measure time, not position. Re-measure only if limb speed looks off.

Effort: a half day to prove it with one character, then about 1–3 days per new character (block-out, armour set, paint). This is the only option where **no combat animation work is lost and no code paths change**.

## Option 2: Godot's BoneMap / SkeletonProfileHumanoid retargeting

How it works: in the import dock you give each skeleton a `BoneMap` with `SkeletonProfileHumanoid` (56 bones). Options such as *Rename Bones*, *Unique Node* (`GeneralSkeleton`), *Overwrite Axis*, *Fix Silhouette* and *Normalize Position Tracks* unify the rests, so any two mapped rigs can share an `AnimationLibrary`. The docs say: "To share animations in Godot, it is necessary to match Bone Rests as well as Bone Names." Retargeting happens only **at import**. ([Godot docs](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/retargeting_3d_skeletons.html), [class ref](https://docs.godotengine.org/en/stable/classes/class_skeletonprofilehumanoid.html))

Problems with KayKit specifically:

- The profile marks 17 bones as `required`: Hips, Spine, Head, both Shoulders, Upper/LowerArm, Hand, Upper/LowerLeg and Foot ([`skeleton_profile.cpp`](https://github.com/godotengine/godot/blob/master/scene/resources/skeleton_profile.cpp)). **KayKit has no Shoulder bones.** The docs describe mapping problems as warnings that don't block import. Arms parented straight to Chest *should* still retarget, but I haven't tested it.
- `wrist.*` vs `hand.*` has to be mapped by hand. `handslot.*` has no profile slot. With *Unmapped Bones: Remove*, their tracks are dropped, including the bow-hand motion in 13 CombatRanged clips. The new rig then needs its own weapon bone, or a `BoneAttachment3D` with an offset on `RightHand`.
- *Rename Bones* and *Unique Node* change `Rig_Medium/Skeleton3D`, `handslot.r` and the `:root` path suffix. `character_view.gd` hard-codes all three.

Use it when: a character comes on a foreign skeleton. That could be Mixamo, the Quaternius universal rig, or Synty's Mecanim-style rig. Retargeting all six KayKit glbs once to the humanoid profile is then cheaper than re-rigging the character.

## Option 3: Mixamo or Rigify

- **Mixamo** auto-rigs an uploaded T-pose mesh and has a large free clip library. Characters and animations are royalty-free for commercial use with no credit required. The one restriction is that you can't redistribute the raw files as an asset product ([Adobe Mixamo FAQ](https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html)). The Mixamo skeleton has shoulders and fingers, so it auto-maps well to `SkeletonProfileHumanoid`. You'd still need Option 2 to play KayKit clips on it. It's worth it only if we want Mixamo's clips too.
- **Rigify** (Blender's rig generator) gives a full animator's control rig. The engine then needs only the `DEF-` deform bones, which means cleanup or a helper add-on before export. Use it only if we start hand-keying new combat clips in Blender, and even then we could key directly on `Rig_Medium`.

## Asset packs and kits

| Source | Licence | Price | Silhouette fit | Notes |
|---|---|---|---|---|
| **KayKit** Adventurers / Animations | CC0 ([page](https://kaylousberg.itch.io/kaykit-adventurers)) | Free; EXTRA $7.95, SOURCE $11.95; animation SOURCE $14.99 | Poor: big head, stubby limbs | Our rig and clip source. Keep for animations. |
| **Quaternius** Universal Base Characters | CC0 | Standard free, Pro $20, Source $20/mo | Bodies only: "Superhero, Regular, and Teen" builds, about 13k tris | "Humanoid Rig compatible with retargeting in any engine", Godot 4.3+ ([page](https://quaternius.com/packs/universalbasecharacters.html)). Good lean body to kitbash on, but no armour, and too many tris for us. |
| **Quaternius** Universal Animation Library | CC0 | Standard/Pro free, Source paid | n/a (animations) | 120+ clips on the same universal rig ([page](https://quaternius.com/packs/universalanimationlibrary.html)). A second clip source if we go the Option 2 route. |
| **Synty** POLYGON (e.g. Fantasy Kingdom) | Synty EULA: "not limited by game engine", 5 seats, **no generative-AI use** ([EULA](https://syntystore.com/pages/end-user-licence-agreement)) | Fantasy Kingdom $175 on sale ($349.99 list) | Poor: realistic low-poly proportions, flat-shaded | 22 characters, not modular, Mecanim rig, now ships Godot 4.5.1+ packages ([page](https://syntystore.com/products/polygon-fantasy-kingdom)). Sidekick modular creator is Unity/Unreal only (there is a community Godot port). |
| **Unity Asset Store** sellers | Asset Store EULA §2.2.1: licence to incorporate the asset into "an electronic application or digital media". **The clause doesn't name an engine.** Only "Restricted Assets" (flagged per listing) carry their own terms. The EULA bans use as AI/ML input. ([EULA](https://unity.com/legal/as-terms)) | varies | varies | Godot use is fine for non-Restricted assets. Check each listing for the Restricted flag and the formats (need FBX/glTF, not Unity prefabs only). |
| **itch.io** sellers | Per-page licence | usually $0–20 | varies | Read each page's licence. Many are CC0 or CC-BY, some forbid redistribution of source. Good for single armour parts. |

None of these ships the FFT look finished. **Treat packs as parts bins**: a Quaternius/Human-Base body, plus armour shapes blocked out in Blender, with painted textures.

## Generator tools

- **Meshy** and similar text/image-to-3D tools with auto-rigging: free-tier outputs are **CC BY 4.0** (credit Meshy), and paid tiers give you ownership ([pricing](https://www.meshy.ai/pricing)). Output meshes are dense and messy, which doesn't suit clean, chunky, hand-painted armour. At most, use them for concept block-outs of armour pieces that you then retopologize.
- **Licence clash:** the Synty EULA and the Unity Asset Store EULA both forbid feeding their assets into generative AI. Don't mix those sources with generator workflows.

## Commissioning

- Low-poly, rigged and weighted, 1,700–2,000 tris, modular parts: **$350–400 fixed, 7–14 days** (Polycount job post, 2025; [thread](https://polycount.com/discussion/238743/paid-low-poly-character-artist-rigger-modular-customization-assets-1-700-2-000-tris)). The page blocked direct fetch, so this is seen via the search snippet.
- Outsourcing guide: stylized character for mid-core games **$2,000–5,000**. Freelance rates run $15–30/h entry, $30–80/h mid and $50–150+/h senior ([RocketBrush](https://rocketbrush.com/blog/3d-character-art-prices-guide)). This is a vendor's own price guide, so treat it as an upper bound.
- **Brief to give:** "skin to the supplied `Rig_Medium` armature, don't change bone names or rolls, rigid-bind armour pieces, one ≤1024² hand-painted atlas". That cuts out rigging cost and keeps every existing clip.

## Recommendation

1. **Now (#14 style test):** Option 1 for the player only. Set aside half a day for the `_strip_root_motion` change and bone re-proportioning, then 1–2 days to model and paint. **$0.**
2. If the pipeline holds, do enemies the same way. Share armour pieces between them, since rigid pieces can be re-parented freely.
3. If Blender time becomes the bottleneck, **commission against our rig**: budget about $400–1,500 per character, depending on the artist and how much painting is involved.
4. Keep Option 2 (BoneMap) in reserve for any character that arrives on a foreign skeleton. Try it on one KayKit clip file before committing to it, because of the shoulder, `handslot` and renaming problems above.

Not verified here: nothing was imported into Godot for this note. The findings on track contents come from parsing the repo's glb files, and the behaviour of Options 1 and 2 comes from the Godot docs and source. The style test (#14) should confirm both.
