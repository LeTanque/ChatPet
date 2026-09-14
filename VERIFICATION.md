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
