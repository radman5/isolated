# Shipping a free Godot 4.7 game on itch.io

Research for radman5/isolated#7 (part of #1). Sources checked 2026-09-18.

## TL;DR

- **Web:** keep the current single-threaded export. It already works on itch with no special options, including Safari/iOS. Don't turn on itch's SharedArrayBuffer checkbox.
- **macOS:** ship the Godot default (ad-hoc signed, not notarized) as a `.zip`. Players on macOS 15+ need one trip to *System Settings > Privacy & Security > Open Anyway*. Notarization costs **$99/yr** (Apple Developer Program). It isn't worth paying for a free game until players complain.
- **Windows:** ship unsigned. Players get "Windows protected your PC" and click *More info > Run anyway*. Signing no longer removes the warning (EV lost its bypass in 2024), so paying for it buys very little for a free game.
- **Upload:** use a `butler push` job in GitHub Actions on version tags, one channel per platform. It's about 10 lines of YAML plus one secret. The first HTML5 upload still has to be marked "played in browser" once, by hand, on the itch dashboard.

## What the repo has today

`export_presets.cfg` has a single `Web` preset:

- `variant/thread_support=false`, so **the Web preset does not use threads**. `variant/extensions_support=false` as well.
- `html/canvas_resize_policy=2` (adaptive), so the game fills whatever frame itch gives it.
- `vram_texture_compression/for_mobile=false`. Mobile browsers that lack S3TC/BPTC fall back to uncompressed textures. That's fine for now.
- Renderer is `gl_compatibility` (project.godot). Web requires it anyway.

`.github/workflows/web.yml` runs on each push to `main`. It downloads Godot 4.7.2 plus export templates (cached), keeps only the `web_*` templates, runs `check.gd`, exports `Web` to `build/web/`, and deploys to GitHub Pages. Nothing goes to itch. There are no Windows, macOS or Linux presets.

## Web

**Threads vs single-threaded.** Godot's web export docs (4.7) call the single-threaded export "the preferred and now default way to export your games on the Web". They describe it as "more compatible overall with stores like itch.io", and say it "works very well on macOS and iOS too, where it always had compatibility issues with multiple threads exports". What you give up: no threads, and audio uses the Web Audio **Sample** playback mode, which has no AudioEffects, no reverb/doppler and no procedural audio. Positional audio can also misbehave. You can switch a player to **Stream** to get the full audio feature set, at the cost of extra latency when threads are off. [Godot: Exporting for the Web](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)

**itch's SharedArrayBuffer option.** It's a checkbox under *Embed Options > Frame Options*. When it's on, itch serves the game from `html.itch.zone` with `COOP: same-origin`, `COEP: require-corp` and `CORP: cross-origin`, and the game page gets COEP `credentialless`. The costs:

- Safari and iOS aren't supported.
- Third-party embeds break.
- Moving to a new domain orphans existing `localStorage` saves. Godot's `user://` on web is IndexedDB, which is also origin-scoped, so the same problem applies.

[itch: Experimental SharedArrayBuffer support](https://itch.io/t/2025776/experimental-sharedarraybuffer-support) (admin post, 2022, updated since). Threads only make sense if profiling shows a need, and ISOLA doesn't need them now. **Leave it off.**

**Limits on the HTML5 zip** ([itch: HTML5 games](https://itch.io/docs/creators/html5)):
- `index.html` at the root. ZIP format only. Filenames are case-sensitive UTF-8.
- At most 1,000 files after extraction, 500 MB total, 200 MB per file, and 240 characters per path.
- A Godot export is about 5 files (`index.html/.js/.wasm/.pck`, the audio worklet and icons), so these limits won't come up.
- itch does **not** compress on the fly (Godot docs: "Hosts that don't provide on-the-fly compression: itch.io"). GitHub Pages gzips the `.wasm`, which is roughly 4x smaller over the wire. On itch the full uncompressed size downloads. If load time becomes a problem, the fix is a size-optimised custom template ([Godot: optimizing for size](https://docs.godotengine.org/en/stable/engine_details/development/compiling/optimizing_for_size.html)).

**Mobile browsers.** Godot says web on mobile runs "significantly" worse than native builds and recommends feature tags to lower settings. Safari's WebGL 2 has known issues. On itch, the **Mobile friendly** option forces "click to launch in fullscreen" on phones. Also turn on itch's fullscreen button, and set a viewport size for embed-in-page mode. Only the single-threaded build runs on iOS at all.

## macOS

**Godot export options** ([Godot: Exporting for macOS](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_macos.html)):
- The output is a Universal 2 `.app` (x86_64 + arm64), packed as a `.zip`. DMG export only works from macOS.
- Without a Developer ID, choose *Codesign: Built-in (ad-hoc only)* and *Notarization: Disabled*. This is the default, and it runs on the Linux CI runner.
- With a Developer ID, choose *Xcode codesign* + *Xcode notarytool* on a Mac, or *rcodesign* on Linux/Windows. rcodesign needs a PKCS#12 cert and an App Store Connect API key. Either route requires the `Debugging` entitlement to be off, and you staple the ticket afterwards.
- Export `.zip`, not a raw `.app`, from Windows: `.app` bundles exported from Windows lose the executable bit.

**Cost.** Developer ID certificates and notarization require the paid Apple Developer Program at **$99 per membership year** ([Apple: enroll](https://developer.apple.com/programs/enroll/), [membership comparison](https://developer.apple.com/support/compare-memberships/)).

**What unsigned/ad-hoc costs players:**
- An ad-hoc signed app that isn't notarized is blocked on first launch.
- Since **macOS Sequoia (15)**, Control-click > Open no longer overrides Gatekeeper. Players have to open *System Settings > Privacy & Security*, click **Open Anyway**, then **Open** again ([Apple developer news, 6 Aug 2024](https://developer.apple.com/news/?id=saqachfa); [Apple Support 102445](https://support.apple.com/en-us/102445)).
- Godot's own [Running Godot apps on macOS](https://docs.godotengine.org/en/stable/tutorials/export/running_on_macos.html) page still lists Control-click. That's out of date for 15+.
- If signing were missing entirely (only linker-signed), players would need `xattr -dr com.apple.quarantine`. The ad-hoc default avoids that.
- Godot also warns that apps run from Downloads or while still quarantined get *path randomization*. Tell players to move the app to `/Applications` first.

For the itch page: put three lines on the macOS download: "Unzip, move to Applications, open once, then System Settings > Privacy & Security > Open Anyway."

## Windows

**What players see** ([Microsoft Learn: SmartScreen reputation](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation), updated 2026-08):
- Unsigned or self-signed: "Windows protected your PC", then *Run anyway*.
- Signed with a valid OV/EV cert: still flagged as "unrecognized" until reputation builds, but it shows the publisher name.
- "EV certificates no longer bypass SmartScreen". Reputation builds over "several weeks and hundreds of clean installs".
- Unsigned files start from zero reputation on every new build.
- **Smart App Control** on Windows 11 blocks unsigned files that lack reputation. Microsoft enables it only on clean installs, and many users turn it off. It's the one case where an unsigned build won't run at all.

**Signing options if it ever matters:**
- Microsoft's Artifact Signing (formerly Trusted Signing) costs from $9.99/month, needs identity validation, and works in GitHub Actions.
- Godot can sign on export using `signtool` or, on Linux, `osslsigncode`. Credentials can come from the `GODOT_WINDOWS_CODESIGN_*` env vars ([Godot: Exporting for Windows](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html#code-signing)).

**Does it matter for a free game?** Not much. itch players are used to the SmartScreen prompt, and signing doesn't remove it for a new, low-download title anyway. It only gets a publisher name onto the prompt. Ship unsigned and put a one-line note on the Windows download.

## Distribution: butler vs manual

**butler** ([docs](https://itch.io/docs/butler/)):
- Syntax is `butler push <dir|zip> user/game:channel`.
- Channel names are auto-tagged: `win`/`windows`, `linux` and `mac`/`osx`. A channel can carry more than one tag.
- `--userversion` (or `--userversion-file`) sets the version shown to players. `--if-changed` skips uploads that haven't changed.
- Uploads are delta-patched, and the itch app updates players incrementally.
- An HTML5 channel still has to be marked "playable in browser" once on the edit page ([pushing](https://itch.io/docs/butler/pushing.html)).

**CI:** set `BUTLER_API_KEY` as a repo secret ([login](https://itch.io/docs/butler/login.html)). Download butler from the fixed URL `https://broth.itch.zone/butler/linux-amd64/LATEST/archive/default` ([installing](https://itch.io/docs/butler/installing.html)). If the key ever shows up in a public log, revoke it.

**Manual upload** through the dashboard works, but:
- every platform is a separate drag-drop,
- there's no patching,
- there's no version string,
- you have to keep re-checking the web upload's "played in browser" flag.

For 3–4 platforms per release, butler wins after the first release.

## Recommended minimal pipeline

1. Add three export presets next to `Web`: **Windows Desktop**, **macOS** (Codesign *Built-in (ad-hoc only)*, Notarization *Disabled*, a bundle ID like `com.radman5.isola`, export as `.zip`) and optionally **Linux**. Leave `Web` alone (`thread_support=false`).
2. Leave `web.yml` / GitHub Pages as the per-push dev build.
3. Add a `release.yml` that runs on `v*` tags:
   - Reuse the same Godot download/cache steps, but keep the `windows_*`, `macos.zip` and `linux_*` templates as well as `web_*`.
   - Export each preset.
   - `butler push` to `radman5/<game>:html5`, `:windows`, `:mac` and `:linux`, using `--userversion ${GITHUB_REF_NAME#v}`.
   - The only secret is `BUTLER_API_KEY`.
4. One-time setup on the itch dashboard:
   - Kind of project: HTML.
   - Tick "played in browser" on the `html5` upload.
   - Turn on **Mobile friendly** and the fullscreen button, and set the viewport size.
   - Leave SharedArrayBuffer **off**.
   - Add the Gatekeeper and SmartScreen instructions to the download notes.

Skipped for now: Apple notarization ($99/yr) and Windows signing ($9.99/mo+). Add notarization when Mac players report friction or the game goes paid. Signing a Windows exe barely helps before the game has reputation.
