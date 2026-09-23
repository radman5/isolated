# Sourcing a multi-legged creature: a rigged, animated six-legged barkling

Research for radman5/isolated#21 (part of #1). The barkling is defined in #17 and `CONTEXT.md`: a small, weak, bark-armoured forest beetle that passes for a mossy stump and unfolds when the player comes within about 4m. The pipeline from #15 ([`ai-character-pipeline.md`](https://github.com/radman5/isolated/blob/research/ai-character-pipeline/docs/research/ai-character-pipeline.md)) is Meshy Pro meshes on KayKit `Rig_Medium`, with Uthana for new humanoid clips, paid-tier output only, and a light web export. This note doesn't repeat that one. Sources were checked on 2026-09-23.

**What this note is based on:** vendor docs, help-centre pages, the Tripo SDK source, store and licence pages, and the Godot docs. **Nothing was generated, rigged or imported.** Anything only a hands-on run can show is marked **[try it]**. Time estimates are my own judgement, not sourced.

## TL;DR

- **Feasible. Keep the barkling six-legged.** No AI tool will hand us a finished, animated beetle, but a beetle is the *easiest* creature to rig by hand: an exoskeleton is rigid segments, so every body part is **rigid-bound to one bone**, the same trick #15 already uses for armour. No weight painting.
- **Recommended route:**
  1. **Meshy Pro** (already paid for) image-to-3D of the barkling in a neutral pose, legs splayed and clear of the body. Or generate the shell, head and one leg separately and duplicate the leg.
  2. **Blender:** hand-build a ~25-bone armature (root, body, head, 2 mandibles, 6 legs × 3 segments, optional shell plate). Split the mesh into parts and parent each to its bone.
  3. **Keyframe the clips in Blender:** idle, walk (tripod gait), lunge/bite, hit, stagger, death, plus the stump "unfold" that #17's first encounter needs. Export GLB.
- **Cost:** **$0 extra** (Meshy Pro is already in the budget; Blender is free). **About 4–6 working days** for someone comfortable in Blender, 8–10 if learning as you go. That's roughly 5% of a 4–5 month MVP.
- **AI tools:** only **Tripo** has a six-legged rig (`rig_type="hexapod"`), and it ships **one** hexapod clip (walk). Meshy rigs humanoids and quadrupeds (quadrupeds get walk only); its "Smart Rig" beta takes custom creatures but its animation library doesn't support them. **Rodin** has no rigging. **Uthana** is humanoid-only. So attack, hit, stagger and death are hand-keyed whichever route you take. Tripo's hexapod rig is an optional one-day shortcut to test, not the plan.
- **Ready-made beetles:** there are **no CC0 animated beetles** from Quaternius or Kenney. Paid ones exist (a €3 itch.io armoured beetle; cute Omabuarts beetles with attack/hit/death), but they're FBX, the wrong art style, and mostly 2K-textured. Good as a **placeholder or animation reference**, not as the shipped barkling.
- **Procedural leg IK** (Godot 4.6+ `TwoBoneIK3D`, six legs in one node) works but is a coding project on top of the keyed clips. **Skip it for the MVP.** A small beetle seen from a top-down camera reads fine with a keyed walk cycle.
- **Fallback verdict:** the hunched upright beetle on `Rig_Medium` is **not needed**. It saves perhaps 2–3 days (it reuses KayKit clips), but it looks like a man in a beetle suit. Keep it only as the escape hatch if the hand-keyed clips slip past a one-week timebox.

## Q1: Can the AI tools rig or animate a six-legged creature?

| | Rig for six legs? | Clips for it? | Source |
|---|---|---|---|
| **Meshy** | **No.** Webapp auto-rig offers Humanoid, Quadruped ("four-legged animals and creatures") and **Smart Rig (Beta)** "for custom or fantasy creatures that don't fit standard categories". The API rigging endpoint is humanoid-only: it's "not suitable for … Non-humanoid assets". | Quadrupeds: "walking is the only animation we support for quadrupeds." **"Smart-rigged models currently aren't supported by our animation library."** | [Help: auto-rigging](https://help.meshy.ai/en/articles/16231707-how-to-create-3d-animation-with-auto-rigging), [API: rigging](https://docs.meshy.ai/en/api/rigging-and-animation), [webapp guide](https://docs.meshy.ai/en/webapp/guides/3d-model/rigging) ("Export and manually rig in DCC tools" for complex custom skeletons) |
| **Tripo** | **Yes, on paper.** `rig_model(rig_type=…)` accepts `biped`, `quadruped`, **`hexapod`**, `octopod`, `avian`, `serpentine`, `aquatic`, `others`; `spec` is `mixamo` or `tripo`; GLB/FBX out. | **One hexapod clip:** `preset:hexapod:walk`. The other presets (idle, slash, hurt…) are biped ones. | [SDK `client.py`](https://github.com/VAST-AI-Research/tripo-python-sdk/blob/master/tripo3d/client.py) (`rig_model`, `retarget_animation`), [SDK `models.py`](https://github.com/VAST-AI-Research/tripo-python-sdk/blob/master/tripo3d/models.py) (`RigType`, `Animation`). Tripo's own docs return 403 to fetchers, so hexapod bone names and credit costs are **unverified [try it]**. |
| **Rodin (Hyper3D)** | **No.** The Gen-2.5 API has no rig, skeleton or animation parameters; Hyper3D markets outputs as "rigging-ready" and points to Uthana for rigging. | None | [API spec](https://docs.hyper3d.ai/en/api-specification/rodin-gen2-5), [Hyper3D rigging blog](https://hyper3d.ai/blog/3d-rigging) |
| **Uthana** | **No.** Auto-rig fails on "Non humanoid" characters ("Missing clearly defined head, torso, two arms, or two legs") and on "Large extra appendages". Re-rig targets are r15 and ue5, both humanoid. | Humanoid motion only | [Auto-rig docs](https://uthana.com/docs/api/capabilities/auto-rig-and-add-character), [pricing](https://uthana.com/pricing) |

**What this means:** every route needs hand-keyed attack, hit, stagger, death and unfold clips. The AI tools can at best save the rig and the walk. For a beetle, the rig is the cheap part (see Q3), so that saving is small.

**Tripo shortcut, if you want to try it (one day, optional):** generate or upload the barkling, call `rig_model(rig_type="hexapod", spec="tripo")`, retarget `preset:hexapod:walk`, import the GLB into Blender and key the other clips on Tripo's skeleton. **[try it]**: whether the hexapod skin weights hold up on a chunky bark shell, and what the bones are called. Shipping it needs a paid Tripo month (about $20, unverified), because free output is labelled non-commercial (see #15). If the weights are soft and bendy, throw them away and rigid-bind anyway.

## Q2: Is there a ready-made rigged, animated beetle?

| Asset | What it has | Licence / price | Fit |
|---|---|---|---|
| **Quaternius** Ultimate Monsters (45–50 models) | Animated, glTF/FBX/Blend. **No insects or beetles** in the roster. | CC0, free ([pack page](https://quaternius.com/packs/ultimatemonsters.html), [roster on poly.pizza](https://poly.pizza/bundle/Ultimate-Monsters-Bundle-5oyGWAmOB6)) | No beetle |
| **Quaternius** Animated Easy Enemies | Spider, lizard, rat, frog, wasp. "Each enemy has a movement, attack, jump and death animation." FBX/OBJ/Blend. | CC0, name your price ([itch.io](https://quaternius.itch.io/animated-easy-enemies)) | **Spider is the closest CC0 multi-legged rig.** No hit/stagger/idle; eight legs; very low-poly style. Useful as a free placeholder or to study a leg rig. |
| **Kenney** | No animated 3D creatures or insects; the animated packs are humanoid ([Animated Characters 3](https://kenney.nl/assets/animated-characters-3)). | CC0 | None |
| **Asgart** "Armored Beetle \| 3D Animated Creature" | Separate "Anims FBX File"; animation list not published. 2048² textures (colour, normal, specular, roughness, emissive). | €3+. "You can use this model for commercial products like animations or games." ([itch.io](https://asgart-3d.itch.io/armoredbeetle)) | Closest in look (armoured beetle). Realistic PBR, heavy textures for web; clip list unknown **[try it]**. Good placeholder. |
| **Omabuarts** Rhino Beetle (Quirky Series) | 19 clips including Attack, Death, Hit, Idle ×3, Walk, Run. 1.9k tris, 4 LODs, 8×8 px texture. | Paid ([Sketchfab listing](https://sketchfab.com/3d-models/rhino-beetle-dbe39f75ab734d24b42e266b74fc2f4d)); the Sketchfab store has moved to Fab, so price shown there | Complete clip set, web-light, but a cute cartoon style with face blendshapes. Wrong for #11's painterly look. |
| **"Beetles" pack** on Fab | Four beetles: two attacks, death, hit from four sides, four idles, walk, turns, take-off/land, fly. | Fab Standard licence ([listing](https://www.fab.com/listings/79ce7e14-7ed3-4f63-b293-8d8d6a9529b2), returns 403 to fetchers; details from search snippets, **unverified**) | Best clip coverage, realistic style, Unreal/Unity packages, so it'd need exporting to glTF. |
| **Zacxophone** Animated insect pack | Dung beetle with 6 clips (walk, idle, transitions), FBX, 2K textures. | Royalty-free on Sketchfab, **with a NoAI clause**: "may not be used … as inputs to generative AI programs" ([listing](https://sketchfab.com/3d-models/animated-insect-pack-c6e27d23a12d45f3be3a4c2cce8ecb78)) | No attack/hit/death. The NoAI clause bars feeding it to Meshy as a reference. |
| **Unity Asset Store** "Low Poly Rigged Beetle Bug" (makemakex) | Clip list and formats not shown. | €9.19, Standard Unity Asset Store EULA ([listing](https://assetstore.unity.com/packages/3d/characters/animals/insects/low-poly-rigged-beetle-bug-255796)) | Unknown clips **[try it]** |

**Licences for store assets:**
- **Sketchfab/Fab Standard:** commercial games are fine, but "you may not sell, license, distribute or otherwise make available the Licensed Material as a stand-alone file" ([Sketchfab licences](https://sketchfab.com/licenses)). A Godot web export packs assets into a `.pck`, which counts as embedded. Fab's Personal tier covers buyers under $100k revenue in the last 12 months ([Fab docs](https://dev.epicgames.com/documentation/en-us/fab/licenses-and-pricing-in-fab)). Fab's EULA says Standard-licence assets may be used in any engine, but fab.com/eula returns 403 to fetchers, so that's **from search snippets, unverified**. Read it before buying.
- **Unity Asset Store EULA:** non-restricted assets may be incorporated into "an electronic application or digital media that has a purpose … beyond the display … of Assets" (§2.2.1). The EULA doesn't mention other engines either way; only assets marked "Restricted Asset" carry extra terms (§2.2.2, §2.9) ([terms](https://unity.com/legal/as-terms)). Check each listing for a Restricted flag.

**Why not ship a store beetle:** none matches the painterly FFT direction from #11, none has a "stump unfold" clip, and the look-alike (Asgart) is heavy on textures. Retexturing and adding clips to one is most of the work of the recommended route anyway, on a rig you don't control.

## Q3: What does hand-rigging and animating one cost?

**Why a beetle is cheap to rig:** insects have a hard exoskeleton, so nothing bends between joints. Each segment (body, head, mandible, each leg segment) is a separate mesh piece **parented rigidly to one bone**, with no weight painting and none of Blender's *Automatic Weights* failures on AI meshes that #15 warned about. Rigify isn't needed; a plain armature does it.

**Armature (~25 bones):** root, body, head, mandible L/R, 6 legs × 3 (coxa, femur, tibia), optional shell. Add a simple IK constraint per leg in Blender for easier keying, then bake on export.

**Estimate** (my judgement, for a small top-down enemy at a 2–3 m camera distance; double the low end if learning Blender animation):

| Task | Time |
|---|---|
| Meshy generation, cleanup, split into parts, bark texture paint-over | 1 day |
| Armature, rigid parenting, leg IK controls | 0.5 day |
| Idle (breathing, mandible twitch) | 1–2 h |
| Walk: tripod gait loop (legs 1-3-5 then 2-4-6) | 0.5–1 day |
| Lunge/bite with a clear wind-up for #17's 0.75s telegraph | 2–4 h |
| Hit, stagger | 2–3 h |
| Death (flip on back, legs curl) | 2–3 h |
| Stump unfold (legs out of a crouched, shell-down pose) | 2–4 h |
| GLB export, Godot import, hook into the enemy scene and `IMPACT` timing | 0.5 day |
| **Total** | **about 4–6 days** |

Money: **$0 beyond Meshy Pro.** Optional: a paid Tripo month (~$20, unverified) for the hexapod rig test, or a €3 placeholder beetle.

**Web weight:** ~25 bones and one small texture atlas is lighter than a KayKit humanoid. Keep it to one 512² or 1024² texture, as #15 recommends.

## Q4: Procedural leg IK in Godot 4.7

- Godot 4.6 brought 3D IK back: `IKModifier3D` with `TwoBoneIK3D`, `ChainIK3D`, `SplineIK3D`, `IterateIK3D`, `FABRIK3D`, `CCDIK3D` and `JacobianIK3D` ([Godot blog](https://godotengine.org/article/inverse-kinematics-returns-to-godot-4-6/), [IKModifier3D](https://docs.godotengine.org/en/latest/classes/class_ikmodifier3d.html)). They're `SkeletonModifier3D`s, like the `RetargetModifier3D` #15 mentions.
- **`TwoBoneIK3D`** handles several limbs in one node through `setting_count`, each with its own root/middle/end bones, target and pole ([class ref](https://docs.godotengine.org/en/latest/classes/class_twoboneik3d.html)). Coxa–femur–tibia maps onto it directly, so one node could drive all six legs.
- The older **`SkeletonIK3D` is deprecated**: "This class may be changed or removed in future versions" ([class ref](https://docs.godotengine.org/en/latest/classes/class_skeletonik3d.html)). Don't build on it.
- **What Godot doesn't give you:** the stepping logic. The blog post says nothing about foot placement or gaits. You'd write the script: ground raycasts per foot, step when a foot drifts past a threshold, alternate the two tripods, lerp the step arc. That's roughly 1–2 days to look decent **[try it]**, and attack/hit/death still need keyed clips blended with it.
- **Verdict:** not worth it for the MVP. On flat forest paths seen from above, a keyed walk cycle with root motion stripped (as the player already does) looks the same. Worth revisiting only if barklings must walk on slopes or roots, or for the rootkin later. If it is used, deterministic solvers like `TwoBoneIK3D` suit it; `LimitAngularVelocityModifier3D` smooths any snapping.

## The fallback

The hunched upright beetle on `Rig_Medium` would reuse KayKit's clips and the whole #15 pipeline, saving maybe 2–3 days. The costs:
- It reads as a humanoid in a beetle costume. That blurs the barkling against the rootkin, which #17 made the *upright*, mantis-like one. Silhouette contrast between the two is worth keeping.
- The stump-unfold ambush from #17 still needs a custom clip on the humanoid rig.

**Verdict: don't fall back by default.** Timebox the six-legged barkling at about one week. If the clips aren't acceptable by then, fall back, and use the Quaternius CC0 spider or the €3 Asgart beetle as the in-game stand-in until the art lands.

## Open questions

- **[try it]** Meshy's Smart Rig (Beta) on a beetle: if it produces a usable skeleton, it saves the half-day armature, though weights still want replacing with rigid parenting.
- **[try it]** Tripo hexapod: bone names, weight quality, and whether the walk preset looks like a beetle or a spider.
- **[try it]** Whether Meshy produces clean, separable legs from one image, or whether generating one leg and duplicating it is better.
