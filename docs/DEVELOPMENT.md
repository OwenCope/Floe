# Developing Floe


Prototype macOS launcher that runs unmodified Raycast extensions: a SwiftUI panel plus a Bun process per running command.

Contribution requirements, review expectations, and security reporting are in the shared [Thaw/Floe policies](https://github.com/thaw-app/.github).

Requires macOS 26 or later, Bun, and Xcode 27 for the vendored ThawUI Swift 6.4 manifest. Extensions run under your user account without sandboxing; only install extensions you trust.

## Run

    cd runtime && bun install && cd ..
    open Floe.xcodeproj        # ⌘R in Xcode

or install it as `/Applications/Floe.app` with `./scripts/devrun.sh` (`--debug`, `--no-launch`).

⌃⌥Space toggles the panel. ↑↓ select, ↵ runs the primary action, ⌘K opens the action menu, Esc goes back.

`Floe.xcodeproj` is generated from `project.yml` by XcodeGen; edit the spec and run `xcodegen generate`
rather than changing project settings in Xcode. `Package.swift` stays for `swift run` and the CLI checks below.

The Run scheme has two disabled environment variables: `FLOE_AUTORUN` opens a command at launch,
`FLOE_DEBUG` logs focus changes.

## Settings

⌘, in the panel, "Floe Settings" in search, or the menu bar icon. General has the launcher hotkey, launch at login
and whether to include Raycast's installed extensions. Each extension has an on/off switch, its preferences, and
per-command aliases and hotkeys. Password preferences are kept in the Keychain; with the default ad hoc signing,
macOS asks again after each rebuild, so set a signing identity in `project.yml` if that gets old.

Commands with required preferences or arguments ask for them in the panel before they run.

## Layout

- `Sources/Floe`: the app: panel, hotkey, app index, and a renderer for the JSON tree the host sends.
- `runtime/host.ts`: bundles a command, renders it with a custom React reconciler, speaks NDJSON on stdio.
- `runtime/api/index.ts`: the `@raycast/api` stand-in.
- `extensions/`: one folder per extension (`hello` is a sample, `diagnostics` fails on purpose to exercise the error screen).

- `Sources/Floe/Thaw`: code ported from Thaw: hotkeys (key codes, Carbon registry, recorder), the HUD, the About page,
  onboarding and permissions, settings search, the Sparkle updater with its consent sheet, and the App Intents that
  Shortcuts and Spotlight use (`FloeIntents.swift`).
- `Sources/Floe/DroppyCode`: code ported from Droppy Code. Each file keeps Droppy Code's copyright and credit line
  and says what Floe changed; `docs/licenses` holds its license and third-party notices.
  - `LoginEnvironment.swift` reads the login shell's environment, which extensions start with, and `Shell.swift` runs
    a tool with a timeout.
  - `AI.ask` is answered by one-shot `claude` or `codex` runs (`TextGeneration.swift`) or by a streamed request to an
    OpenAI-compatible API (`ChatCompletionStream.swift`). Settings › General › AI picks between them; the choice and
    the request an extension makes are in `HostRequest.swift`.
- `CREDITS.md` and `Sources/Floe/Credits.swift` are written by `scripts/generate-credits.py`; run it after changing a dependency.
- `Vendor/ThawUI`: design system copied from thaw-app/Thaw (commit in `Vendor/ThawUI/UPSTREAM`).
- `Vendor/ThawConcurrency`: Thaw's timeout and one-shot continuation helpers, copied the same way.

## License

AGPL-3.0. ThawUI and the other code from Thaw stay under GPL-3.0, which the AGPL allows combining with. The code from Droppy Code is AGPL-3.0 with the attribution terms in `docs/licenses/DroppyCode-LICENSE`. Extensions under `extensions/` keep their own licenses.

## Adding an extension

Extensions live in `~/Library/Application Support/Floe/Extensions`; Raycast's installed ones are picked up
from `~/.config/raycast/extensions`. To add a store extension, copy its folder from
https://github.com/raycast/extensions there and run `bun install --ignore-scripts` inside it (a full install:
some extensions import dev dependencies at runtime). Per-extension storage, preferences and cached bundles go to
`…/Floe/Data/<name>`.

The app is self-contained: the build copies `runtime/` and Bun into `Contents/Resources/runtime`. Set
`FLOE_ROOT` to a checkout (or use `swift run`) to work against the checkout's runtime and its `extensions/`
samples instead, including `diagnostics`, which fails on purpose to exercise the error screen.

## Keys

| Key | Where | Does |
|---|---|---|
| ↑↓, Page Up/Down, Home/End | lists, action menu | move |
| ↵ / ⌘↵ | lists | first / second action |
| ⌘K | lists | action menu; type to search it, → and ← in and out of submenus |
| ⌘⇧F | root | add or remove a favorite |
| ↵ | menu bar search | open the item's menu (needs Accessibility) |
| Esc, ⌘[ | commands | back |
| ⌘, | anywhere | settings |
| ↵, ⌘⇧C | error screen | try again, copy details |

## Tests

    swift test                                   # Swift Testing suites in Tests/FloeTests
    bun --config=runtime/bunfig.toml test ./runtime   # runtime suites in runtime/tests
    ./scripts/coverage.sh --summary              # both, with coverage per measured file

The Swift tests import the app's module directly and never launch it. Logic lives in files that can run
in a test (`Ranking`, `Manifest`, `ViewState`, `MarkdownParser`, `Shortcuts`, `PropFormat`, `Preferences`,
`MenuBarLogic`, `Settings`, `Session`, `CommandLookup`, `ThawHUDPlacement`, `UpdateLogic`, the onboarding sequencer,
permission state and the settings search index); views, the process, the Keychain and Accessibility code are excluded
from coverage in `sonar-project.properties`, which also states the rule. New decision logic belongs in a
measured file with a suite beside it.

## Code style

Floe uses [SwiftLint](https://github.com/realm/SwiftLint) and [SwiftFormat](https://github.com/nicklockwood/SwiftFormat)
with Thaw's rules, in `.swiftlint.yml` and `.swiftformat`. CI runs SwiftLint in strict mode. Before a commit:

    swiftformat .
    swiftlint lint --strict

Tests and `Vendor/` are not linted. The size and complexity limits apply to new code only; what predates them is
listed in `.swiftlint.baseline`.

## Releases and updates

Floe updates itself with [Sparkle](https://sparkle-project.org), the same way Thaw does. The pieces:

- `SUFeedURL` and `SUPublicEDKey` in `project.yml` (the Info.plist source). The feed is
  `https://thaw-app.github.io/Floe/appcast.xml`, served from this repository's `gh-pages` branch.
- `Sources/Floe/Thaw/Updates.swift` wraps Sparkle. While `SUPublicEDKey` is empty the app builds no
  updater: "Check for Updates…" is absent from the status menu, the About page has no updates card, and
  General has no "Automatically check for updates" switch. The rules are in `UpdateLogic.swift`.
- With a key, the first time Settings opens a sheet asks whether to check automatically. Sparkle does
  nothing before that answer except a check the user starts.
- `.github/workflows/release.yml` builds an existing tag, notarizes it, zips the app, signs an appcast
  item for it with the `SPARKLE_ED25519_PRIVATE_KEY` secret (`prod` environment), attaches the ZIP to the
  GitHub Release beside the DMG, and pushes `appcast.xml` to `gh-pages` after the release is published.
  A tag whose Info.plist has no key skips the Sparkle steps and ships the DMG alone.

Switching updates on, once:

1. `swift build`, then `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account floe`. The private key
   stays in your login Keychain; the command prints the public key.
2. Put the public key in `SUPublicEDKey` in `project.yml` and run `xcodegen generate`.
3. `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account floe -x ~/floe-sparkle.key`, then
   `./scripts/set-secrets.sh` and answer `@~/floe-sparkle.key` for `SPARKLE_ED25519_PRIVATE_KEY`. Delete the file.
4. After the first release has pushed `appcast.xml`, turn on GitHub Pages for thaw-app/Floe: Settings,
   Pages, deploy from the `gh-pages` branch, folder `/`.

Each release:

1. Raise `CFBundleShortVersionString` and `CFBundleVersion` in `project.yml` (and `sonar.projectVersion`),
   run `xcodegen generate`, commit. Sparkle orders builds by `CFBundleVersion`, a whole number that must go
   up every time; the workflow stops if it does not.
2. Tag the commit with the version (`0.2.0`, or `0.2.0-beta.1` for the beta channel) and push the tag.
3. `./scripts/release.sh` picks the tag and dispatches the workflow. Try a dry run first: it builds and
   reports the appcast diff and publishes nothing.

Pushing the appcast needs "Publish release" checked, because the appcast links to the release's ZIP. The
Sparkle tools version in `release.yml` (`sparkle-version` and its checksum) must match `Package.resolved`.

To rehearse an update with a Debug build, serve an appcast locally and point the build at it:
`defaults write com.thaw.floe FloeDebugFeedURL http://localhost:8000/appcast.xml`. Release builds
ignore that key, and without it a Debug build refuses to check.

## Checks

    bun runtime/smoke.ts extensions/hello planets          # host only
    .build/debug/Floe --selftest hacker-news frontpage  # Swift ↔ Bun round trip
    .build/debug/Floe --search cal                      # ranked root results
    .build/debug/Floe --icon-check                      # every extension's icon, rendered off screen
    .build/debug/Floe --menubar [query]                 # menu bar items Floe can open
    .build/debug/Floe --panel-snapshot /tmp/p           # root and menu bar views, drawn off screen
    FLOE_BENCH_DUMP=/tmp/s .build/debug/Floe --bench-settings  # settings page timings and snapshots
    bun runtime/survey.ts ~/.config/raycast/extensions      # compatibility across many extensions
    FLOE_AUTORUN=hacker-news/frontpage swift run        # open straight into a command

## Menu bar item search

"Search Menu Bar Items" (root search, or its hotkey in Settings › General) uses the look of Thaw 3's
inspector search panel, the one Thaw opens from its menu bar icon. Thaw finds and opens items through MenuBarModel and its own runtime; Floe reads
each app's extras menu bar through the Accessibility API and opens an item by pressing it, so it needs
only the Accessibility permission. It shows no previews of the items, so it never asks for Screen
Recording; items Thaw keeps hidden may not open from here.
