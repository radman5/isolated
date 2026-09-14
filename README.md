# isolated — ISOLA combat prototype

> **Branch `stage2b-gesture`.** The button build is frozen at tag `stage2-button`.
> Both share the stagger implementation; `git merge-base` proves it.

Stages 1-2 of `../isola/ISOLA_Combat_Test_Plan.md`. **Disposable.** Per §8 what
carries forward is the tuning knowledge and the numbers, not this code.

> **Note:** Stage 2 was built before the Stage 1 gate was evaluated, by explicit
> decision. §4 warns that stage 2 will not rescue a failed stage 1, so if the
> base verbs turn out to feel wrong, the enemy work does not save them.

Godot **4.7.2 mono** — `/Users/wesleychase/Downloads/Godot_mono.app`.
(`/Applications/Godot.app` is 4.2.1 and cannot open this project.)

## Run

```bash
GODOT=/Users/wesleychase/Downloads/Godot_mono.app/Contents/MacOS/Godot

$GODOT --headless --path . --script res://check.gd   # logic check, prints OK
$GODOT --editor --path .                             # then F5
```

`check.gd` asserts the four things that silently ruin a feel test: a swing can't be
cancelled, stamina gates both verbs, i-frames open and close on the right frames,
stamina regen waits then stops at the cap. It needs no scene and no window.

## Controls (gesture build)

`WASD` move · **hold LMB** draw weapon · **flick the mouse** to strike ·
**hold RMB** block · `Space` dodge · `1`/`2` sword/bow · `Esc` free the cursor ·
`R` restart · `C` flag a camera-contributed hit

Facing follows the mouse. Rotation is clamped by stance — 720°/s free, 180°/s in
a stance, **0 while the bow is drawn**. Dodge is the one input with no gesture
involvement, deliberately (§7): the input most needed under pressure has to be
instant and unambiguous.

### Debug view — `F1` (or `` ` ``) toggles

Drawn by `debug_draw.gd`. It only observes the game and never takes part in it,
so removing the node changes nothing about play.

- **Arcs** on the ground are the real hit test: reach and half-angle, measured
  to the target's **centre** (the small cross), height ignored. Grey while a
  stance is held (the arc your next flick would get, with the ±cone edges),
  yellow in wind-up, red while active, then a fading red ghost so the six active
  frames can actually be seen. **An outline turns green while the other actor's
  centre is inside it**: that swing would connect right now.
- **Enemy**: its attack arc and a faint `standoff` ring.
- **Bow**: the shot cone while drawing (green outline = on target), then a tracer
  and a travelling arrowhead on release. Green means hit, red means miss.
- **Rings** under an actor: cyan for i-frames, magenta for stagger, grey for
  blocking, white for an armed parry.
- **Labels** over each head: stance, state with its timer, `chain n/3`, hits
  `landed` this chain, charge or draw %, health and stamina, and `PUNISH` when
  the enemy is open.
- **Popups**: damage dealt with `hit n/3`, charge, and either `STAGGER 0.94s` or
  `no stagger (committed)` (the trade rule, visible). Also damage taken,
  `BLOCK`, `GUARD BREAK`, `PARRY`, `DODGED`, `CLAMPED asked +x°`, and arrow
  strength.

### Calibrate the flick threshold first

`1200 px/s` is a guess, and whether macOS reports retina motion in physical or
logical pixels is not documented. Flick five times and read **`peak`** on the
overlay, then set `flick_threshold` from it and record it below.

## Files (gesture build)

| | |
|---|---|
| `gesture.gd` | Flick detection + bow drag. Pure. No ring buffer — `InputEventMouseMotion.screen_velocity` is already px/s. |
| `stance_state.gd` | The second state axis: stance, charge, chain, block/parry. Player only. |

Two axes, not one enum: `combat_state.gd` says what your body is committed to,
`stance_state.gd` says what your weapon hand is doing. A flick fires the *existing*
committed WINDUP/ACTIVE/RECOVERY, so a swing means the same thing for both sides.

## Files

| | |
|---|---|
| `combat_state.gd` | Stamina + attack/dodge FSM. Pure, no engine coupling. Everything stage 1 tests. |
| `camera_relative.gd` | Camera-relative input + the §3 input-transition latch. |
| `player.gd` | `CharacterBody3D`. Holds every tunable, decides *where* things move. |
| `enemy.gd` | Stage 2. Runs the *same* `CombatState`, fed by AI instead of `Input`. |
| `fight.gd` | On the Arena root. Fight clock, win/lose, reset. |
| `metrics.gd` | Autoload. JSONL to `user://run_*.jsonl`, path printed at startup. |
| `debug_hud.gd` · `check.gd` · `arena.tscn` | |

Tunables are re-pushed into `CombatState` every frame, so **edits in the remote
inspector land live while playing** (Debugger → Remote scene tree → Player).

## The stage 2 loop

Telegraph (yellow, 0.60s) -> dodge through it -> punish during recovery (0.60s).
Both sides run the same committed state machine, so "committed" means the same
thing for the enemy as it does for you.

`standoff` (2.15) is deliberately just outside your `attack_reach` (2.0): you
have to step in to punish. Drop it below your reach and the punish window
becomes free, which removes the spacing game entirely.

Verified mechanically, not by eye: dodging on the telegraph took **zero damage
across five consecutive attacks**. A late dodge still loses - the tail of the
roll is vulnerable by design (`iframe_end` 0.28 < `dodge_time` 0.40).

### Stagger (Stage 2b decision, in BOTH builds)

A landed hit freezes the enemy for `hit_stagger` (0.75s) - **unless it is already
committed to a swing.** That exception is the mechanic:

- Hit into its telegraph and you trade. You both land. Attacking at the wrong
  moment costs you.
- Hit during its RECOVERY and you extend the punish window enough for a second
  swing. Correct timing is what stagger rewards.

Without the exception a hit cancels the 0.6s wind-up outright, the player swings
faster than that, and the enemy never attacks at all - measured at 3.34s of
mashing for **zero** damage taken, i.e. stagger made trading *better*.

Measured with scripted strategies (`hit_stagger` sweep, bots not hands):

| `hit_stagger` | mash | dodge-and-punish |
|---|---|---|
| 0.25 | 3.34s, 50 hp | 9.53s, 75 hp |
| 0.50 | 3.33s, 50 hp | 6.0s, 75 hp |
| **0.75** | **3.32s, 75 hp** | **4.8s, 100 hp** |
| 1.00 | 3.31s, 75 hp | 4.78s, 100 hp |

0.75 is the knee. Mashing stays ~1.5s faster but costs 25 hp; playing well takes
none. In stage 3 that 25 hp compounds across three fights, which is the whole
attrition hypothesis. Still to be confirmed by hands on the controls.

Known and left for you to tune: the enemy has no retreat and never backs off,
and a neutral dodge rolls you forward into it.

## A/B protocol (§12 — the actual deliverable)

```bash
git switch --detach stage2-button   # relaunch editor, 5 fights, QUIT
git switch stage2b-gesture          # relaunch editor, 5 fights, QUIT
```

**One launch per build, quit between.** Each launch writes one `run_*.jsonl` with
one `session_start` carrying `input_mode`, so each file is self-labelling.

**Use sword + dodge only during the runs.** Bow and block exist here but not in
the button build; using them makes the comparison measure option count rather
than input grammar, which is the one thing it is for.

One honest asymmetry: the button build has no charge, so its stagger is always
the 0.75 floor, while this build scales 0.75–1.2. Unavoidable — charge is part of
the grammar being compared. The floor is identical.

Compare time-to-kill, hits taken, and the metric that decides it: **which one you
want to play again.**

## Tuning log

Starting numbers. Record where you actually land — that record is the deliverable.

| Knob | Start | Landed on |
|---|---|---|
| `move_speed` | 5.0 | |
| `ground_accel` | 45.0 | |
| `turn_speed` | 12.0 | |
| `windup_time` | 0.22 | |
| `active_time` | 0.10 | |
| `recovery_time` | 0.35 | |
| `attack_lunge` | 0.6 | |
| `attack_cost` | 25.0 | |
| `dodge_time` | 0.40 | |
| `dodge_distance` | 3.5 | |
| `iframe_start` | 0.05 | |
| `iframe_end` | 0.28 | |
| `dodge_cost` | 30.0 | |
| `regen_rate` | 45.0 | |
| `regen_delay` | 0.55 | |
| **enemy** `windup_time` | 0.60 | |
| **enemy** `recovery_time` | 0.60 | |
| **enemy** `standoff` | 2.15 | |
| **enemy** `damage` | 25.0 | |
| **enemy** `move_speed` | 3.0 | |
| `hit_stagger` | 0.75 | |
| `flick_threshold` | 1200 px/s | **calibrate me** |
| `cone_deg` | 60 | |
| `charge_time` | 1.0 | |
| `chain_window` | 0.45 | |

Most likely wrong, in order: `recovery_time` (the commitment — the whole thesis,
and the easiest to overdo), `turn_speed`, `ground_accel`, `iframe_start`.

## Gates

- **Stage 1:** moving and swinging at nothing feels responsive.
- **Stage 2:** you fight the enemy ten times in a row without forcing yourself.

Still not built, deliberately: the corridor (stage 3), hazard (4), stealth (5),
block, parry, combos, jump/traversal, hit VFX, health bars.

## Log events

`session_start` `session_end` `fight_start` `fight_end` `attack`
`attack_refused` `dodge` `dodge_refused` `ignored` `enemy_attack` `enemy_hit`
`player_hit` `dodge_success` `camera_blame` `restart`

A high `ignored` count means `recovery_time` is too long. `fight_end` carries
`time_to_kill` and `winner`.

Hits taken and dodge attempts/successes are **not** counted into summary fields
on purpose - every hit is already a timestamped event, so they are a jq window
between `fight_start` and `fight_end`. A second copy of a number is a second
number that can disagree.

```bash
LOG=~/Library/Application\ Support/Godot/app_userdata/isolated/run_*.jsonl
jq -s '[.[]|select(.ev=="fight_end")]|map(.time_to_kill)' $LOG   # time-to-kill
jq -s '[.[]|select(.ev=="player_hit")]|length' $LOG              # hits taken
jq -s '[.[]|select(.ev=="dodge")]|length' $LOG                   # dodge attempts
jq -s '[.[]|select(.ev=="dodge_success")]|length' $LOG           # ...that worked
```

Still not logged, because stage 3 does not exist yet: deaths by corridor
position.
