# isolated — ISOLA combat prototype

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

## Controls

`WASD`/arrows or left stick · `J`/LMB/RB attack · `Space`/B dodge ·
`R`/Start restart · `C`/Back flag a camera-contributed hit

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
