# Contributing to Floe

All contributions welcome. Propose changes to this document in a pull request.

Floe is early: there are no releases yet and the app is built from source. The [TODO list][todo] in the README shows what is missing.

## Code of Conduct

Read and follow our [Code of Conduct][coc].

## Ways to contribute

Bug reports, code, docs, and reports about Raycast extensions that do not work in Floe. Looking for a concrete task? Pick an item from the [TODO list][todo] and open an issue to say you are working on it.

Questions are welcome on the Thaw community's [Discord][discord], where Floe is discussed too. GitHub issues and pull requests remain the record for bugs and decisions.

### AI-assisted contributions

AI-assisted work is welcome when the result is high quality and follows this guide.

- You are responsible for what you submit. By opening a pull request you state that you have the right to contribute the change under GPL-3.0, including any AI-generated portions.
- Prefer tools whose terms allow contributing output to GPL-licensed projects. Do not feed clearly proprietary or third-party-restricted code into an assistant and commit the result as if it were yours.
- You must understand and be able to explain the change in review.

Low-quality PRs are closed. A PR is closed when it shows observable process or quality failures: unreviewed generated content pasted without human cleanup, failing CI left unaddressed, ignored maintainer feedback, an unchecked PR template, or drive-by refactors with no issue. Using AI does not lower the bar. If we request changes and there is no meaningful follow-up within a reasonable window, the PR is closed; open a new one later that addresses the feedback.

## Before you start

You need a GitHub account and a fork:

1. Fork the repository on GitHub
2. Clone your fork locally

   ```bash
   git clone https://github.com/YOUR_USERNAME/Floe.git
   cd Floe
   ```

3. Create a branch for your changes

   ```bash
   git checkout -b your-branch-name
   ```

4. When ready, open a pull request against `thaw-app/Floe:main`

## Non-technical contributions

### Reporting bugs

Before submitting a bug report, search the [issue tracker][it] and check the [TODO list][todo]; what is listed there is not supported yet. The bug report template asks for the information we need to reproduce the issue; reports without enough detail may be closed until more is provided.

Include the Floe version and commit from the About page in settings. If an extension is involved, name the extension and the command, and say whether it came from Raycast's folder or Floe's. If Floe showed its error screen, press Copy Details (⌘⇧C) and paste the result.

### Documentation improvements

A pull request to fix anything unclear, incomplete, or out of date in the project's docs is welcome.

## Technical contributions

### Prerequisites

- macOS 26 or later
- A recent Xcode. `Vendor/ThawUI` declares `swift-tools-version: 6.4`, and CI builds with Xcode 27.
- [Bun](https://bun.sh), which runs extensions and is copied into the app at build time
- [XcodeGen](https://github.com/yonaskolb/XcodeGen), only if you change `project.yml`

### Getting started

```bash
cd runtime && bun install && cd ..
open Floe.xcodeproj
# Or build, install, and launch /Applications/Floe.app:
./scripts/devrun.sh
```

[docs/DEVELOPMENT.md][dev] has the full build notes, the layout of the repository, and the list of command-line checks.

`Floe.xcodeproj` is generated from `project.yml` by XcodeGen. Edit the spec and run `xcodegen generate` rather than changing project settings in Xcode, then commit both.

`Vendor/ThawUI` is a copy of Thaw's design system (the commit is in `Vendor/ThawUI/UPSTREAM`). Changes to it belong in [Thaw](https://github.com/thaw-app/Thaw) first.

### Build a shareable DMG without a release

Maintainers can run [Build DMG](workflows/build-dmg.yml) to get a signed, notarized DMG of any branch, tag, or commit. It uploads only the DMG, keeps it for three days, and creates no tag or GitHub release. On a pull request from a branch in this repository, a maintainer can comment `.build` to start it for that branch.

The signing job waits for approval on the `prod` environment. Only approve reviewed refs: the build scripts of that ref run in the signing job.

```bash
gh workflow run build-dmg.yml -R thaw-app/Floe --ref YOUR_BRANCH
```

### SCA / SAST expectations

Floe treats automated security and quality findings as part of the merge bar. The full dependency SCA policy (thresholds + suppressions) lives in [SECURITY.md](SECURITY.md) (§ Dependency SCA policy).

| Signal | Where | Expectation |
| --- | --- | --- |
| **Dependency SCA** (`dependency-sca`) | OSV-Scanner on every PR / `main` push | Fix or suppress (via `.github/osv-scanner.toml` + reason) before merge |
| **Dependabot** | Dependency / Actions update PRs | Review and merge promptly; those PRs must still pass `dependency-sca` |
| **SonarQube Cloud** | [Project dashboard](https://sonarcloud.io/summary/overall?id=thaw-app_Floe) | Fix new issues unless a maintainer marks won't-fix |
| **CodeQL** | Security analysis workflow on `main` (TypeScript and workflows) | Address high/critical findings; discuss false positives with maintainers |

Do not merge with a failing check. If a finding is a false positive or not exploitable in Floe, add a documented suppression in `.github/osv-scanner.toml` (see SECURITY.md) rather than bypassing the check.

### Tests

There is no unit test target yet. CI builds the app and runs two headless checks; run them before you open a pull request:

```bash
bun runtime/smoke.ts extensions/hello planets
swift build && .build/debug/Floe --selftest hello planets
```

The second prints `SELFTEST OK` when the Swift to Bun round trip works. More checks are listed in [docs/DEVELOPMENT.md][dev].

### Project conventions

- Branch & base: pull requests target `main`.
- PR size: aim for ≤500 lines / ≤20 files per PR. If you expect to exceed this, say why in the Summary and link the design/issue.
- Templates & issues: bugfix and feature PRs should reference a GitHub issue (`Closes: #123`).
- Commit / PR titles: Conventional Commits, e.g. `fix(runtime): …`, `feat(settings): …`. CI checks the PR title via PR Metadata.
- Sensitive areas: expect deeper review when touching how extensions are loaded and run, preferences and Keychain storage, or permissions.

### Pull requests

Open a pull request via the [Floe pull requests page][pr] and fill in the [template][prt]. It will guide you through the required information and checklist.

## Project docs (orientation)

- [Governance][gov]: roles and decision-making
- [Development][dev]: building, layout, checks
- [Security policy][sec]: reporting and security requirements

## Resources

- [How to Contribute to Open Source](https://opensource.guide/how-to-contribute/)
- [Using Issues](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues)
- [Using Pull Requests](https://help.github.com/articles/about-pull-requests/)
- [Conventional Commits](https://www.conventionalcommits.org/)

[coc]: CODE_OF_CONDUCT.md
[todo]: https://github.com/thaw-app/Floe#todo
[it]: https://github.com/thaw-app/Floe/issues
[pr]: https://github.com/thaw-app/Floe/pulls
[prt]: https://github.com/thaw-app/Floe/blob/main/.github/pull_request_template.md
[gov]: GOVERNANCE.md
[dev]: ../docs/DEVELOPMENT.md
[sec]: SECURITY.md
[discord]: https://discord.gg/KDfWjWDnR4
