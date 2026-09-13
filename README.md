# isolated — ISOLA combat prototype

Stage 1 of `../isola/ISOLA_Combat_Test_Plan.md`. **Disposable.** Per §8 what carries
forward is the tuning knowledge and the numbers, not this code.

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
| `metrics.gd` | Autoload. JSONL to `user://run_*.jsonl`, path printed at startup. |
| `debug_hud.gd` · `check.gd` · `arena.tscn` | |

Tunables are re-pushed into `CombatState` every frame, so **edits in the remote
inspector land live while playing** (Debugger → Remote scene tree → Player).

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

Most likely wrong, in order: `recovery_time` (the commitment — the whole thesis,
and the easiest to overdo), `turn_speed`, `ground_accel`, `iframe_start`.

## Gate

> Moving and swinging at nothing feels responsive.

Not built, deliberately: enemy, corridor, hazard, stealth, block, parry, combos,
hit VFX, health bars. §4 — *"Do not proceed to stage 2 to 'see if enemies help.'
They won't."*

Stage-1 log events: `session_start` `session_end` `attack` `attack_refused`
`dodge` `dodge_refused` `ignored` `camera_blame` `restart`. A high `ignored`
count means `recovery_time` is too long. Not logged yet because there is nothing
to log them against: time-to-kill, hits taken, dodge successes, deaths by
corridor position.
