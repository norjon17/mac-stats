# Changelog

## 1.0.1 (2026-11-19)

- Built with Swift 6 strict concurrency checking: the compiler now proves most cross-thread access is safe.
- Fixed three data races: network reachability updates, the SMC fan-mode cache, and notification threshold tracking.
- Menu bar widgets and popup charts now update their values under a lock and redraw only on the main thread.
- Sleep and wake logging can no longer crash the app if macOS delivers those events off the main thread.
- What's new: this list is now available from Settings, in the About section.
- Build script stops on a failed build instead of reusing the previous app.

## 1.0.0 (2026-10-31)

- First release of mac-stats, a trimmed fork of Stats by Serhiy Mytrovtsiy.
- Four modules only: CPU usage, RAM usage, CPU/GPU temperature, network upload and download speed.
- Apple Silicon and macOS 26 or later; Liquid Glass popup.
- No telemetry, no updater, no privileged helper, no shell commands run in the background.
- Download speed falls back to route statistics when security software hides the network counters.
- Rotating log file with a 10-minute health line, viewable from Settings.
- Installer: DMG and PKG built by Scripts/package.sh.
