# Contributing

Thanks for helping. Bug reports, fixes, and small, focused features are welcome. For a
larger change, please open an issue first, so we can agree on the approach.

## Requirements

- macOS 27 on Apple silicon
- Xcode 27, or the Command Line Tools for Xcode 27

## Build and run

```sh
swift build                     # debug build
scripts/build.sh                # signed .app, .zip, and .dmg in build/
open "build/Mac Memory Cleaner.app"
```

Watch the app log while you test:

```sh
log stream --level info --predicate 'subsystem == "com.serbinenko.MacMemoryCleaner"'
```

The admin steps need the one-time setup. Run it from the app, or with
`"build/Mac Memory Cleaner.app/Contents/MacOS/MacMemoryCleaner" --setup`.

## Project layout

| Path | Contents |
| :--- | :--- |
| `Sources/MacMemoryCleaner/MacMemoryCleanerApp.swift` | Entry point, scenes, menu bar label |
| `Sources/MacMemoryCleaner/AppState.swift` | Observable state: polling, cleaning, auto-clean, hot key |
| `Sources/MacMemoryCleaner/Preferences.swift` | Every setting, with its default value in one place |
| `Sources/MacMemoryCleaner/AppInfo.swift` | App name, version, and links |
| `Sources/MacMemoryCleaner/Cleaning/` | The clean steps, the report, and the lock that allows one clean at a time |
| `Sources/MacMemoryCleaner/Memory/` | Memory statistics and the per-app memory sampler |
| `Sources/MacMemoryCleaner/System/` | sudo setup, shell runner, hot key, notifications, login item, log |
| `Sources/MacMemoryCleaner/Views/` | The menu bar panel and the Settings window |
| `Sources/MacMemoryCleaner/CommandLineInterface.swift` | `--stats`, `--clean`, and the other commands |
| `Sources/MacMemoryCleaner/Screenshots.swift` | `--screenshots`, which renders the README images |
| `scripts/` | Build, packaging, and icon scripts |

## Code style

- Swift 6 language mode. The module uses default `MainActor` isolation. Mark code that must
  run elsewhere `nonisolated` or `@concurrent`.
- Follow the style of the code around your change. Use comments to explain *why*, not *what*.
- Keep the app free of dependencies, network access, and telemetry.
- User-facing text should be short and plain. Prefer one idea per sentence.

## Testing

There is no unit test suite. Check your change end to end with the real app and the
command line:

```sh
MMC="build/Mac Memory Cleaner.app/Contents/MacOS/MacMemoryCleaner"
"$MMC" --stats
"$MMC" --clean --json
"$MMC" --screenshots /tmp/mmc-screenshots   # renders the panel and all Settings tabs
```

Give your terminal Screen Recording permission first. Without it, `--screenshots` still
works, but Liquid Glass looks flat. Each window comes to the front and takes keystrokes for
about a second, so do not type while it runs. Render on a Retina display for sharp images.

CI builds the app on macOS 27 for every pull request and runs a real clean on the runner.

## Pull requests

- Keep each pull request to one change.
- Describe what you changed, why, and how you tested it.
- For changes users will notice, add an entry under `## [Unreleased]` at the top of
  `CHANGELOG.md`. Create that section if it is missing.
- If the UI changes, update the README screenshots with `--screenshots docs --demo`. The
  `--demo` data keeps the apps on your Mac out of the images.

## Releasing (maintainers)

1. In `CHANGELOG.md`, rename the version section to `## [X.Y.Z] - YYYY-MM-DD` and add its
   link at the bottom.
2. Set `CFBundleShortVersionString` in `Resources/Info.plist` to `X.Y.Z`.
3. Commit and push to `main`, then tag and push the tag:
   `git tag vX.Y.Z && git push origin vX.Y.Z`. The workflow stops if the changelog section
   has no date.
4. The Release workflow builds the app and opens a **draft** release with the DMG, zip, and
   checksums. Check it, then publish it.

To sign with Developer ID and notarize, add these repository secrets:
`DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD` (a base64 `.p12` export of your
Developer ID Application certificate), and `NOTARY_KEY_BASE64`, `NOTARY_KEY_ID`,
`NOTARY_ISSUER` (an App Store Connect API key). Without them, releases are ad-hoc signed.
