# Floe

<p align="center">
  <b>The open source launcher for macOS.</b>
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="docs/DEVELOPMENT.md">Building</a> ·
  <a href="#acknowledgments">Acknowledgments</a>
</p>

<p align="center">
  <img alt="Floe's launcher with suggestions and commands under the search field" src="docs/images/floe.jpg" width="800" />
</p>

## Features

- Open apps and commands from one hotkey, ranked by how often and how recently you use them
- Run Raycast extensions as they are, including the ones already installed in Raycast, on a Bun runtime bundled with the app
- Search the menu bar's items and open their menus from the keyboard, with previews of the items in view, recents, and your own names for items
- Fill in extension forms, preferences, and arguments, with passwords kept in the Keychain
- Give apps, commands, and the menu bar search their own aliases and hotkeys, and pin favorites
- See what went wrong when a command throws, crashes, or stops responding, then try it again
- Built on ThawUI, the design system from [Thaw](https://github.com/thaw-app/Thaw), for macOS 26 and later

Floe is early: there are no releases yet, so build it from source. Extensions that sign in with OAuth, menu bar commands, and background commands don't run yet.

## Acknowledgments

- [Thaw](https://github.com/thaw-app/Thaw): the ThawUI design system, hotkey code and the About and settings sidebar designs. GPL-3.0.
- [CompactSlider](https://github.com/buh/CompactSlider), used by ThawUI. MIT.
- [Bun](https://bun.sh), which runs extensions. MIT.
- [React](https://react.dev) and react-reconciler, which render them. MIT.
- [Raycast extensions](https://github.com/raycast/extensions), whose API Floe implements. Each extension keeps its own license. Raycast is a trademark of Raycast Technologies Inc.; Floe is not affiliated with Raycast.
