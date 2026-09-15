# Verification

Checked September 14, 2026 on an Apple Silicon Mac using Swift 6.3.3 and the macOS 26.5 SDK. The deployment target is macOS 14.

- **19 automated tests passed.** Covers network byte-rate calculation, interface resets/removal/addition, wake gaps, direction hysteresis, stop grace period, slowdown recovery, event priority/expiration, configuration validation/round trips, corrupt-file backups, pet imports/duplicate rejection, symlink containment, original frame timing, bundled asset loading, and a live native interface-counter read.
- **Release build passed.** Complete app bundle includes its own pet resources; Info.plist validation and strict code-signature verification passed with a local ad-hoc signature.
- **Native launch verified.** Blue Turtle appeared in the transparent desktop companion window. The native app stayed running with Settings closed; reopening Settings worked via the standard Command-comma shortcut.
- **All five previews verified through the native UI.** Idle, Run left, Run right, Failed / tired, and Viewing laptop appeared in the active pet state. Native screenshots visually confirmed the existing turtle artwork, failed pose, and laptop pose.
- **Live network values verified.** The Network tab displayed changing downstream/upstream rates from the Mac's real interfaces; the desktop pet was observed switching between run-left, run-right, and failed states during normal traffic.
- **GUI configuration persistence verified.** Changed Downloading to Viewing laptop in Settings and read the saved JSON to verify `downstream: laptop`. Restored default mappings afterward. Unit tests separately verify a fresh store instance reads persisted configuration.
- **Asset integrity verified.** The 36 shipped PNG frames were copied byte-for-byte from the previously created Blue Turtle pack, with SHA-256 hashes and original variable durations recorded in the bundle.

Limitations: Intel execution, macOS 14 specifically, external-display removal, fullscreen Spaces, sleep/wake, and Reduce Motion were not manually exercised on this run. Those behaviors have code paths (and pure baseline/reset tests where applicable), but are not claimed as visually verified. No controlled bandwidth benchmark or packet-level comparison was performed. The app is locally signed, not notarized for public distribution.

## Optional task activity trigger — September 14–15, 2026

- **30 automated tests passed** after adding task-state parsing, multi-task priority, stale-state expiration, blocking versus asynchronous questions, incremental/partial/malformed/oversized records, file replacement/deletion, missing-folder recovery, and migration from existing settings. Network regression tests remain included.
- **Release build and strict ad-hoc signature verification passed.** The running app was updated after backing up its previous bundle and preferences.
- **Real local task detection verified in the native app.** Enabling the default sessions folder showed an active local Codex task and Blue Turtle's Viewing laptop animation.
- **Synthetic lifecycle events verified through the live file reader and native UI.** An isolated test folder produced Waiting for a blocking input call, Celebration after completion, and Failed / tired after interruption. These checks used local test records, not actual failed user tasks. The completion/reaction duration was temporarily extended to 15 seconds for observation and restored to four seconds.
- **Opt-in and recovery verified.** Empty/quiet sessions released task priority. The default sessions folder was restored and the trigger switched off after testing. Existing pet selection and network preferences were preserved.
- **48 bundled PNG frames verified against the original Blue Turtle pack.** Waiting and review/celebration frames use the existing artwork and original timings; no artwork was regenerated.

The adapter covers local Codex session metadata. Browser/cloud-only tasks, internal approval dialogs, and unread-review state are not claimed as supported. See `docs/task-activity-investigation.md` for evidence and limitations. The original platform/manual-test limitations above still apply.
