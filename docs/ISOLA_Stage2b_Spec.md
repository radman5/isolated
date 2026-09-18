# ISOLA — Combat Prototype, Stage 2b

**Gesture Combat — Coding Agent Handover Spec**

> Variant branch off *ISOLA Combat Prototype Test* §4. Replaces the input layer of Stages 1–2. Does **not** restart the test.

**Goal:** the same Stage 2 enemy, fought with a gesture-driven input system instead of button presses, so the two can be played back to back and compared directly.

**The comparison is the deliverable.** You already have the button version in your hands. That baseline is the most valuable thing in this stage.

---

## 1. What Carries Over

Unchanged from Stages 1–2: stamina as a resource, the committed-attack principle, the Stage 2 enemy with its telegraph and punish window, the fixed camera, grey-box art, the debug overlay and CSV logger, and the whole attrition hypothesis.

**Only the input layer changes.** Keep the button version on a branch — you will be playing them against each other.

---

## 2. The Core Grammar

One consistent rule across every weapon:

> **Hold to commit → mouse motion to express → release to resolve.**

| | Left button held | Not held |
|---|---|---|
| **Sword** | Stance: charging, flick to strike | Free aim, no gesture reads |
| **Bow** | Draw: drag back to load, release to fire | Free aim, no gesture reads |
| **Right button held** | Block stance (either weapon) | — |

**The load-bearing rule: gestures only register while a button is held.** Free mouse movement never triggers anything. Without this, aiming at a moving enemy fires attacks constantly.

---

## 3. Facing & Aim

Facing comes from the **mouse**, not movement direction. Raycast from camera through cursor to the Y=0 plane; the player turns toward that point.

**Rotation speed is clamped, and the clamp changes by state:**

| State | Max rotation |
|---|---|
| Free | 720°/s (effectively instant) |
| Sword stance held | 180°/s |
| Block stance held | 180°/s |
| Bow drawn | **0°/s — facing fully locked** |

Slowed rotation while committed is what makes positioning matter and being flanked genuinely dangerous. It is the mechanical expression of "you are an ordinary person, not a magic swordsman."

### Movement while committed

| State | Move speed |
|---|---|
| Free | 100% |
| Sword stance held | 50% |
| Block stance held | 40% |
| Bow drawn | 35% |
| Dodging | scripted |

---

## 4. The Sword

### Sequence

1. **Hold LMB** — sword draws back, stance entered, charge begins accumulating, stamina drains continuously
2. **Charge caps** at max after a set duration — holding beyond that is pure stamina waste
3. **Flick the mouse** in the strike direction — swing fires
4. **Chain**: further flicks while still holding produce fast light follow-ups, up to the cap
5. **Release LMB** — stance exits, weapon returns to neutral

### Flick detection — the latency rule

**Fire the swing the instant the velocity threshold is crossed, not when the gesture completes.** Detect that a flick has *started*, never that one *happened*. Waiting for gesture completion adds 50–100ms of input lag that no amount of tuning will hide.

Direction is taken from the mouse delta vector at the moment of threshold crossing.

### The direction cone

Strike direction is **clamped to ±60° of current facing.** A flick outside the cone clamps to the nearest cone edge — it never fails silently and never rotates the player.

This is what makes the slow rotate meaningful: lining up a strike is a positioning act, not a wrist act.

### Charge

Charge level scales damage, swing arc, and stagger. It applies to the **first** swing of a chain only — chained follow-ups are always light.

### Chaining

- **Cap: 3 swings total per stance hold** (1 charged + 2 chained)
- Each chained flick costs stamina; the chain also ends when stamina is insufficient
- **Swing side alternates automatically** (left-to-right, right-to-left) — this produces swordplay rhythm with no combo system underneath
- Chain window: a further flick must come within a short time of the previous swing, or the chain resets

> **v2 hook — do not build now.** Later intent is that a completed 3-hit chain can be extended by swapping weapons mid-chain. Structure `ChainState` so the cap and the reset condition are separable and a weapon swap could plausibly reset the counter without resetting the chain. Leave the hook; build nothing.

---

## 5. The Bow

1. **Hold LMB** — arrow loads, **facing locks immediately**
2. **Drag the mouse away** from the intended target — the cursor is the bowstring
3. Drag distance = draw strength; shot direction = the vector **opposite** the drag
4. **Release LMB** — fires

The bow needs no separate aim. Drag-back supplies direction and magnitude in one continuous motion, adjustable until release.

**Feedback:** draw a debug line from the player to the cursor plus an arrow indicator along the firing vector. This reads instantly and is the whole reason the mechanic works.

**Open question — flagged, not decided:** whether block stance is available with the bow equipped. Default for this test: **no block with bow.** Bow users have dodge only. This is likely good — ranged safety should cost defensive options — but it is untested.

---

## 6. Block & Parry — Build In This Order

> **Parry is on the original do-not-build list and that reasoning still holds.** Window length, failure recovery, what it rewards and how it reads are among the most expensive things in melee combat to tune — and here the input is *also* a gesture, compounding the two hardest problems at once. Building parry first will consume the entire stage and teach nothing about whether gesture combat works.

### Part 1 — Block stance (build first)

- **Hold RMB** — block stance, slowed movement and rotation
- Incoming hits cost stamina and deal reduced chip damage instead of full damage
- **Stance breaks** if stamina empties — player is staggered and vulnerable
- No stamina regeneration while the stance is held

**Gate: block must feel good before Part 2 exists.**

### Part 2 — Parry (build only after Part 1 passes its gate)

- A **flick while in block stance**, within a short window before impact, negates the hit and staggers the enemy
- **Successful parry refunds its stamina cost. A failed flick costs stamina and leaves the player open.**
- Implement as a single flag that can be switched off to A/B block-only against block-plus-parry

*The refund-on-success rule matters: stamina now gates dodging, charging, swinging, chaining and blocking, and five systems on one bar is how a player ends up unable to act at all and feeling cheated. Parry should reward reading the enemy, not consume resource.*

---

## 7. Dodge — Stays On A Button

**Space. Direction from WASD, or facing if no input. No gesture involvement whatsoever.**

Flick-to-dodge was considered and rejected: when not holding a button the mouse is aiming, tracking a moving enemy means constant fast mouse motion, and every one of those would register as a flick. The input most needed under pressure must be the one that is instant and unambiguous. Nothing expressive is lost — nobody admires a dodge.

---

## 8. Stamina Economy

Single bar, 0–100. **Starting values only — all `[Export]`, tune by feel.**

| Action | Cost |
|---|---|
| Sword stance hold | 12/s drain while charging |
| Charged swing release | 15 |
| Chained swing | 10 each |
| Bow draw hold | 8/s drain |
| Bow release | 10 |
| Block stance hold | 5/s drain |
| Hit absorbed while blocking | 20 |
| Parry — success | 0 (cost refunded) |
| Parry — failure | 15 |
| Dodge | 25 |
| Regeneration | 25/s after 1.0s delay |

**No regeneration while any stance is held.** Charge caps at 1.0s of hold.

---

## 9. Implementation Notes

### New scripts

```
scripts/
├── input/
│   ├── GestureRecognizer.cs      ← flick detection, threshold crossing
│   ├── MouseAimController.cs     ← raycast to plane, clamped rotation
│   └── DragVectorTracker.cs      ← bow draw
├── player/
│   ├── WeaponStance.cs           ← stance state machine
│   ├── ChainState.cs             ← chain counter, side alternation, v2 hook
│   └── BlockComponent.cs         ← block, parry flag
```

### `GestureRecognizer.cs`

Sample mouse delta per frame into a short ring buffer. Emit `FlickDetected(Vector2 direction, float magnitude)` **the frame the velocity threshold is crossed**, then enter a brief refractory period so one physical flick cannot fire twice. Exports: velocity threshold, refractory duration, buffer length.

### State machine

Extend the Stage 1 enum rather than replacing it. New states: `SwordStance`, `SwordSwing`, `BowDraw`, `BlockStance`, `ParryWindow`, `StanceBreak`. The commitment rule still applies — swings cannot be cancelled once started.

### Debug overlay additions

Current stance · charge level · chain count · last flick direction and magnitude · flicks rejected as below threshold · cone clamp applied (bool) · draw strength · block stamina remaining · parry window active.

### Logger additions

`stance_entered`, `stance_exited`, `flick_detected`, `flick_rejected`, `swing_fired`, `chain_extended`, `chain_capped`, `cone_clamped`, `draw_started`, `arrow_fired`, `block_entered`, `hit_blocked`, `stance_broken`, `parry_success`, `parry_failed`.

---

## 10. Tuning Values — Starting Points

| Value | Start |
|---|---|
| Flick velocity threshold | 1200 px/s |
| Flick refractory | 0.12s |
| Direction cone | ±60° |
| Charge time to max | 1.0s |
| Chain window | 0.45s |
| Chain cap | 3 swings |
| Rotation — free | 720°/s |
| Rotation — stance | 180°/s |
| Bow max draw distance | 300 px |
| Parry window before impact | 0.20s |
| Block chip damage | 25% of incoming |

---

## 11. Acceptance Criteria

Agent-verifiable:

- [ ] Gestures register **only** while a button is held — free mouse movement triggers nothing
- [ ] Flick fires on threshold crossing, not gesture completion
- [ ] Strike direction clamps to the cone and never rotates the player
- [ ] Rotation clamp differs correctly per state; bow draw locks facing entirely
- [ ] Chain caps at 3 and alternates swing side automatically
- [ ] Bow fires opposite the drag vector with strength proportional to drag distance
- [ ] Block absorbs hits at stamina cost and breaks when stamina empties
- [ ] Parry exists behind a single toggleable flag
- [ ] Dodge is Space-only with no gesture involvement
- [ ] No stamina regeneration while any stance is held
- [ ] All values `[Export]` and runtime-editable
- [ ] All new log events written

**Manual gate:**

- [ ] Flicking feels like swinging, not like drawing a symbol
- [ ] No accidental swings while aiming or repositioning
- [ ] The cone clamp feels like a constraint on your body, not a bug
- [ ] Bow drag-back reads instantly without explanation
- [ ] The stance-held slow rotate makes positioning matter rather than feeling sluggish
- [ ] Input lag is not perceptible on the swing

---

## 12. The A/B Test — The Actual Point

Once Stage 2b passes its manual gate:

1. Fight the **Stage 2 enemy** with the button system. Five runs.
2. Fight the **same enemy** with the gesture system. Five runs.
3. Same day, back to back, same enemy, same arena.

**Compare:** time-to-kill, hits taken, and — the metric that decides it — **which one you want to play again.**

A gesture system that is merely *interesting* loses to a button system that is *good*. Gesture combat is pure feel, the most expensive thing to tune solo, and it is worth its cost only if it wins this comparison outright.

Both outcomes feed the Stage 5 verdict. Neither wastes the work.

---

## 13. Out of Scope

Weapon swapping · chain extension past 3 · gamepad support · multiple camera angles · animation beyond capsule orientation · sound · input buffering · enemy variety · lock-on · parry before block passes its gate.

---

## 14. GDD Consequence — Action Required

Mouse-to-world aiming requires that screen-to-world mapping mean the same thing everywhere.

> **Varied fixed camera angles per combat space are now off the table. The game uses one consistent camera angle throughout.**

Update ISOLA GDD §3 (camera rules) accordingly. This does not affect fixed-versus-follow — the camera stays fixed — only the variety of angles.
