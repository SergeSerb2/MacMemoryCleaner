# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [1.0.0] - Unreleased

First release.

### Added

- Menu bar panel with memory used, a breakdown like Activity Monitor, swap use, and the
  memory-pressure level.
- One-click **Clean Memory**: flush pending writes (`sync`), ask apps to release memory
  (`memory_pressure -S`), and purge the disk cache (`purge`). Each step can be turned off.
- One-time admin setup that installs a narrow sudoers rule, and removes it on request.
- Top apps by memory, including their helper processes, with Quit and Force Quit, and a
  shortcut to Activity Monitor.
- Auto-clean when macOS reports memory pressure, or when available memory falls below a
  threshold, with a minimum wait between cleans.
- Global keyboard shortcut, ⌃⌥⌘M by default.
- Notifications after shortcut and automatic cleans.
- Open at login.
- Command-line mode: `--stats`, `--clean`, `--status`, `--setup`, `--show-rule`,
  `--remove-setup`, and `--version`, with `--json` output.
- Settings › About with the version and links.

[1.0.0]: https://github.com/SergeSerb2/MacMemoryCleaner/releases/tag/v1.0.0
