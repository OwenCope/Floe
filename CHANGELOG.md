# Changelog

All notable changes to Floe are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

The `release.yml` workflow reads the section matching the release tag
(`## [tag]`) and uses it as the release notes for both the GitHub Release
and the Sparkle appcast, unless overridden with the `release_notes` input.

## [Unreleased]

**macOS 26 and later · No release yet: build from source**

### Added

- One hotkey opens a search over applications, extension commands, script commands, quicklinks and System Settings panes, ranked by how often and how recently each is used. Matched letters are drawn in a stronger weight.
- Raycast extensions run unmodified on a Bun runtime inside the app, including the ones Raycast has already installed. Forms, preferences, arguments, toasts, confirmation dialogs, background and interval commands, and menu bar commands work. Passwords go in the Keychain.
- An Extension Store page browses, installs and updates extensions.
- Menu bar item search lists the menu bar's items and opens their menus from the keyboard.
- Clipboard history, snippets with text expansion, quicklinks with fallback searches, emoji and symbols, file search, calendar events, and a calculator with unit conversion.
- System commands (sleep, lock, empty Trash) and toggles for Wi-Fi, mute and keeping the Mac awake.
- An Actions menu (⌘K) on applications and files: quit, force quit, show in Finder, open with, copy, move to Trash.
- Scopes in the root search: `files invoice`, `clipboard meeting`, `menu wifi`, `tabs invoice`.
- Optional search sources, off until turned on in Privacy: files and open browser tabs (Safari, Dia, Helium) add up to three rows to an ordinary search.
- Preferred apps: a terminal, an editor and a notes app. Files, folders and the Finder selection open in the ones already in use, and `note` followed by text goes to Apple Notes, Antinote, or any app with a URL scheme.
- Ask AI: `ask` and a question, or the Ask AI row under any search, shows one answer in the launcher. No history is kept.
- AI sources: the `claude` or `codex` tool, Apple Intelligence on the Mac, or an OpenAI-compatible API (OpenAI, OpenRouter, Ollama, LM Studio). A switch keeps all AI on the Mac, and one extension can be pinned to a source of its own.
- Thaw 3's actions in the search when Thaw is installed, and a switch that makes the launcher follow Thaw's menu bar appearance.
- Appearance settings: Thaw 3's glass styles, a tint, a border, a shadow, and a compact layout that is only the search bar until you type.
- A Privacy page with the permissions and their reasons, the search sources, and everything Floe contacts over the network.
- `Floe --pick` lends the search panel to any script: it reads lines on standard input and prints the one chosen.
- Aliases and hotkeys for applications, commands and the menu bar search. Favorites stay at the top.
- What’s New, in the About page’s menu, shows these release notes in the app.
- Detailed logging, off by default, writes a log to `~/Library/Logs/Floe` for troubleshooting. What is typed or asked is never logged.

### Changed

- Menu bar commands are added to the menu bar by hand, from the search or from Settings. None starts on its own at launch.
- Browser sign-in (OAuth) for extensions is parked. Extensions use a token preference until it has been tested against real providers.
- Settings opens in a process of its own, which ends when the window closes and gives its memory back. It has its own Dock icon while it is open.

### Fixed

- The settings window's toolbar no longer lets scrolled content show through. ([#3](https://github.com/thaw-app/Floe/issues/3))
- ⌘A, ⌘C, ⌘V, ⌘W and ⌘Q work in the search field and in Settings.
- Return in the file search opens the file instead of revealing it in Finder.
- The settings gear keeps its size in every bottom bar.
- The system's password and one-time-code AutoFill no longer attaches to the search field.

### Development

- `Sources/Floe` and its tests are sorted into folders by area.
- The root search is built from providers, scopes and sources that each answer a query on their own.
- swift-subprocess, swift-algorithms, swift-async-algorithms, swift-markdown and swift-argument-parser replace hand-written code.
- `Floe --bench-search` times the catalog scan and each keystroke; `--bench-settings` times each settings page.
- `Floe --settings` is the settings process. The launcher starts it and the two keep in step over distributed notifications, all listed in `ProcessLink.swift`.
- A watchdog writes a report to `~/Library/Logs/Floe` when the main thread stops answering.
