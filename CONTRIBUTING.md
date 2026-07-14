# Contributing to RiffMemo

This is a solo/portfolio project, not a project with a formal contribution process — but PRs are welcome. This doc is the shortest path from "cloned the repo" to "opened a PR."

## Building and testing

Follow the [Getting Started](README.md#getting-started) section in the README for prerequisites and setup.

To run the same build-and-test steps CI runs:

```bash
cd RiffMemo
xcodebuild clean build \
  -project RiffMemo.xcodeproj \
  -scheme RiffMemo \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO

xcodebuild test \
  -project RiffMemo.xcodeproj \
  -scheme RiffMemo \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO
```

If Xcode reports it can't find that destination unambiguously (common when you have multiple simulator runtimes installed — e.g. more than one iOS version of "iPhone 16"), run `xcrun simctl list devices available` and swap in any available iPhone simulator name/OS from that list. CI pins a single runner image so it doesn't hit this ambiguity, but a local machine's exact set of installed runtimes varies.

A PR's checks must pass before it merges — see [`.github/workflows/ios-build.yml`](.github/workflows/ios-build.yml).

## Finding something to work on

Work is tracked in a private Linear workspace, not GitHub Issues, so the backlog isn't publicly browsable. If you want to contribute:

- Open a GitHub issue describing the bug or feature first, so it can be discussed before you put work into a PR.
- Or reach out directly — contact info is in the [README](README.md#contact).

## Branch naming and commits

This repo's convention (see `git log` for examples):

- Branches: `<username>/<short-kebab-case-description>` (e.g. `waskar/fix-waveform-seek`). If your work maps to an internal ticket you were given a number for, it looks like `<username>/was-<number>-<slug>`.
- Commits/PR titles: `<type>(<scope>): <description>` using conventional-commit types (`fix`, `feat`, `ref`, `docs`, `test`, `chore`). If the change was filed against an internal ticket, include its number: `fix(audio): WAS-55 — Harden recording/analysis pipeline`. Omit the ticket reference entirely if there isn't one — don't invent a number.

## Tests

New code should ship with unit tests where the code is actually testable. Every feature ViewModel follows the same pattern: dependencies are injected as protocols (e.g. `AudioRecorderProtocol`, `RecordingRepository`, `AudioPlayerProtocol`) so tests can substitute mocks instead of touching AVFoundation, UIKit, or SwiftData directly — see `RiffMemoTests/RecordingViewModelRaceTests.swift` for the shape, and `RiffMemoTests/Mocks/` for the available test doubles. If a new ViewModel takes a concrete dependency that would need real I/O in tests, introduce a protocol for it following that same pattern before merging.

## Opening a PR

PRs are squash-merged, so the PR title becomes the commit message on `main` — keep it in the `type(scope): description` form above. Open against `main`, make sure CI is green, and describe what changed and why in the PR body.
