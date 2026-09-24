# isolated — ISOLA combat prototype

Stages 1-2 of `../isola/ISOLA_Combat_Test_Plan.md`, with the click / charged-chain
sword. **Disposable.** Per §8 what carries forward is the tuning knowledge and the
numbers, not this code.

Godot **4.7.2 mono** — `/Applications/Godot_mono.app`.
(`/Applications/Godot.app` is 4.2.1 and cannot open this project.)

## Run

```bash
GODOT=/Applications/Godot_mono.app/Contents/MacOS/Godot

$GODOT --headless --path . --script res://check.gd   # logic check, prints OK
$GODOT --headless --path . res://stealth_check.tscn  # stage 5 wake rules, prints STEALTH OK
$GODOT --editor --path .                             # then F5
```

`check.gd` asserts the combat rules that break quietly: commitment, enemy stamina pacing, dodge cooldown,
i-frames, stagger, held charge, chain link count and target path, block, parry. It needs
no scene and no window.

## Share (web build)

Every push to `main` runs `.github/workflows/web.yml`: `check.gd` must print `OK`, then the
`Web` preset is exported and deployed to GitHub Pages (`https://<user>.github.io/<repo>/`).
The game opens on a demo menu that lists every `.tscn` in `demos/`, so a new demo is just a
scene dropped there. `Backspace` brings the menu back.

## Controls

`WASD` move · **hold `Shift`** sneak · `Space` dodge · **hold RMB** block · `1` sword · `2` bow shot · `3` volley · `4` arrow rain ·
`-`/`=` enemy count · `[`/`]` arrow count · `F1` debug · `Esc` free the cursor · `R` restart.
Facing follows the mouse.

**Sword**

| Input | Result |
|---|---|
| **Click** | One arc swing at the cursor. Base damage and knockback, **never dashes** and never slows or stops your movement: you walk at full speed through the whole swing. Fires on press. A click during a swing is ignored; there is no combo. |
| **Hold** | The swing pauses at the top of its wind-up and charges. Move at 35%. While the chain is on cooldown, holding does nothing extra and the click swing goes out as normal. The **chain path** is drawn on the ground: yellow rings are locked-in targets, the faint ring is the one the next link would add. |
| **Release** | Starts the chain cooldown, `chain_cooldown_per_link` (1s) × links. Dash-strikes each target on the path in turn: invulnerable, a whole-game hit freeze on every hit, and the last link knocks them flying. No target in range: it goes out as a plain arc. |
| **Space while charging** | Rolls out. The wind-up before the hold point is still committed. |

**Bow:** hold, pull back to aim, release. Pulling past `bow_draw_threshold` (60px) nocks
the arrow and turns you to face where it will fly, which is opposite the pull. From then on the draw grows with **time held**, from `bow_min_draw` (20%) to full over
`bow_charge_time` (1s), and pulling further only aims. The draw scales range, damage and
pierce budget.

Arrows are the KayKit `arrow_bow` model flying at `arrow_speed` (40 m/s). Who gets hit is
decided at release, from the same calculation as the preview, and each hit lands as the
arrow reaches that enemy. So an enemy 12m away is hit about 0.3s later.
While drawing, the ground shows each arrow's line to where it stops, with a ring on every
enemy it will hit, dimmer after each pierce. The line is green when it hits and faint
white with an end mark when it hits nothing. Like the chain path, it's always drawn.

- **Pierce.** An arrow's budget is `draw × (bow_pierce + skill_pierce)`, which is 2 + 1 = 3 at
  full draw. It visits enemies in its cone nearest first. Each one is hit, and the arrow
  carries on only while the budget covers that enemy's `toughness` (1 on the Skeleton
  Warrior), spending it. So a full draw passes three skeletons and stops in the fourth.
  A light tap stops in the first.
- **Falloff.** Each earlier pierce costs `pierce_falloff` (15%), compounding: 30 → 25.5 →
  21.7 → 18.4 at full draw.
- **Volley (`3`).** Fires `arrow_count` arrows (3 by default), `arrow_spread_deg` (8°)
  apart around the aim. Each pierces on its own. The `arrows` −/+ buttons (or `[`/`]`) tune
  it from 1 to 7, live, without restarting the fight. It then waits `volley_cooldown` (2s).
  The single shot (`2`) always fires one arrow and is free.

**Arrow rain (`4`).** Hold to show the target circle on the ground. It starts
`rain_min_diameter` (1m) wide with `rain_min_arrows` (4), and grows to `rain_max_diameter`
(5m) with `rain_max_arrows` (20) over `rain_grow_time` (1.5s). The circle trails the mouse
at `rain_follow_speed` (6 m/s), so it lags behind a fast flick, and never goes past
`rain_range` (14m, the faint ring around you). Enemies inside it get a green ring. The bow's shot cone isn't drawn in this mode.
Release: the arrows go up, then each drops onto its own random point in the circle, about
0.05s apart. Each hits every enemy within `rain_hit_radius` (0.8m) of where it lands, for
`rain_damage` (15) and half a stagger, with no knockback. Hits are decided where the arrows
land, not at release, so walking out of the circle works. The cooldown is
`rain_cooldown_per_arrow` (0.25s) × arrows, so a full rain waits 5s. A draw started while a
mode is cooling down is refused.

Verified in a scripted run: a full rain on a frozen enemy landed all 10 arrows (150 damage)
about 1.2s after release. That was with the earlier 10-arrow, 10m circle.
Rain arrows don't cut trap ropes yet.

Verified in a scripted run with 4 enemies in a line and one to the side: a full draw
previewed Enemy1–4 and landed exactly 30, 25.5, 21.7, 18.4. With 3 arrows, two lines ran
down the row and the third hit the side enemy.

**Links.** One link is free, and each `link_charge_time` (0.35s) held adds another,
up to the lower of:

- `sword_max_links` (5), the weapon;
- `skill_max_links` (3), a plain export until there is a skill system.

## No stamina — cooldowns (`docs/adr/0001`)

The player has no stamina. Cooldowns are the only limit on actions:

| Action | Limit |
|---|---|
| Click swing | Free. Only its own wind-up and recovery pace it. |
| Charged chain | `chain_cooldown_per_link` (1s) × the links in the chain, from release. A 3-link chain waits 3s. A charge released with no target costs nothing. |
| Dodge | `dodge_cooldown` (0.65s) from the start of one roll to the next, so 0.25s after the roll ends. |
| Bow shot (`2`) | Free. The draw time is the limit. |
| Volley (`3`) | `volley_cooldown` (2s) after firing. |
| Arrow rain (`4`) | `rain_cooldown_per_arrow` (0.25s) × arrows fired. |
| Block | Free, but every blocked hit still chips `block_chip` (25%) off health, which never comes back. There is no guard break any more. |

The debug label and HUD show every cooldown (`cd chain · dodge · volley · rain`). The chain cooldown
does not yet shrink with skill level, because there is no skill system yet.

**Enemies still use stamina**, but only to space out their swings (`attack_cost` against
`regen_rate`). It is not a resource the player sees, and it keeps the Stage 2 tuning.

**Targets.** While charging you turn to face the cursor (`charge_turn_rate`, 720°/s). The
first target is the enemy nearest the **cursor** inside a wedge pointing at it:
`chain_first_range` (6m) deep and `chain_first_arc` (45°) either side, outlined on the
ground. Each next one is the nearest unvisited enemy within `chain_hop_range`
(4.5m) of the last. The chain stops early when nothing is in range.

**The strike.** Each link dashes to `link_standoff` (1.1m) short of its target in
`link_dash_time` (0.07s), passing through other bodies. The freeze lasts `hitstop_time`
(0.05s), or `hitstop_last` (0.10s) on the last link. Each earlier link throws its
target `link_knockback` (2.5m) off to the side, away from where the next link goes, so
the dash line is clear when the chain ends. Targets are followed live, so this
doesn't break the path.

Verified in a scripted run with 4 enemies in a line: a click with no movement input moved the player 0.000m.
A 1.2s hold showed 3/3 links (the skill cap). Release hit Enemy1, 2 and 3 in order, a
30-damage hit fired at the player mid-chain returned `dodged`, and `Engine.time_scale`
went back to 1.

## Art

Characters, weapons and animations are **KayKit** by Kay Lousberg, all **CC0**
(free for commercial use, no credit required). The license files are in
`assets/kaykit/licenses/`.

| Pack | Used |
|---|---|
| [Adventurers 2.0](https://kaylousberg.itch.io/kaykit-adventurers) | `Ranger.glb` (player), `sword_1handed`, `bow_withString`; the other 5 characters are included for swapping |
| [Skeletons 1.1](https://kaylousberg.itch.io/kaykit-skeletons) | `Skeleton_Warrior.glb` (enemy), `Skeleton_Blade`; 3 more skeletons included |
| [Character Animations 1.1](https://kaylousberg.itch.io/kaykit-character-animations) | 6 `Rig_Medium_*.glb` animation libraries, shared by every character |

Only the glTF files were copied in. The packs also ship FBX, OBJ and Unity versions,
plus clips not used here; re-download from the links above if you need them.

`character_view.gd` (the `Model` node on Player and Enemy) is purely visual. It watches
the combat state and plays the matching clip, so gameplay and `check.gd` are untouched.
**Swap a character** by changing `model` / `right_hand` / `left_hand` on that node
in the inspector; every KayKit character uses the same rig.

| State | Clip |
|---|---|
| Idle / walk / run | `Idle_A` / `Walking_A` / `Running_A`, played at a rate that matches movement speed |
| Click | `Melee_1H_Attack_Slice_Horizontal` |
| Held charge | `Melee_1H_Attack_Jump_Chop`, frozen at the top of its wind-up |
| Chain links | Alternating `_Slice_Horizontal` / `_Slice_Diagonal`, `_Jump_Chop` on the last; each restarts so the blade lands as the dash arrives |
| Dodge | `Dodge_Forward/Backward/Left/Right`, picked from the dodge direction |
| Stagger / guard break | `Hit_A` |
| Block stance | `Melee_Blocking` |
| Bow | `Ranged_Bow_Draw` → `Ranged_Bow_Aiming_Idle` → `Ranged_Bow_Release`; bowstring bends with draw |
| Death | `Death_A` (player), `Skeletons_Death` (enemy) |
| Enemy | `Skeletons_Idle`, `Skeletons_Walking`, `Melee_1H_Attack_Chop` |

**Swings are fitted to the game's timings, not the other way round.** Each attack's
impact moment (where the hand moves fastest) was measured by sampling
`handslot.r` across the clip, and the clip is time-warped so impact lands as the active
frames begin, whatever `windup_time` is tuned to. The enemy's chop lands at 0.59s of a
0.60s telegraph, so it plays close to natural speed.

Dodges and the skeleton death carry up to 0.7m of sideways root motion, which is
stripped on load because the physics body already does the moving.

## Camera

`follow_camera.gd` follows the player at a fixed 50° angle. It only moves and never
turns, so mouse aim, WASD and the bow pull-back keep meaning the same direction
everywhere. It eases in (`follow_speed`, frame-rate independent) and snaps on load, so
the reload after each fight doesn't swoop.

**Why it's smooth.** The display here runs at 120Hz, but physics runs at 60Hz, so a body's
real position only changes every other frame. `physics/common/physics_interpolation`
is on, and the camera follows the *interpolated* position. The debug view draws at
interpolated positions too, so arcs and labels don't jitter against the capsules.

Measured in a scripted walk with a dodge, 118 fps, per-frame speed change:

| | interpolation on | interpolation off |
|---|---|---|
| player on screen | 1% | **199%** (stalls every other frame) |
| camera | 3% (worst 0.42 m/s) | 5% |

Tune `pitch_deg`, `distance` and `follow_speed` live in the inspector. Don't change
`yaw_deg` during play: it changes what "up the screen" means.

Anything that teleports a body after spawn should call `reset_physics_interpolation()`
on it, or it will visibly streak from the old spot for one frame.

## Stagger

A landed hit freezes the enemy for `hit_stagger` (0.75s), **unless it is already
committed to a swing**. That exception is the mechanic:

- Hit into its telegraph and you trade: you both land.
- Hit during its recovery and you extend the punish window enough for a follow-up.

Without the exception a hit cancels the enemy's 0.6s wind-up, the player swings
faster than that, and the enemy never attacks: stunlock. Sweep with scripted
strategies (bots, not hands):

| `hit_stagger` | mash | dodge-and-punish |
|---|---|---|
| 0.25 | 3.34s, 50 hp | 9.53s, 75 hp |
| 0.50 | 3.33s, 50 hp | 6.0s, 75 hp |
| **0.75** | **3.32s, 75 hp** | **4.8s, 100 hp** |
| 1.00 | 3.31s, 75 hp | 4.78s, 100 hp |

## Knockback

A click shoves enemies straight away from you by 1.2m. A chain throws each target
2.5m to the side, then the last one ×2.5 straight ahead. A **committed enemy isn't
moved by a click** (`armor_knock_mult` 0), because pushing it out of range mid-swing
cancels its attack through distance, which is stunlock again. A chain moves it anyway:
it's the expensive attack, and clearing a path is its job. Enemies shove you too, and a
dodge shrugs it off.

**Dodging and chaining pass through enemies**, so a roll gets you out of a crowd.
Collision comes back once you are clear of every enemy's capsule. I-frames are
unchanged (0.05–0.28s of the 0.40s roll): passing through isn't the same as being
untouchable.

## Impact feedback — `F2` toggles

Every landed hit is made visible. `fx.gd` holds the effects, `player.gd` fires them,
`follow_camera.gd` owns the camera kick, and `enemy.gd` owns its own knockback slow-mo.
Tunables are in the player's **Impact** group.

The game never slows down globally. A global slow-mo (tried first) read as lag, so
now: the dash stays full speed, every hit gets a **freeze frame**, and only the enemy
you knocked back **slides in slow motion**, easing back to normal speed.

| Hit | Freeze frame | Victim's knockback | Kick | Also |
|---|---|---|---|---|
| Chain link | `hitstop_time` 0.05s | slow-mo for `link_knock_slowmo` 0.6s from `knock_slowmo_scale` 0.25 | `link_shake` 0.35 | sparks along the dash, white flash |
| Last link | `hitstop_last` 0.10s | slow-mo for `last_knock_slowmo` 1.0s | `last_shake` 0.6 | bigger sparks, flash, gold ground ring |
| Click swing | `swing_hitstop` 0.04s | normal | `swing_shake` 0.15 | small sparks, flash |
| Arrow | none | normal | `arrow_shake` 0.2 × draw | sparks along the arrow, flash, green ground ring |
| You get hit | none | — | `hurt_shake` 0.4 (half when blocked) | |

A slowed knockback covers the same distance, just over more time: in a scripted run,
2.5m of knock moved 0.97m in its first 150ms against 2.3m unslowed, and both ended up
about 1.9m away. Only the slide is slowed. The enemy's animation and stagger timer run
at normal speed.

The kick is a spring, not jitter: the camera is shoved along the hit direction and a
damped spring (`kick_hz` 7, `kick_damping` 0.45, on the camera) pulls it back with one
small overshoot. It only moves the camera's position, so aim is unaffected.

`Fx.prewarm` draws every effect once under the floor at load, so their shaders compile
then and not on the first hit of a fight.

**F2 turns all of it off** and leaves only the chain's original hitstop. Test plan §3
warns that hit VFX can hide a weak core, so compare with F2 before trusting a "feels
better". `fx_toggled` is logged.

Physics keeps stepping during a freeze, with delta 0, so `_run_chain` skips those steps.
Otherwise a dash past its time divides by zero and the player's position goes NaN.

## Route 1 (`demos/route1.tscn`)

The whole of Route 1, from the Glade to Settlement 2, following the "Route 1 shape" and "Route 1 monsters" decisions. **Don't hand-edit the scene.** It's generated: `python3 tools/gen_route1.py [seed]` (seed 8 is checked in; about 8 seconds).

### How the map is generated

The beats and their order are fixed by the design; where they sit is procedural:

1. **Clearings by constrained random walk.** Each beat's clearing sits one path length on from the last (clearing radii plus 12–24m), turning by a random angle. The turn is mean-reverting (`t * 0.35 + random`, capped at ±55°), so the route winds but keeps heading north. A clearing that crowds an earlier one is rejected and retried.
2. **Winding paths.** A Catmull-Rom spline through each pair of clearings, with its midpoint pushed sideways by up to 28% of the distance. The path's width drifts with noise between about 3.4 and 6.6m. The path into the ravine stays straight, for the bridge.
3. **Side nooks.** Three short dead-end spurs (12–16m) off the paths, each ending in a small clearing with a rock and mushrooms.
4. **A signed distance field.** The walkable ground is a smooth-min union of the clearings (circles) and the path segments (capsules), sampled on a 1m grid: negative inside, positive outside.
5. **Domain warping.** The field is sampled at a point pushed about by fractal value noise (±2.6m), so no edge is straight or perfectly round.
6. **The ravine** is a band 8m wide across the whole valley, cut through the field where the straight path crosses it.

At load:
- `route_terrain.gd` raises banks from the field, paints the ground, and traces the collision walls just outside the walkable edge with **marching squares**. The walls leave a gap exactly as wide as the bridge; the `RavineLip` wall blocks that gap until the tree falls.
- `route_foliage.gd` plants trees and undergrowth with **Poisson-disc sampling** (Bridson), so there's no grid to spot.

Monsters, the nest, the waystone and signposts are placed in each clearing's own frame (forward along the route). So the nest demo's sneaking lane still runs up the middle of the nest, whichever way the route turns there.

### Running the checks

```bash
Godot --headless --path . --script res://tools/route1_check.gd      # prints ROUTE OK
Godot --path . --script res://tools/route1_shots.gd -- /tmp/shots   # screenshots + fps
```

`route1_check.gd` walks the whole route with real collision, asserting each beat, and ends with `ROUTE OK`. Run it after regenerating the route.

### The beats

| Leg | Beat | What's there |
|---|---|---|
| 1 | The Glade | You start here. |
| 1 | First surprise | A stump barkling on the path into the first clearing. |
| 1 | The chest | In the side nook just before the mud: `E` (or attack) opens it, and the **bow** rises out. That unlocks hotbar slot 2. |
| 1 | Mud clearing | Mud fills the whole clearing, so there's no dry way round. The ground sinks 0.35m under a wet surface, so you and the pair of barklings wade in it up to the shins, at 35% speed. Shoot them from the edge with the bow, or wade in. |
| — | **Waystone** | Heals you to full and makes leg 2 the restart point (`waystone.gd`). The dead giant tree stands beside it. |
| 2 | Stealth stretch | The nest: 5 rootkin, the satchel at the heart, and the log. |
| 2 | Clearing | A group of 3 barklings. |
| 2 | The ravine | **Placeholder puzzle:** step on the gold ring and the tree bridge drops (`bridge_trigger.gd`). |
| — | Settlement 2 | The green ring. It only counts while you're carrying the satchel. |

**Legs** (`route.gd`, which extends `fight.gd`): health carries through a leg and never regenerates. A death reloads the scene and restarts the current leg: from the Glade before the waystone, from the waystone after it. The leg number is a static, so it survives the reload, and leg 1's monsters (the `leg1` group) are removed when leg 2 restarts. Killing every monster doesn't end the route (`clear_wins = false`); only Settlement 2 does.

### Weapons: the hotbar and locked slots

The hotbar (`weapon_hotbar.gd`, in every demo's HUD) shows the four slots: 1 Sword, 2 Bow, 3 Volley and 4 Rain. The one in hand has a gold border, locked slots are dimmed and say "locked", and volley and rain show their cooldown as a dark fill draining away. Pressing a locked key flashes that slot red.

A scene can lock slots with the player's `locked_weapons`. Route 1 locks `shot`, `volley` and `rain`, so you start with the sword. Every other demo has the full kit.
- **Unlocking:** the chest (`chest.gd`) unlocks `shot`.
- **Persistence:** unlocks live in the static `player.unlocked`, so a death keeps the bow and the chest stays open. `route.gd` clears them when a run ends, either at Settlement 2 or by leaving for the menu.
- **Revises a decision:** the map's "Kit progression" decision had the bow as a Route 2 gift. It's now found on Route 1.

Verified by `tools/route1_check.gd`, which **walks with real collision** (`move_and_slide`):
- In the mud the player stands 0.35m lower, at 38% of the speed on dry ground.
- Key 2 is refused (the weapon stays the sword) until the chest is opened with `E`; then key 2 gives the bow, and volley stays locked.
- After a leg 1 death, the bow is still unlocked and the chest is still open.
- Pushing in 8 directions for 3s each, from the Glade and from the first path, never took the player past the walkable edge.
- The waystone healed 40 to 100 and set leg 2. Dying in leg 2 restarted at the waystone, with 0 leg 1 and 8 leg 2 monsters.
- Sneaking the nest lane, in the stretch's own frame, picked up the satchel with 0/5 rootkin awake.
- The lip held until the gold ring dropped the bridge. The player then walked 12m across it at a steady height, 10m above the ravine floor, and reaching Settlement 2 ended the route and cleared the bow for the next run.

The previous straight layout had a bug: its invisible walls ran across both ends of the ravine and blocked the bridge. The old test moved the player by teleporting, so it never noticed.

## Route 1 art: terrain, forest and see-through trees

`demos/route1.tscn` now has real ground, banks and forest. Everything is built at load from the same layout in `tools/gen_route1.py`.

- **Terrain** (`route_terrain.gd`): one mesh on a 1m grid with a matching `HeightMapShape3D`.
  - Flat wherever you walk. Banks rise about 3m at the edges (`bank_height`, `bank_width`), with rolling forest floor beyond.
  - The ravine drops 10m across the whole valley.
  - Vertex colours paint worn dirt down the middle, a mud blob, and leaf litter off the path.
  - The invisible walls are still the hard edge; the banks are how that edge looks.
- **Ground shader** (`shaders/terrain_splat.gdshader`): the painted-ramp lighting, grass as the base layer, and triplanar cliff rock wherever the ground is steep. It uses 5 texture samplers, well inside WebGL2's 16.
- **Forest** (`route_foliage.gd`): a scatter with a fixed seed, so every load looks the same.
  - Trees in a band on the banks, Poisson-disc spaced at least `tree_spacing` apart. Undergrowth along the edge, grass on the floor away from the dirt, and a few rocks and mushrooms. The twisted trees (about 10k triangles each) are left out of the scatter.
  - Hand-placed landmarks: the giant dead tree, the waystone rock and saplings round the nest.
  - One `MultiMeshInstance3D` per model part per 48m tile, so each tile culls on its own. Nothing has collision, so rootkin see through leaves.
- **Foliage shader** (`shaders/foliage.gdshader`): the same painted ramp, alpha-cut leaves and a little wind.
- **See-through** (`shaders/fade.gdshaderinc` + `occluder_fade.gd`): trees, undergrowth and anything above 1.2m of bank dither away in a soft cylinder from the camera to the player and each awake enemy. Anything within 7m of the camera fades too (`fade_near`), so canopies right under the lens don't fill the screen.
  - It uses discard with a 4×4 Bayer dither, not blending, so it stays in the opaque pass.
  - Shadows stay whole.
  - Sleeping rootkin and stump barklings get no hole, so the fade never gives the nest away.
- **Look:** `art/route_env.tres` (filmic, warm ambient, fog, saturation 0.72) and `art/painted_ramp.tres`, both from the style test's numbers. `shaders/painted_ramp.gdshader` came from the `prototype/style-test` branch.

**Art sources** (all CC0, licence notes next to the files):
- `assets/quaternius_nature/`: 33 Quaternius Stylized Nature MegaKit models from Poly Pizza. `tools/repack_quaternius.py` rewrites them to share 11 textures and drop the normal maps, taking them from 62 MB to 11 MB. The author says no generative AI was used.
- `assets/textures/terrain/`: 3dtextures.me stylized grass, dry mud (used for both the path and the mud), leaves (forest floor) and cliff rock. The site doesn't say whether AI was used.
- The raw downloads live in `art_src/`, which git and Godot both ignore.

**Measured** on an M1 Pro at 1600×900 with vsync off, in the editor's debug build:

| Spot | fps |
|---|---|
| Glade | 162 |
| Stump barkling | 98 |
| Mud clearing | 81 |
| Waystone | 155 |
| Nest | 123 |
| Ravine / bridge | 160 |
| Settlement 2 | 161 |

There are 510 trees and about 2,140 grass clumps; the level builds in about 0.9s at load. What got the nest from 45 to 123fps:
- **Sleeping enemies pause their `AnimationPlayer`.** A playback speed of 0 still cost about 1.6ms of CPU each per frame.
- **Enemies more than 45m from the camera stop animating** (`animate_range` in `character_view.gd`).
- **The sun uses 2 shadow cascades instead of 4**, which is plenty at 12.5m.
- **The terrain doesn't cast shadows.**
- **Cliff rock is only sampled on steep ground.**

The web build hasn't been measured yet. The knobs, cheapest first: `grass_spacing`, `tree_spacing`, `tree_view_range`, and the Sun's `directional_shadow_max_distance`.

## Route 1 monsters — stand-ins (`demos/barkling.tscn`, `demos/rootkin.tscn`)

These are the two monsters from the "Route 1 monsters" decision, standing in on KayKit skeletons until the real models exist. Both demos are the arena with a different `enemy_scene`, so `-`/`=` still sets the count.

| | Barkling (`barkling.tscn`) | Rootkin (`rootkin.tscn`) |
|---|---|---|
| Stand-in | `Skeleton_Minion` at 0.6 scale, chest height | `Skeleton_Rogue` |
| Damage / wind-up / recovery | 20 / 0.75s / 0.70s | 35 / 0.55s / 0.60s |
| Health / move speed | 60, so three click swings / 3.0 | 150 / 4.0, below your 5.0 |
| Attack | **Lunge**: dashes `lunge_distance` (1.4m) forward during its active frames and bites within `attack_range` (1.4m) of wherever it has got to. It starts from 2.6m out. | The skeleton swing |
| Asleep | — | `still_while_asleep`: frozen on its idle pose like a sapling |

**Stump disguise** (`demos/stump.tscn`): a barkling with `disguised` on stands as a mossy stump. It's blind and deaf, and it wakes only within `unfold_distance` (4m), or when hit or woken by an ally. It then spends `unfold_time` (0.6s) growing to full size and turning to face you before it can act.

Verified in a scripted run:
- A barkling lunging at a player who stood still travelled 1.7m (1.4m plus a short slide as it stopped) and took them from 100 to 80.
- Three 25-damage swings killed it.
- A sleeping rootkin's idle clip ran at speed 0, and returned to normal speed once it woke.
- A disguised barkling stayed asleep while the player walked loudly 6m away. At 3.5m it unfolded straight away, and its first wind-up came 0.95s later.

## The nest (`demos/nest.tscn`)

Five rootkin sleep around the nest's heart, where the healer's satchel lies. Pick it up and get it to the green ring. The exit only counts while you're carrying it (`fight.gd`'s `exit_needs`).

- **Wake one, wake all.** Enemies with the same `nest` name all wake together, however far apart they are.
- **The stretch's edge.** `stealth_stretch.gd` is a rectangle drawn faintly on the ground. Any enemy whose `stretch_path` points at it chases you only while you're inside. Past the edge, it walks back to its spot and falls asleep again. A sleeper also ignores anything it sees or hears beyond the edge, so the nest doesn't keep waking and settling while you stand just outside.
- **The satchel** (`pickup.gd`): walking within 0.9m of it picks it up silently into `player.carrying`, and the HUD shows `CARRYING satchel`. Restarting reloads the scene and puts it back.
- **The lane.** The four side rootkin face outwards and the last one faces north behind a log. That leaves a sneaking path up the middle to the heart, then round the left end of the log to the exit.

Verified in a scripted run:
- Sneaking that lane woke nothing and reached the exit.
- Walking it woke all 5 at once.
- Reaching the exit round the side without the satchel didn't count. Sneaking the lane through the heart picked it up without waking anything, and the run ended at the exit.
- With the player outside the edge, all 5 walked home, to within 0.13m of their spots, and slept.
- Running south from the heart after waking the nest, none of them got within 6m of the edge.

**Tuning note:** that escape took no damage. Rootkin (speed 4.0) can't catch a player running at 5.0, and their 0.55s wind-up never lands on a target moving away. "Route 1 monsters" wanted a caught player to lose health, so they may need a short lunge or a faster first step.

## Stage 5 — sneaking (`demos/stealth.tscn`)

Get from the start to the green ring at the far end. Four skeletons stand guard:
Guard1 sweeps its gaze over the first half, a pair faces each other under a hanging
weight, and ExitGuard sweeps over the exit. Crates (1.8m, taller than a skeleton's eye)
block sight. Reaching the ring ends the run: `winner` is **`sneaked`** if nothing woke,
**`escaped`** if something did. Fighting them all still counts as a win.

**Sneak:** hold `Shift`. 45% speed (`sneak_move_mult`).

A sleeping enemy stands still (or sweeps by `look_sweep`) until one of these wakes it,
and then stays awake. Every wake logs `enemy_alerted` with `why`:

| `why` | Rule |
|---|---|
| `sight` | You're inside its cone (`sight_half_angle` 55°, `sight_range` 10m) with a clear line from its eye to your chest. Sneaking shrinks the range to 60% (`sneak_sight_mult`). |
| `heard` | You're moving within `hear_range` (9m) × your `noise()`: 1 walking, 0.2 sneaking (`sneak_noise`), 0 standing still. Dodges and chains are never quiet. |
| `hit` | Any damage: sword, arrow, fire, a fall. |
| `ally` | Another enemy within `alert_range` (7m) woke up. It chains. |
| `noise` | The trap door, hanging weight and gate wake everything within their `noise_radius` (14m). Dropping the weight on the pair is two kills, but it wakes the exit guard too. |

The **cone** (yellow wedge) and **hearing ring** (blue) are drawn under each sleeping
enemy, and both shrink live as you sneak or stop. The drawn cone ignores walls; the real
check doesn't, so a crate can hide you inside a drawn cone.

Enemies spawned by the arena's `-`/`+` start awake, so the arena plays as before. In the
other demos, walking wakes a station at 9m, the same as the old `aggro_range`, but now
you can sneak up on it. `fight_end` gains `alerted`: how many enemies were awake.

Skipped: a sneak-attack bonus, suspicion or investigate states (it's asleep or awake,
nothing between), patrol routes, and going back to sleep.

## Stage 3 — attrition corridor (`demos/corridor.tscn`)

Three pairs of Skeleton Warriors, 18m apart down a walled 6m-wide corridor. **No healing** between
them; the red bar bottom-left is your health. Each one stays asleep until you are within
`aggro_range` (9m), so each pair comes as its own fight. Corridor skeletons only: `damage` 35 (arena 25) and `windup_time` 0.45 (arena 0.6). Die or clear all three and it restarts at full.

The question (test plan §4): does the third fight feel different from the first *only
because you arrive hurt*? Each kill logs `enemy_down` with `player_hp`, and `fight_end`
carries `cleared`, counting single skeletons (0–6), so a death happened at pair `cleared / 2 + 1`, rounded down.

## Stage 4 — trap door (`demos/trap_door.tscn`)

This demo tests the Stage 4
question: can you win a fight you'd lose head-on by using the room?

- **The Heavy** (`heavy_enemy.tscn`, the KayKit Knight with axe and shield) takes 5% damage
  (`damage_taken_mult`), never staggers (`stagger_taken_mult` 0), barely moves when hit
  (`knock_taken_mult` 0.1), has 300 hp and toughness 10 so arrows stop in it, and hits for
  **60**. That's 240 sword hits: unwinnable head-on on purpose. Its 0.8s wind-up is the
  telegraph.
- **The trap** (`trap_door.gd`) is a 3×3m door held shut by a rope tied to a post. Shoot the
  rope and the door drops for `open_time` (2s). Anything on it, or walking onto it while it's
  open, falls and dies, armour or not, including you. One use per fight.
- **Aiming** at the rope shows a yellow ring on it in the bow preview. Any node in the
  `shootables` group with `shoot_position()`, `shoot_radius` and `shot()` works the same
  way. An enemy standing between you and the rope stops the arrow.
- **Baiting.** The Heavy walks to `standoff` (2.4m) from you and stops. Stand just past the
  door's edge and it stops on the door.

`fight.gd` has `spawn_enemies` off here, so it uses the placed Heavy and hides the enemy
buttons, and it logs `stage` "4". New log events: `trap_triggered`, `enemy_fell`,
`player_fell`.

Verified in a scripted run: a sword hit took the Heavy from 300 to 298.75 with no stagger.
Standing 3m from the door, the Heavy walked onto it in 2.6s. A full draw at the rope showed
the ring, the arrow cut it, and the Heavy fell and died while the player stayed alive.

## Environment traps (`demos/environment.tscn`)

Seven trap stations in one map, each waking at `aggro_range` (9m) so they play as
separate encounters. `R` restarts. The rules are the same everywhere:

- **The room is neutral.** Falls, the weight and spikes kill anything, armour or not,
  including you. Fire burns through armour, block and i-frames. Mud slows you too.
- **Enemies walk around live hazards and stop at edges** (`Hazard.steer`, a five-ray fan
  plus a downward ray for the floor). Knocking them in still works — only their own
  walking is careful.
- **Anything below y = −4 dies.** That is what makes the gaps lethal.
- **Triggers** are the `shootables` group: `shoot_position()`, `shoot_radius`, `shot()`.
  Arrows trigger them in flight, and a sword swing triggers one inside its arc.

| Station | What it tests |
|---|---|
| **1. Bridge** | 4 skeletons on a 3m bridge over a gap. Chain through them: each link throws its target 2.5m sideways, off the bridge. The last link knocks forward instead, so it stays on. |
| **2. Ledge** | 2 skeletons on a plateau across a 3m gap. The chain dash ignores gravity, so it carries you over. |
| **3. Hanging weight** | A block on a rope over a marked circle, with a Heavy. The rope hangs at the post, not over the circle, so the enemy you are baiting is not standing between you and your own trigger. |
| **4. Oil and fire** | Shoot the jar for a slick (slows, flammable), then the lantern to light it: `burn_dps` 22 for 8s. A lantern with no oil makes a small, brief fire, so the oil is what earns the second arrow. |
| **5. Mud and gate** | A mud patch at 35% speed in front of a gated corridor. Shoot the lever to drop the portcullis and split the group. |
| **6. Pressure plates** | Stand on the plate: it flashes for `tell` (0.4s), fires for 1s, then cools for 3s. One drives a spike floor (kills), one a flame wall (burns). Enemies path around both while they are live. |
| **7. Trap door** | The Stage 4 trap from `demos/trap_door.tscn`, with its own Heavy. |

`traps/hazard.gd` holds the pure parts (zone shapes, how slows stack, steering) and
`traps/hazard_zone.gd` is the one node behind mud, oil, fire and spikes.

Verified in a scripted run of every station: a chain knocked 2 of 4 skeletons off the
bridge to their deaths; the weight crushed a 300hp Heavy that shrugs off 95% of sword
damage; oil then lantern burned all 5 skeletons to 0; skeletons in mud moved at 1.0 m/s
against a 3.0 base; the closed gate held all 6 back; the spikes killed a skeleton on the
plate's tell; and the player died in their own open trap door.

## The enemy

Telegraph (yellow, 0.60s) → dodge through it → punish during recovery (0.60s). It
runs the same committed state machine as you, fed by AI instead of input.
`standoff` (2.15) sits just outside your `attack_reach` (2.0), so you have to step in
to punish. It has no retreat and never backs off yet.

`−` / `+` top-right (or `-` / `=`) sets 0–8 enemies. Changing the count restarts the
fight so time-to-kill stays meaningful. Spawned by `fight.gd` from `enemy.tscn`.

## Debug view — `F1` (or `` ` ``) toggles

Drawn by `debug_draw.gd`, which only observes; removing the node changes nothing.

- **Arcs** on the ground are the real hit test, measured to the target's **centre**
  (the small cross). Grey at rest: what a click would hit now. Yellow while winding
  up, red while active, then a
  fading ghost. **An outline turns green while the other actor's centre is inside
  it**: that swing would connect right now.
- **Charging**: a yellow ring at `chain_first_range`. The path itself is always drawn, F1 or not.
- **Enemy**: its attack arc and a faint `standoff` ring.
- **Bow**: the shot cone while drawing, then a tracer (green hit, red miss). The label shows draw %, pierce budget and arrow count; popups show `pierce n`.
- **Rings**: cyan i-frames, magenta stagger, grey blocking, white armed parry.
- **Labels**: weapon, state with timer, links landed, `links n/cap (weapon · skill)`
  while charging, `CHAIN n/m` while it plays, health, chain and dodge cooldowns, and `PUNISH` when an enemy is open.
- **Popups**: damage with `link n/m`, `FINISHER`, and `STAGGER` / `KILL` or
  `no stagger (committed)`; damage taken, `BLOCK`,
  `PARRY`, `DODGED`; arrow strength.

## Files

| | |
|---|---|
| `combat_state.gd` | Action FSM: wind-up/active/recovery/dodge/stagger, dodge cooldown, enemy stamina, health, held charge, held active window. Pure. Shared by player and enemy. |
| `stance_state.gd` | Weapon hand: bow/block stances, block/parry resolution, chain link count and target path, arrow pierce path and volley fan. Pure. Player only. |
| `gesture.gd` | Pull-back drag for the bow; flick detection, now only for parry. Pure. |
| `camera_relative.gd` | Screen/stick direction → world direction. |
| `follow_camera.gd` | Smooth fixed-angle follow camera. |
| `player.gd` | Input, aim, movement, hits. Every tunable is `@export`. |
| `enemy.gd` · `enemy.tscn` · `heavy_enemy.tscn` | The enemies: skeleton, and the armoured Heavy. |
| `traps/*.gd` | Hazard zones and traps: trap door, hanging weight, oil jar, lantern, gate, pressure plate. |
| `fight.gd` | Spawning, enemy-count controls, fight clock, win/lose, reset. |
| `character_view.gd` | KayKit model, weapons and animations for an actor. Visual only. |
| `debug_draw.gd` · `debug_hud.gd` | Debug view and text overlay. |
| `metrics.gd` | Autoload. JSONL to `user://run_*.jsonl`, path printed at startup. |
| `check.gd` | Headless asserts. |
| `demo_menu.gd` · `demos/` | Autoload. Start menu over every scene in `demos/`. |

Tunables are re-pushed every frame, so **edits in the remote inspector land live
while playing** (Debugger → Remote scene tree → Player).

## Tuning log

Starting numbers. Record where you actually land; that record is the deliverable.

| Knob | Start | Landed on |
|---|---|---|
| `move_speed` | 5.0 | |
| **camera** `pitch_deg` / `distance` / `follow_speed` | 50° / 12.5 / 6.0 | |
| `windup_time` / `active_time` / `recovery_time` | 0.22 / 0.10 / 0.35 | |
| `attack_damage` / `attack_reach` / `attack_arc` | 25 / 2.0 / 55° | |
| `sword_max_links` / `skill_max_links` / `chain_cooldown_per_link` | 5 / 3 / 1.0 s | |
| `link_charge_time` / `charge_move_mult` | 0.35 s / 0.35 | |
| `chain_first_range` / `chain_first_arc` / `chain_hop_range` | 6 m / 45° / 4.5 m | |
| `charge_turn_rate` | 720°/s | |
| `link_dash_time` / `link_standoff` | 0.07 s / 1.1 m | |
| `hitstop_time` / `hitstop_last` | 0.05 s / 0.10 s | |
| `hit_stagger` | 0.75 | |
| `bow_pierce` / `skill_pierce` / `pierce_falloff` | 2 / 1 / 15% | |
| `arrow_spread_deg` / **enemy** `toughness` | 8° / 1 | |
| `volley_cooldown` / `rain_cooldown_per_arrow` | 2 s / 0.25 s | |
| `rain_min_diameter`–`rain_max_diameter` / arrows / `rain_grow_time` | 1–5 m / 4–20 / 1.5 s | |
| `rain_range` / `rain_follow_speed` / `rain_damage` / `rain_hit_radius` | 14 m / 6 m/s / 15 / 0.8 m | |
| `attack_knockback` / `link_knockback` / `finisher_knock_mult` | 1.2 m / 2.5 m / 2.5 | |
| `dodge_time` / `dodge_distance` / `dodge_cooldown` | 0.40 / 3.5 / 0.65 s | |
| `iframe_start` / `iframe_end` | 0.05 / 0.28 | |
| **enemy** `windup_time` / `recovery_time` | 0.60 / 0.60 | |
| **enemy** `standoff` / `damage` / `move_speed` | 2.15 / 25 / 3.0 | |
| **enemy** `knockback` | 1.0 m | |

## Gates

- **Stage 1:** moving and swinging at nothing feels responsive.
- **Stage 2:** you fight the enemy ten times in a row without forcing yourself.
- **Stage 3 — decided:** health never regenerates on its own. Healing
  will come from consumables, magic or companions (not built in this prototype).

Not built yet: jump/traversal, healing. Parry exists but ships off (`parry_enabled`) until block
feels right.

## Logs

One `run_*.jsonl` per launch. `fight_end` carries `winner`, `enemies`,
`time_to_kill`, `player_hp_left`. Hits taken and dodges are counted from the event
stream rather than stored twice.

```bash
cd ~/Library/Application\ Support/Godot/app_userdata/isolated && python3 -c '
import json,glob
for f in sorted(glob.glob("run_*.jsonl")):
    ev=[json.loads(l) for l in open(f)]
    ends=[e for e in ev if e["ev"]=="fight_end"]
    ttk=[e["time_to_kill"] for e in ends if e["winner"]=="player"]
    print(f, "fights",len(ends), "won",len(ttk),
          "avg_kill %.1fs"%(sum(ttk)/len(ttk)) if ttk else "-",
          "hits_taken",sum(e["ev"]=="player_hit" for e in ev))'
```

Quit the game between sessions; a session left running with enemies spawned logs
thousands of idle deaths.
