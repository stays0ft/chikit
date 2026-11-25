# Contributing

Chikit is a small personal project, so contributions are best kept small and focused. Open an issue first
for anything big, so we can agree on it before you spend time.

## Build and test

You need macOS 14 or newer on Apple silicon, and Xcode or the Command Line Tools (Swift 6).

```sh
swift build                                 # compile
./build.sh --test                           # unit tests, no app and no UI
./build.sh && ./build/Chikit --selftest     # build the bundle, run the built-in self test
./build.sh --install                        # install to /Applications
./Tools/setup-signing.sh                    # once, so permissions survive rebuilds
```

CI runs the build, the selftest and the unit tests on every push and pull request. A change should pass
all three locally first.

## Layout

```
Sources/Vorssaint/   the app (the module keeps its inherited name)
  Core/              shared types, localized strings, defaults, the feature catalog
  Services/          each feature's logic
  UI/                SwiftUI views for the panel and Settings
  App/               the menu bar shell and feature lifecycle
Sources/FanControlHelper/   the privileged fan helper
Tests/MetricsTests.swift    unit tests (a standalone runner, no XCTest)
Tools/               icon generation, signing setup, uninstaller, UI smoke test
```

## Conventions

- Match the style of the code around you. SwiftUI views, small services, no new dependencies.
- Every feature is a case of `AppFeature` and can be installed and uninstalled. When it is off it must
  load nothing, so wire any new background work through `FeatureRuntime`.
- New user-facing text goes in the string tables for all 13 languages, or in English with a note so it can
  be translated.
- Keep the source file copyright headers. They credit the original project this one was forked from.
- Tests for pure logic go in `Tests/MetricsTests.swift`. The runner compiles a hand-picked file list, so
  add new support files to the list in `build.sh`.

## Pull requests

Keep them to one change, say what and why, and make sure `swift build` and `./build.sh --test` pass. By
contributing you agree your work is licensed under GPL-3.0-or-later like the rest of the project.
