# ISOLA — Real-Time Combat Prototype Test

**Test Plan v0.1 — Companion to ISOLA GDD §9**

> **Purpose:** determine whether a real-time combat system is viable for this project, before committing production time to one. This is a disposable prototype. None of it needs to ship.

| Timebox | Budget | Rate | Engine |
|---|---|---|---|
| 8 calendar weeks — hard stop | ~60 hours | 5–10 hrs/week | Godot 4 + C#, macOS |

**Note on the timebox:** at 5–10 hours a week, the commonly-quoted "two week prototype" is six to eight calendar weeks of real time. Plan against the real number. Being in stage 2 in week four is on schedule, not behind.

---

## 1. What This Test Is Answering

**Primary question:** is real-time combat good enough here to justify its cost, or should the project use turn-based instead?

**Secondary question:** does *attrition across a journey* differentiate this from dense per-room action combat (the Moonlighter comparison)?

**This test does not answer:** enemy variety, weapon variety, progression, loot, balance, or anything about the shipped game's content. Those are production questions and belong after the verdict.

---

## 2. Design Basis

Combat is **not** a main pillar of ISOLA. That is the design brief, not a weakness, and it drives every decision below.

### Inverting the dense-action model

| Dense action (Moonlighter-like) | ISOLA |
|---|---|
| Hundreds of enemies per run | A handful per route |
| Individually forgiving, punishing in aggregate | Individually dangerous |
| Snappy, cancellable attacks | Committed attacks with wind-up |
| Fights you clear | Fights you remember |
| Tension: "can I get back with the loot?" | Tension: "can I get through at all?" |

### The core hypothesis: attrition, not per-room combat

**Health does not regenerate between fights.** You leave home at full, and whatever a route costs you, you carry to the end of it.

This is load-bearing because it:

- Makes a single fight matter without needing combos, depth, or a large moveset
- Makes *avoiding* a fight a genuine decision — fitting for an ordinary person with no magic
- Gives the healer recruit obvious mechanical weight
- Fits route-opening structurally: a one-way push through hostile ground, not a dungeon to dip in and out of

### The environmental layer

Using the room to win is the strongest expression of "you are ordinary in a world that isn't," and it collapses environmental puzzles and combat into one verb rather than two systems.

**It is deliberately tested last (stage 4), not first.** Environmental tricks are a *multiplier* on combat feel — multiplying something near zero still gives near zero. If the base fight is mushy, a clever hazard moment will paper over it and green-light a system that isn't actually good.

Full verticality (multi-level arenas) is **out of scope for the test**: navmesh across height, enemy pathing up and down, camera occlusion and elevation, falling and ledge rules, and the jump question. A pit or ledge hazard delivers height-as-threat for the price of one `Area3D`.

---

## 3. Locked Constraints

### Camera — fixed angles, PS1 style

Fixed camera plus real-time combat is a known hard pairing (the Resident Evil problem: the camera cuts, "forward" changes meaning mid-input, the player walks back the way they came). Tolerable when shuffling down a corridor; bad when dodging. Rules:

- **One fixed camera angle, the same throughout the game. The camera never cuts during a fight.**
- **Every combatant stays in frame.** If an enemy can leave the view, the space is designed wrong.
- **Movement is camera-relative.** On any cut outside combat, held input retains its previous meaning until the stick/key is released. (~20 lines, removes most of the pain.)

> **Amended by Stage 2b (§14 of that spec).** This bullet previously read "one fixed angle *per combat space*", allowing the angle to vary between spaces. Mouse-to-world aiming requires that screen-to-world mapping mean the same thing everywhere, so **varied angles are now off the table** — one consistent angle for the whole game. This does not change fixed-versus-follow; the camera stays fixed. Consequence in code: the input-transition rule above is now unreachable, since there are no cuts to transition across.

### Defensive options — dodge first, block conditionally

Building dodge *and* block simultaneously doubles the tuning problem at exactly the moment the test is trying to isolate whether one defensive verb feels good.

- **Stages 1–3: dodge only.**
- **Stage 4: add block only if dodge-only feels thin.**
- If added, the jobs must be clearly separate:
  - **Dodge** — avoids and repositions, i-frames
  - **Block** — holds ground, chip damage, stamina drain, breaks if held too long
- **No parry.** Parry is a tuning black hole; every hour on it is an hour not spent finding out whether the system works at all.

> **Stage 2b is an explicit exception to both rules above.** `ISOLA_Stage2b_Spec.md` §6 builds block at stage 2 and parry behind a flag, on the reasoning that a gesture grammar needs its defensive verbs to be judged as a whole. The original reasoning is not withdrawn — it is why §6 gates parry behind block passing its own gate first, and why `parry_enabled` ships **false**. If Stage 2b loses the A/B, this exception dies with it and the dodge-only rule stands unchanged for the button line.

### Player constraints

- **Physical weapons only.** No player magic, ever.
- One attack. One dodge. Stamina gates both.
- Attack has a wind-up, commits for its duration, **cannot be cancelled**.

### Build constraints

- **Grey boxes only.** Capsules, no art, no UI beyond debug text.
- **Port the character controller from RELICBORN** rather than rewriting it. This is a free week — take it.

### Explicitly not built during this test

Combos · multiple weapons · enemy variety · loot · levelling · attractive health bars · hit VFX · anything on a route intended to ship.

*All of it hides whether the core is good.*

---

## 4. The Five Stages

### Stage 1 — Arena & Verbs
**Weeks 1–2**

Flat grey plane. One fixed camera angle. Port the character controller across. Implement move, one committed attack (wind-up, non-cancellable), one dodge with i-frames, stamina gating both. Camera-relative movement with the input-transition rule.

**Gate:** moving and swinging at nothing feels responsive.

*If this gate fails, nothing after it matters. Do not proceed to stage 2 to "see if enemies help." They won't.*

---

### Stage 2 — One Enemy
**Weeks 3–4**

**One** enemy. Not three. It needs a readable telegraph, a committed attack, and a punish window afterwards. Tune until fighting this single enemy repeatedly is fun.

**Gate:** you fight it ten times in a row without forcing yourself.

---

### Stage 3 — The Attrition Corridor
**Week 5**

Three instances of that same enemy, spaced apart down a short corridor. **No healing between them.** Play it start to finish.

**Gate:** the third fight feels meaningfully different from the first, purely because you arrive at it already hurt.

*This stage is testing the central hypothesis of the whole design, not just the combat.*

---

### Stage 4 — One Hazard
**Week 6**

Add a single `Area3D` pit or hazard near the third enemy. Set that third enemy to be **unwinnable head-on** at the health the player would realistically arrive with.

Hazard options, cheapest first:

1. **Bait-into hazard** — pit, broken floor, fire. `Area3D` + death trigger. Near-free. *Recommended.*
2. **Pushable object** — crate or rock shoved down a slope. One rigidbody plus physics tuning.
3. **Collapsible** — attack a rotten beam to bring down a pillar. Trigger, animation, damage zone.

Also the decision point on adding block.

**The question:** can the player win a fight they'd lose straight-up, by using the room?

**Gate:** you reach for the hazard unprompted, and it feels clever rather than fiddly.

*If players grind the enemy down anyway, or fumble the hazard and feel cheated, that is a real finding — bought for the price of one `Area3D`.*

---

### Stage 5 — Avoidance & Verdict
**Weeks 7–8**

Add a vision cone to one enemy. Test whether sneaking past is a satisfying choice or simply boring. This is the cheapest possible version of stealth and is designed to be thrown away.

Then review the logs and deliver the verdict.

---

## 5. Instrumentation

Log throughout:

- Time-to-kill per fight
- Hits taken per fight
- Dodge attempts vs. dodge successes
- Deaths by corridor position (1st / 2nd / 3rd enemy)
- **Camera-contributed hits** — every time the camera arguably caused a hit

*That last one is the fixed-camera verdict, and it is the number most likely to kill the approach.*

### The metric that actually decides it

**Unforced replays of the corridor.** How many times do you play it again without telling yourself to?

Five or more is a pass. Finishing the corridor and immediately opening the design document instead is a fail, regardless of what the other numbers say.

---

## 6. Success Criteria

- [ ] One enemy is genuinely fun to fight alone, repeatedly
- [ ] Getting hit feels like the player's mistake — never the camera's, never the controls'
- [ ] The third corridor fight feels different from the first, purely from accumulated damage
- [ ] The hazard produces a "won a fight I shouldn't have" moment
- [ ] Five or more voluntary, unforced corridor replays
- [ ] Camera-contributed hits are rare enough to be a tuning problem, not a design problem

---

## 7. Kill Criteria

**Agreed in advance, while it is still cheap to agree.**

Build the **turn-based** system instead if, at week 8:

- The combat is merely **tolerable** rather than good, **or**
- The camera log shows the fixed camera is regularly at fault

**"Tolerable" is a real-time combat system's death sentence.** It only gets harder from here — animation timing, hit feel, frame data, and balance all compound. A system that is tolerable in grey boxes will not become good in production.

Fixed camera and turn-based is a much friendlier pairing, and it is a fallback that costs eight weeks rather than eight months.

---

## 8. Post-Verdict

**If real-time passes:** the prototype is still disposable. What carries forward is the tuning knowledge and the numbers, not the code.

**If real-time fails:** the turn-based test reuses the same corridor, the same attrition hypothesis, and the same fixed camera. Only the fight resolution changes.

Either way, the attrition hypothesis (§2) has been tested and that finding survives the verdict.
