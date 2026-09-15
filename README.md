# isolated — ISOLA combat prototype

Stages 1-2 of `../isola/ISOLA_Combat_Test_Plan.md`, with the combined click/charge
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
i-frames, stagger, chain cancel, input buffer, held charge, block, parry. It needs
no scene and no window.

## Controls

`WASD` move · `Space` dodge · **hold RMB** block · `1`/`2` sword/bow ·
`-`/`=` enemy count · `F1` debug · `Esc` free the cursor · `R` restart.
Facing follows the mouse.

**Sword**

| Input | Result |
|---|---|
| **Click** | Swing at the cursor. Base damage and knockback, no dash. It fires on press, so a click adds no delay. |
| **Click again** | Buffered, and chains into the next swing (up to 3). Follow-ups dash in. |
| **Hold** | The swing pauses at the top of its wind-up and charges (up to `charge_time`, 1s). Move at 35%. |
| **Hold + pull back** | Aims the charge the opposite way, like drawing the bow. |
| **Release** | Sends the charged strike, turning you to face it. Charge scales damage, arc, stagger, knockback and dash. |
| **Space while charging** | Rolls out. The wind-up before the hold point is still committed. |

**Bow:** hold, pull back, release.

A click and a charge are the same swing. The only difference is whether the button
is still down when the wind-up would release, which is the Dark Souls heavy-attack
trick: pressing never waits, and a charge never forces an extra swing first. Each
swing belongs to the press that started it, so clicking again to chain queues the
next swing instead of charging the current one.

Charging drains `sword_drain` stamina; running out sends the strike. Pull-back
under `charge_aim_deadzone` (25px) strikes straight ahead. `cone_deg` (180 =
anywhere) limits how far to the side a charge can be aimed.

Verified in scripted runs: a click hits exactly one wind-up (0.22s) after the press;
dash is 0 m on a plain click, 0.99 m on each chain follow-up, and 1.56 m on a 58%
charge (target 1.58 m); a 1s hold with pull-back released at 83% for 45.8 damage.

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
| Chain swings 1 / 2 / 3 | `Melee_1H_Attack_Slice_Horizontal` / `_Slice_Diagonal` / `_Stab` |
| Held charge | `Melee_1H_Attack_Jump_Chop`, frozen at the top of its wind-up |
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
turns, so mouse aim, WASD and the charge pull-back keep meaning the same direction
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

## Chaining — buffer and cancel

Click in rhythm; don't wait. A click made while a swing is still coming out is
**buffered** (the label shows `BUFFERED`) and fires on the first frame it legally
can. A buffered follow-up may also **cancel the previous swing's recovery**, so a
3-hit chain comes out in about 0.6s (the `CANCEL` popup marks each one).

What stays committed: wind-up and active frames are never cancelled, and nothing
cancels into a dodge. Only the dead time after a swing is given up, and only to the
next swing in the chain.

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

Your hits shove enemies straight away from you: 0.6 m light, more with charge,
×2.5 on the last swing of a chain. A **committed enemy isn't moved**
(`armor_knock_mult` 0), because pushing it out of range mid-swing cancels its
attack through distance, which is stunlock again. Enemies shove you too, and a dodge
shrugs it off. Getting hit mid-chain can push you out of your own reach; the
follow-up dash is what closes that gap.

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
  up or charging (widens with charge, white line = aim), red while active, then a
  fading ghost. **An outline turns green while the other actor's centre is inside
  it**: that swing would connect right now.
- **Enemy**: its attack arc and a faint `standoff` ring.
- **Bow**: the shot cone while drawing, then a tracer (green hit, red miss).
- **Rings**: cyan i-frames, magenta stagger, grey blocking, white armed parry.
- **Labels**: weapon, state with timer, `chain n/3`, hits landed, `CHARGE %`,
  health, stamina, `BUFFERED`, and `PUNISH` when an enemy is open.
- **Popups**: damage with `hit n/3`, `FINISHER`, charge, and `STAGGER` / `KILL` or
  `no stagger (committed)`; `CANCEL`; damage taken, `BLOCK`, `GUARD BREAK`,
  `PARRY`, `DODGED`; arrow strength.

## Files

| | |
|---|---|
| `combat_state.gd` | Action FSM: wind-up/active/recovery/dodge/stagger, stamina, health, held charge, chain cancel. Pure. Shared by player and enemy. |
| `stance_state.gd` | Weapon hand: bow/block stances, chain counter, input buffer, block/parry resolution. Pure. Player only. |
| `gesture.gd` | Pull-back drag for bow and charge aim; flick detection, now only for parry. Pure. |
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
| `attack_lunge` / `lunge_time` | 1.0 m / 0.08 s | |
| `charge_time` / `charge_move_mult` | 1.0 s / 0.35 | |
| `charge_damage_mult` / `charge_lunge_mult` | 1.0 / 1.0 | |
| `chain_windup_time` / `chain_recovery_time` | 0.12 / 0.20 | |
| `chain_cancel_from` / `buffer_window` / `chain_window` | 0.0 / 0.4 / 0.45 | |
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
