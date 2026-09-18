# Dialogue tooling for a small reveal-based cast

Research for radman5/isolated#6 (part of #1). Researched 2026-09-18.

**Question:** For ISOLA, a Godot 4.7 GDScript game with Web export, which dialogue approach should we use: Nathan Hoad's Dialogue Manager, Dialogic 2, or a hand-rolled one? Needs: a handful of NPCs, reveal-only dialogue, a few flags, a simple box, controller and mouse input.

**Recommendation: hand-roll it.** Put the lines in a GDScript dictionary or a `.tres` Resource, show them in a `Label` or `RichTextLabel`, and keep flags in an autoload. If the amount of writing grows past what's comfortable to edit that way, use **Dialogue Manager 4** as the fallback. Don't use **Dialogic 2**.

---

## What the design actually needs

From `docs/ISOLA_GDD.md`:

- §12 "Scope Guardrails": "Branching narrative — **reveal-based characters only**, no choice-driven divergence". There is a hard cap of 5 recruits and 1 person searched for.
- §6 "The Recruits": each recruit is convinced by "a *single specific act*, not a quest chain", and a recruitment moment "should be a few minutes long".
- **Watch this one:** one of the §6 convincing acts is *"Say the honest thing instead of the kind thing"*. That is a dialogue choice, even if it only happens once. Whatever we pick has to present **a two-option prompt at least once**, operable with controller and mouse. It still isn't a branching narrative: the two options lead to a different line, and possibly a flag.

So the whole requirement is: roughly 5 to 10 speakers, lines shown in order per beat, a few boolean flags (`recruit_convinced`), and one or two binary prompts. That is well inside what a hand-rolled system can do.

## Comparison

| | Dialogue Manager 4 | Dialogic 2 | Hand-rolled |
|---|---|---|---|
| Latest release | v4.1.0, 2026-09-04 [1] | 2.0-alpha-20, 2026-07-21 [5] | n/a |
| Maturity | 4th major version; repo since 2022-01; 2 open issues; 82 contributors [2] | Still **alpha** (v2 alphas since before 2024-01); 178 open issues; README: "code may change at any Dialogic Release" [6][7] | Our code, our bugs |
| Godot 4.7 | README: "for Godot 4.6+". The repo's own `project.godot` targets `"4.7"` [3] | Requires 4.5+. alpha-20 "fixes things that broke in Godot 4.7" (#2773 → fixed by #2769). Open 4.7 bug #2777 (UI lingers about 0.5s at timeline end with custom styles) [5][8] | Engine-native, so no compatibility question |
| Licence | MIT (credit = include the licence text, e.g. in credits) [2][4] | MIT [6] | n/a |
| Footprint (`addons/` at the release tag, uncompressed) | about **0.7 MB, 189 files** (57 `.gd`, 9 `.cs`) [9] | about **7.6 MB, 962 files** (258 `.gd`, 75 `.png`) [9] | About 100 lines of GDScript and one scene |
| Autoloads added | `DialogueManager` | `Dialogic` plus subsystems | Whatever we write |
| Web export | No engine-level problems found. The two web reports (#927, #1046) were user errors: case-sensitive filenames, and `FileAccess.file_exists` where `ResourceLoader.exists` was needed [10] | Historical web bugs (v1 era, and #2384 on 4.3), all closed. alpha-20 strips PNGs from exports (#2717). #2605 (open) says asset dependencies of `.dtl`/`.dch` are hard to track for export [5][11] | Stays safe as long as data is a `.gd` or `.tres` (always exported). A raw `.txt`/`.json` needs the export "non-resource files" filter [13] |
| Controller + mouse | Example balloon: `next_action = &"ui_accept"`, `skip_action = &"ui_cancel"`, plus left-click handling; responses menu uses focus [12] | Built-in input settings (not checked in depth) | Use `ui_accept` and a `gui_input` click, the same as the DM balloon does |
| Localisation | Lines go through `tr()`; CSV or PO; `.dialogue` files auto-added to POT template generation; static `[ID:KEY]` line IDs; `##` translator notes; v4.1 adds a CSV exporter and static-ID keys [1][14] | Has translation support (not checked in depth) | Godot-native: store keys, run through `tr()`, CSV/PO translations; POT extraction from GDScript `tr()` calls [15] |
| Authoring | Script-like `.dialogue` files with an in-editor editor, syntax checking and a runtime state debugger [1][3] | Visual timeline editor, characters, portraits, backgrounds (visual-novel oriented) | Edit a dictionary in code |
| Upgrade risk | v3 to v4 had renames (titles became "cues") but the project documents the upgrade [1] | alpha-20 **broke custom subsystems and old save states**; "If you are late into production I recommend sticking with your godot and dialogic version" [5] | None |

## Per option

### Dialogue Manager 4 (nathanhoad/godot_dialogue_manager)

- Active: four patch/minor releases between 2026-08-15 and 2026-09-04, and the last push was 2026-09-09 [1][2].
- It is "stateless": the game stays the authority on state and dialogue reads and mutates your autoloads. That fits "a few flags" well [3].
- Distribution: v4 is on the **new Godot Asset Store** (store.godotengine.org, listing v4.1.0, 54 reviews). The legacy Asset Library only carries "Dialogue Manager 3" (v3.10.4, for Godot 4.4) [16][17].
- Downsides for us: it is a branching-dialogue system and most of what it offers (responses, conditions, mutations, cues, C# bridge, debugger) is capability we'd never use. It also adds about 0.7 MB to the `.pck`, because our Web preset uses `export_filter="all_resources"`.

### Dialogic 2 (dialogic-godot/dialogic)

- Still labelled alpha. The current `plugin.cfg` on `main` reads `2.0-Alpha-21 WIP (Godot 4.5+)` [7].
- The maintainer's own alpha-20 notes say they've "barely had any time for Dialogic". That release **breaks save states and custom subsystems** [5].
- It is about 10x Dialogue Manager's size, and built for visual-novel presentation (portraits, backgrounds, styles, timelines) that ISOLA's §11 PS1 look doesn't call for.
- It isn't on the legacy Asset Library for 4.x, nor findable on the new store under that name. Installing is from GitHub, plus the built-in auto-updater [6].
- **Rejected:** it is heavy, alpha, and ships breaking changes, all for features we won't use.

### Hand-rolled

A sketch of the full system, which we can grow if needed:

- `dialogue.gd` holds `const LINES := { "driver_intro": ["DRIVER_INTRO_1", "DRIVER_INTRO_2"], ... }`, storing translation keys rather than prose.
- `dialogue_box.tscn` is a `PanelContainer` holding a `RichTextLabel`, with a `visible_ratio` tween for the typewriter effect. It advances on `ui_accept` or a left click, and the Godot-native `tr()` handles localisation.
- For the one or two binary prompts: two `Button`s that grab focus (controller works through `ui_*` focus navigation, and the mouse works natively), and the result writes a flag.
- Flags go in a `Dictionary` on an existing or new autoload.
- Localisation comes for free from the engine: `tr(key)` with CSV or PO translations, and POT generation from GDScript [15].
- Web: keep the data in `.gd` or `.tres`, never raw `.txt`/`.json` loaded with `FileAccess`, which is the same trap as DM #1046. That way nothing depends on export filters or case-sensitive paths [10][13].

**When to switch to Dialogue Manager:** if the amount of text makes editing a dictionary painful (lots of lines per NPC, a writer who isn't editing code, or conditional lines creeping in). Moving the keys and lines into `.dialogue` files is a mechanical port, and DM's `tr()`/CSV path uses the same keys.

## Sources

1. Dialogue Manager releases v4.0.0 and v4.1.0 notes: https://github.com/nathanhoad/godot_dialogue_manager/releases (tags `v4.0.0` to `v4.1.0`)
2. Dialogue Manager repo metadata via GitHub API (licence MIT, created 2022-01-26, pushed 2026-09-09, 2 open issues): https://github.com/nathanhoad/godot_dialogue_manager
3. Dialogue Manager README ("for Godot 4.6+"; older-version table) and repo `project.godot` (`config/features=PackedStringArray("4.7", "C#")`): https://github.com/nathanhoad/godot_dialogue_manager/blob/main/README.md
4. Dialogue Manager FAQ, "How do I credit Dialogue Manager in my game?": https://github.com/nathanhoad/godot_dialogue_manager/blob/main/docs/FAQ.md
5. Dialogic 2.0-alpha-20 release notes: https://github.com/dialogic-godot/dialogic/releases/tag/2.0-alpha-20
6. Dialogic README ("requires at least Godot 4.5"; install via docs and auto-updater; alpha/beta API-change warning): https://github.com/dialogic-godot/dialogic/blob/main/README.md
7. Dialogic `addons/dialogic/plugin.cfg` on `main`; repo metadata via GitHub API (MIT, 178 open issues): https://github.com/dialogic-godot/dialogic
8. Dialogic issues #2773 "Dialogic 2 is broken in Godot 4.7" (closed, fixed by #2769) and #2777 "Bug in Godot 4.7 on timeline end" (open): https://github.com/dialogic-godot/dialogic/issues/2773, https://github.com/dialogic-godot/dialogic/issues/2777
9. Footprint: sum of blob sizes under `addons/<name>/` from the GitHub git-trees API at tags `v4.1.0` and `2.0-alpha-20`. These are uncompressed repo sizes, not measured `.pck` deltas.
10. Dialogue Manager issues #927 and #1046 (web export portraits; root causes were filename case and `FileAccess` vs `ResourceLoader`): https://github.com/nathanhoad/godot_dialogue_manager/issues/927, https://github.com/nathanhoad/godot_dialogue_manager/issues/1046
11. Dialogic issues #2384 (4.3 web export, closed) and #2605 (export asset dependencies, open): https://github.com/dialogic-godot/dialogic/issues/2384, https://github.com/dialogic-godot/dialogic/issues/2605
12. Dialogue Manager `addons/dialogue_manager/example_balloon/example_balloon.gd` at `v4.1.0`
13. Godot docs, Exporting projects ("allows non-resource files such as .txt, .json and .csv to be exported"): https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html
14. Dialogue Manager docs, Translations: https://github.com/nathanhoad/godot_dialogue_manager/blob/main/docs/Translations.md
15. Godot docs, Internationalizing games and Localization using gettext (POT generation, extracting strings from GDScript): https://docs.godotengine.org/en/stable/tutorials/i18n/internationalizing_games.html
16. Godot Asset Store listing: https://store.godotengine.org/asset/nathanhoad/dialogue-manager/
17. Legacy Asset Library API, assets 3654 "Dialogue Manager 3" and 1432 "Dialogue Manager 2": https://godotengine.org/asset-library/asset/3654

**Not verified:** actual `.pck` size delta for each addon in a Web build; Dialogic's input and localisation internals (not needed once it was rejected on maturity and size).
