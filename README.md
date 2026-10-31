# mac-stats

A trimmed fork of [exelban/stats](https://github.com/exelban/stats) that shows four things in the macOS menu bar and nothing else:

- CPU usage
- RAM usage
- CPU and GPU temperature
- Network download and upload speed

Built for Apple Silicon on macOS 26 and newer. Ad-hoc signed, no network access, no telemetry, no updater, no privileged helper.

## Why a fork

Upstream Stats is a large app: ten modules, a remote-monitoring client, an auto-updater, desktop widgets, a privileged fan-control daemon, and readers that shell out to `top`, `ps`, `nettop` and `curl` on timers. This fork keeps the parts needed for the four metrics above and removes the rest, so there is less to go wrong when the app runs for days.

What was removed: GPU, Disk, Battery, Bluetooth, Clock and Remote modules; the WidgetKit extension; the SMC helper daemon and all fan control; LevelDB history; the System Stats telemetry client; the updater; the HID and IOReport private-API sensor paths; every subprocess-spawning reader; 40 of 41 localizations.

What was fixed on the way (from a reader audit of the upstream code):

- Net: the interface name was re-resolved through `configd` on every access, the VPN proxy lookup ran every tick regardless of the setting, and link details were recomputed per address entry. Now one `sysctl` per tick, details every 15 s.
- Sensors: every discovered SMC key was polled every second and every non-success read printed an error line. Now keys are probed once at startup, only displayed sensors are polled, failing keys back off, and nothing is printed.
- CPU: the temperature reader probed five Intel-only keys on every tick before reaching the Apple Silicon list.
- Kit: debug logging is off unless the app is started with `--debug`; error logging is rate-limited per call site.

## Build

Requirements: Xcode 27 or newer, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
Scripts/build.sh            # builds build/Stats.app
Scripts/build.sh --install  # builds and replaces /Applications/Stats.app
```

The Xcode project is generated from `project.yml` and is not committed. To open it in Xcode, run `xcodegen generate` first. Edit `project.yml`, not the project, when adding files or targets.

If `xcodebuild` complains that the active developer directory is CommandLineTools, either run `sudo xcode-select -s /Applications/Xcode.app` once, or leave it and let the script set `DEVELOPER_DIR`.

## First run on macOS 26

macOS 26 has a privacy control under System Settings → Menu Bar. If the app is running but no icons appear, open that panel and toggle Stats on.

The "Start at login" switch in Settings uses the system login-item service. Because the app is ad-hoc signed, macOS may ask you to approve it under System Settings → General → Login Items the first time.

## Soak test

`Scripts/soak.sh build/Stats.app 12` runs the app for 12 hours, samples memory, CPU time, file descriptors, child processes and Mach ports every five minutes, runs `leaks` at the end, and writes a pass/fail summary. The acceptance bar is under 5 MB of memory drift, zero child processes, and zero error lines on stdout.

## Layout

- `Kit/` shared framework: Store, Reader, Module, menu bar widgets, popup and settings windows, charts, SMC client.
- `Modules/CPU`, `Modules/RAM`, `Modules/Sensors`, `Modules/Net` one framework each.
- `Stats/` the app shell: settings window, dashboard, combined-modules view.
- `SMC/` the `smc` command-line tool for listing sensor keys (`smc list -t`).
- `Tests/` unit tests.

## Credits and licence

All of the real work is Serhiy Mytrovtsiy's in [exelban/stats](https://github.com/exelban/stats), MIT licensed. This fork keeps that licence; see `LICENSE`.
