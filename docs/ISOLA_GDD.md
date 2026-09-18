# ISOLA

**Game Design Document — Concept v0.1**

*Working title. See Naming, below.*

> The woman who raised you and forty other children is dying. There is a rumour of a cure somewhere past three settlements nobody can reach anymore. You have a sword, some map fragments, and no magic at all. You go.

| Engine | Perspective | Scope | Platform |
|---|---|---|---|
| Godot 4 + C# | Low-poly 3D, PS1 aesthetic | Solo, a few months | macOS (dev), PC target |

---

## 1. The Premise

The settlements used to be connected. They aren't anymore. Forest reclaimed the paths, a cave system collapsed, a bridge came down, the cable car rusted through, monsters moved into the gaps, and magic fog sits in the low ground where nobody sensible goes. Each village now survives alone, on what it can make itself, trading rumours with whoever still risks the walk.

You are nobody in particular. You were raised in an orphanage by a woman who took in children nobody else would, and you never left. She is sick with something no one local can name or treat. There is a rumour — only a rumour — of a cure somewhere beyond the third settlement.

You have map fragments, stories picked up along the way, and no magical ability whatsoever. Everything you do, you do with your hands, your feet, and a weapon.

**What the game is about:** not saving the world. Reconnecting a small piece of it, and finding out who you can convince to walk back with you.

---

## 2. Design Pillars

**1. Opening a road is permanent and visible.**
Every route you clear changes the world for good. Caravans start moving. Shops stock things they couldn't get before. People travel. The world knits together behind you and stays knitted.

**2. You are ordinary in a world that isn't.**
Magic exists. Wizards exist. Fog does things you don't understand. You have none of it. Your power is persistence and the people you convince to come with you.

**3. Recruitment is the heart, not settlement-building.**
Finding capable people in hard places and earning their trust is the fantasy. The village grows because people choose to move there once they finally can.

**4. Scope discipline is a design pillar, not a constraint.**
Every number in this document is a wall against feature creep. Systems get depth by being reused, not by being added to.

---

## 3. Core Loop

> Hear a rumour → Follow map fragments into uncharted territory → Fight and solve your way through → Reach the far settlement → **The route opens permanently** → Trade, travel, and recruits flow back along it → New rumours from the new settlement → Repeat

Between routes, the player returns home: check on the orphanage, talk to recruits who have moved in, restock, pick the next thread.

---

## 4. The World

**Four settlements. Three routes. That's the whole map.**

| | Content |
|---|---|
| **Home** | The orphanage settlement. Starting point. Where recruits move to and where the sick woman is. |
| **Settlement 2** | Opened by Route 1. |
| **Settlement 3** | Opened by Route 2. |
| **Settlement 4** | Opened by Route 3. Nearest point to the rumoured cure. |

### Route obstacles (one dominant obstacle per route, others as set dressing)

- Overgrown forest — no path, navigation by landmark
- Collapsed cave system
- Broken bridge
- Dead cable car
- Monsters occupying the gaps
- Magic fog — **a wall, not a mechanic.** Impassable until a route, tool, or recruit changes that. Never something the player fights directly.

### Route-opening state

Each route is binary: `Closed` → `Open`. No partial states, no maintenance, no re-closing. Once open:

- A caravan NPC walks the route on a loop
- The connected settlement's shop gains ~3 new items
- Fast travel becomes available (see Recruit 3)
- One or more recruits may relocate to Home

---

## 5. Trade — Deliberately Shallow

Trade is **flavour that signals consequence**, not an economy.

**In scope:** new shop items appear after a route opens; a caravan NPC visibly walks the road; a line or two of NPC dialogue about goods arriving.

**Explicitly cut:** supply and demand, price fluctuation, buying low and selling high, caravan management, logistics, cargo capacity, trade route income.

*Rationale: reads as a living economy for roughly 1% of the build cost. A real economy sim would consume the entire timeline.*

---

## 6. The Recruits

**Hard cap: five.** Each is convinced by a *single specific act*, not a quest chain. A recruitment moment should be a few minutes long, not a sub-story.

### The 3 / 2 split

Three recruits **change how the world works**. Two are **just people worth knowing**. The purely human ones are what stop the cast becoming a menu of unlocks and make the mechanical ones land.

### Confirmed

**Recruit 3 — The Carriage Driver (world-changing)**
He *is* the fast-travel system. Recruiting him unlocks travel along opened routes. As each further route opens, his company grows and the carriages improve — better, faster, more comfortable, more of them. His business visibly succeeding is the clearest single indicator of what the player has achieved.

### To design (slots)

| Slot | Type | Function | Convincing act |
|---|---|---|---|
| 1 | World-changing | e.g. healer — removes trips home to recover | TBD |
| 2 | Human | — | TBD |
| 3 | World-changing | Carriage driver — fast travel | TBD |
| 4 | World-changing | e.g. cartographer or smith | TBD |
| 5 | Human | — | TBD |

### Convincing-act variety (each used once)

- Survive a fight alongside them
- Recover a specific object
- Say the honest thing instead of the kind thing
- Prove a capability to them
- Offer them somewhere safer than where they are

*Rationale: "every character is convinced differently" is the right creative instinct and a scope bomb if uncapped. Five hand-built moments is achievable. Ten is not.*

---

## 7. The Clock

The orphanage mother is dying. This creates urgency — and a design trap.

**Decision: a stage clock, not a timer.** Her condition worsens at fixed story beats, never by elapsed real or in-game time.

Trigger beats: Route 1 opens → Route 2 opens → healer recruited → Route 3 opens → arrival at the rumoured cure.

*Rationale: a real timer punishes exploration and makes a sim/adventure stressful; a fake timer gets noticed within an hour when the deadline never lands. A stage clock feels like time passing while leaving the scenic route open. Players almost never catch it.*

### The orphanage

A house full of children gives the game:

- A cast that can be written with warmth rather than politics
- Natural quest-givers and sources of route rumours
- Emotional weight for every recruit — you're not growing a village, you're making sure those kids don't lose the only adult holding them together

---

## 8. The Ending

**The cure is a rumour, not a fact.** Design toward the honest ending: *you don't get there in time.* What remains is four connected settlements, five people who came back with you, and a house of children who now have a network instead of one woman.

You fail at the thing you set out to do and change the world sideways while doing it.

*Soften only if playtesting demands it. Do not soften pre-emptively.*

---

## 9. Combat — BIG UNKNOWN

**Status: undecided. Detailed design lives in the separate battle system document.**

Leaning away from turn-based, but not resolved. This is the largest single cost in the project and the one genuine unknown in the design.

### Resolution method: build both, don't argue about it

Two weeks. Build the same fight twice — once real-time with a dodge and a light attack, once turn-based on a small grid. Play both. Keep the one you want to play again.

| | Real-time | Turn-based |
|---|---|---|
| Cost | High — hit feel, animation timing, frame data, game feel iteration | Lower — no timing or feel problems to solve |
| Risk | Feel is the hardest thing in games to get right solo | Player has stated a lean away from it |

**Do this test before any other production work.** Two weeks spent here protects months.

### Constraints regardless of outcome

- Player uses **physical weapons only** — no player-facing magic system
- Enemy roster is drawn from route obstacles: monsters in the gaps, whatever the fog leaves behind
- Keep the roster small and reuse it across routes with variation

---

## 10. Puzzles — Environmental Only

Move the thing. Flood the channel. Open the gate from the other side. Restore power to the cable car. Fell the tree to bridge the gap.

**Explicitly cut:** bespoke logic puzzles, riddles, minigames, anything requiring puzzle-design craft. Each costs weeks and is a skill not yet in hand.

Puzzles exist to make a route feel *earned*, not to be the game.

---

## 11. Art Direction

**PS1 aesthetic, low-poly 3D.** Chosen over pixel art deliberately.

*Rationale: pixel art looks cheap but isn't — every character needs multi-directional walk cycles, and AI image tools cannot hold a character consistent across animation frames. Low-poly 3D lets a model be made or bought once and animated with reusable skeletal animation. 3D space is also the mental model that already works for this developer.*

### The PS1 look is a shader stack, not artistry

Build it once, and everything after looks intentional:

- Vertex snapping to a low-resolution grid (the wobble)
- Affine texture mapping — perspective-correct mapping off (the warp)
- Render at ~320×240, upscale
- Dithering
- Hard distance fog — **also hides the edges of the world, which is a scope saver**

### Characters

Avoid realistic human faces. Lip sync and facial animation can eat a month. Use simple features, masks, or stylised faces, and let body language, silhouette, colour and the dialogue box carry emotion. *A Short Hike* is the reference.

### Assets

Single consistent asset pack (Synty / Quaternius / Kenney) as the base. Consistency beats quality.

---

## 12. Scope Guardrails

### Hard numbers

- 4 settlements
- 3 routes
- 5 recruits
- 1 person searched for
- 1 ending

### Cut entirely

- Economy simulation
- Logic puzzles
- Player magic
- Branching narrative — **reveal-based characters only**, no choice-driven divergence
- Settlement building / construction systems
- Procedural generation
- Multiple playable characters
- Real-time failure timer

### The two-project problem

There are now two designs in play: RELICBORN and ISOLA. **The failure mode is not picking the wrong one — it is carrying both.** Before any code is written, decide out loud which is the project and which is the folder that stays closed for six months.

*Note: "find a person in the wild, bring them home, watch the settlement come alive" is a loop that has now been designed twice, independently. That pull is real and worth understanding before committing either way.*

---

## 13. Naming

`ISOLA` is a working title. Concerns:

- *Isola* is an Image Comics series
- *Isoland* and *Isolania* already exist on Steam
- Short, common words are hard to own and hurt discoverability

Alternatives pointing at roads rather than isolation: **The Long Way**, **Waymaking**, **Between**, **Passage**, **The Open Road** — or name it after the rumour being chased.

---

## 14. Open Questions

1. Who are the four remaining recruits — function, personality, convincing act?
2. What are the five human-scale reasons each one is stuck where they are?
3. What is the actual nature of the illness, and does anyone name it?
4. What is the rumour, in whose words, and how does it reach the player?
5. What do the first ten minutes look like?
6. Combat: real-time or turn-based — resolved by the two-week build test
7. What does a return trip *feel* like on foot versus by carriage, and is walking an opened route ever still worth doing?
8. How many children are in the orphanage, and which of them are named characters?
