# isolated — ISOLA combat prototype

Stages 1-2 of `../isola/ISOLA_Combat_Test_Plan.md`, with the click / charged-chain
sword. **Disposable.** Per §8 what carries forward is the tuning knowledge and the
numbers, not this code.

Godot **4.7.2 mono** — `/Users/wesleychase/Downloads/Godot_mono.app`.
(`/Applications/Godot.app` is 4.2.1 and cannot open this project.)

## Run

```bash
GODOT=/Users/wesleychase/Downloads/Godot_mono.app/Contents/MacOS/Godot

$GODOT --headless --path . --script res://check.gd   # logic check, prints OK
$GODOT --editor --path .                             # then F5
```

`check.gd` asserts the combat rules that break quietly: commitment, stamina gating,
i-frames, stagger, held charge, chain link count and target path, block, parry. It needs
no scene and no window.

## Controls

`WASD` move · `Space` dodge · **hold RMB** block · `1`/`2` sword/bow ·
`-`/`=` enemy count · `F1` debug · `Esc` free the cursor · `R` restart.
Facing follows the mouse.

**Sword**

| Input | Result |
|---|---|
| **Click** | One arc swing at the cursor. Base damage and knockback, **never dashes**. Fires on press. A click during a swing is ignored; there is no combo. |
| **Hold** | The swing pauses at the top of its wind-up and charges. Move at 35%, stamina stops regenerating. The **chain path** is drawn on the ground: yellow rings are locked-in targets, the faint ring is the one the next link would add. |
| **Release** | Dash-strikes each target on the path in turn: invulnerable, a whole-game hit freeze on every hit, and the last link knocks them flying. No target in range: it goes out as a plain arc. |
| **Space while charging** | Rolls out. The wind-up before the hold point is still committed. |

**Bow:** hold, pull back, release.

**Links.** One link is free, and each `link_charge_time` (0.35s) held adds another,
up to the lowest of:

- `sword_max_links` (5), the weapon;
- `skill_max_links` (3), a plain export until there is a skill system;
- what stamina can pay at `link_cost` (12) each. A click already paid for one link, and a chain pays for the rest on release.

**Targets.** The first is the enemy nearest the **cursor**, within `chain_first_range`
(6m) of you. Each next one is the nearest unvisited enemy within `chain_hop_range`
(4.5m) of the last. The chain stops early when nothing is in range.

**The strike.** Each link dashes to `link_standoff` (1.1m) short of its target in
`link_dash_time` (0.07s), passing through other bodies. The freeze lasts `hitstop_time`
(0.05s), or `hitstop_last` (0.10s) on the last link. Earlier links don't knock back,
so targets stay where the path said they were.

Verified in a scripted run with 4 enemies in a line: a click moved the player 0.000m.
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

Your hits shove enemies straight away from you: 0.6 m light, and
×2.5 on the last link of a chain (earlier links don't knock). A **committed enemy isn't moved**
(`armor_knock_mult` 0), because pushing it out of range mid-swing cancels its
attack through distance, which is stunlock again. Enemies shove you too, and a dodge
shrugs it off.

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
- **Bow**: the shot cone while drawing, then a tracer (green hit, red miss).
- **Rings**: cyan i-frames, magenta stagger, grey blocking, white armed parry.
- **Labels**: weapon, state with timer, links landed, `links n/cap (weapon · skill · stamina)`
  while charging, `CHAIN n/m` while it plays, health, stamina, and `PUNISH` when an enemy is open.
- **Popups**: damage with `link n/m`, `FINISHER`, and `STAGGER` / `KILL` or
  `no stagger (committed)`; damage taken, `BLOCK`, `GUARD BREAK`,
  `PARRY`, `DODGED`; arrow strength.

## Files

| | |
|---|---|
| `combat_state.gd` | Action FSM: wind-up/active/recovery/dodge/stagger, stamina, health, held charge, held active window. Pure. Shared by player and enemy. |
| `stance_state.gd` | Weapon hand: bow/block stances, block/parry resolution, chain link count and target path. Pure. Player only. |
| `gesture.gd` | Pull-back drag for the bow; flick detection, now only for parry. Pure. |
| `camera_relative.gd` | Screen/stick direction → world direction. |
| `follow_camera.gd` | Smooth fixed-angle follow camera. |
| `player.gd` | Input, aim, movement, hits. Every tunable is `@export`. |
| `enemy.gd` · `enemy.tscn` | The enemy. |
| `fight.gd` | Spawning, enemy-count controls, fight clock, win/lose, reset. |
| `character_view.gd` | KayKit model, weapons and animations for an actor. Visual only. |
| `debug_draw.gd` · `debug_hud.gd` | Debug view and text overlay. |
| `metrics.gd` | Autoload. JSONL to `user://run_*.jsonl`, path printed at startup. |
| `check.gd` | Headless asserts. |

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
| `sword_max_links` / `skill_max_links` / `link_cost` | 5 / 3 / 12 | |
| `link_charge_time` / `charge_move_mult` | 0.35 s / 0.35 | |
| `chain_first_range` / `chain_hop_range` | 6 m / 4.5 m | |
| `link_dash_time` / `link_standoff` | 0.07 s / 1.1 m | |
| `hitstop_time` / `hitstop_last` | 0.05 s / 0.10 s | |
| `hit_stagger` | 0.75 | |
| `attack_knockback` / `finisher_knock_mult` | 0.6 m / 2.5 | |
| `dodge_time` / `dodge_distance` / `dodge_cost` | 0.40 / 3.5 / 30 | |
| `iframe_start` / `iframe_end` | 0.05 / 0.28 | |
| `regen_rate` / `regen_delay` | 45 / 0.55 | |
| **enemy** `windup_time` / `recovery_time` | 0.60 / 0.60 | |
| **enemy** `standoff` / `damage` / `move_speed` | 2.15 / 25 / 3.0 | |
| **enemy** `knockback` | 1.0 m | |

## Gates

- **Stage 1:** moving and swinging at nothing feels responsive.
- **Stage 2:** you fight the enemy ten times in a row without forcing yourself.

Not built yet: the corridor (stage 3), hazard (4), stealth (5), jump/traversal,
hit VFX, health bars. Parry exists but ships off (`parry_enabled`) until block
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
