# ChatPet

A standalone Swift macOS menu-bar companion, currently named **DesktopPet** in the app. **Blue Turtle—the pet already created for Frank—is the first and default pet.** Its 36 bundled PNG frames are copied unchanged from the corrected September 13, 2026 pet pack, including the visor transparency repair. Original variable frame timing is preserved. Nothing is installed into or modified inside ChatGPT.

## Build and run

Requires **macOS 14 or newer**, Xcode 16+ or a Swift 6 toolchain, and Apple command-line tools. No third-party packages, account, API key, packet capture permission, or administrator access is required.

```sh
cd ~/git/ChatPet
swift test
./Scripts/build-app.sh
open dist/DesktopPet.app
```

The script builds for the current Mac architecture, assembles a relocatable `.app`, applies an ad-hoc signature for local use, and verifies it. You can move the app to `~/Applications` or `/Applications`. The delivered binary is Apple Silicon; rebuild on Intel for an Intel binary. Opening `Package.swift` in Xcode is also supported. Use the packaging script for the complete app bundle; the command-line executable uses accessory activation policy as well.

Optional build variables: `CONFIGURATION=debug`, `OUTPUT_DIR=/path/to/output`, and `SIGNING_IDENTITY="Developer ID Application: …"`. Public distribution additionally requires appropriate Developer ID signing with hardened runtime and notarization; the local build is not notarized. Do not disable Gatekeeper.

If running in an environment with restricted compiler caches:

```sh
CLANG_MODULE_CACHE_PATH=/tmp/DesktopPet-clang \
SWIFT_MODULECACHE_PATH=/tmp/DesktopPet-swift \
./Scripts/build-app.sh
```

The build script's `--disable-sandbox` only disables SwiftPM's nested build sandbox; it changes no macOS system security settings.

## Controls

Use the **paw icon in the menu bar** to choose a pet, show/hide, pause, preview animations, recenter, import a pet pack, open Settings, or quit. There is no Dock or application-switcher icon. Closing Settings keeps the pet running. Reopening the application opens Settings.

Drag the pet to place it on any display. Enable click-through to stop it intercepting clicks; the menu bar remains available. Size, position, movement, selected pet, event mappings, trigger settings, and visibility persist. The pet is visible above normal windows and joins Spaces, with auxiliary full-screen behavior supported where macOS permits it.

The Settings **Events** tab maps each semantic event to any available animation. The play buttons preview for six seconds, making the pet visible and resuming it if needed. Choose `Idle` for an event if you prefer a quiet response. The **Network** tab displays live aggregate receive/send rates and sensitivity controls.

## Default behavior

| Event | Animation | Rule |
| --- | --- | --- |
| Downstream traffic | Run left | Dominant download rate |
| Upstream traffic | Run right | Dominant upload rate |
| Significant slowdown | Failed / tired | Below 25% of burst peak while still active |
| Traffic stops | Failed / tired | Below 2,048 B/s for 3 seconds after activity |
| No recent activity | Idle | Includes quiet startup |
| Occasional break | Viewing laptop | 4 seconds every random 45–100 seconds |

Network sampling defaults to once per second. Both directions count; if they are similar, the current direction persists until the other exceeds it by 20%. Failures last 2.5 seconds and take priority over laptop breaks. Background network events continue updating while temporary animations play, so the pet returns to the latest activity. Slowdown fires once per drop and rearms after substantial recovery. A brief gap does not count as stopped.

The pet moves at 55 points/second while running and stops traveling at the display edge, continuing the same animation in place. It never reverses direction just because it hit the edge. Disable travel to keep the animation stationary. System Reduce Motion stops frame animation and travel while retaining state changes. Hide/Pause suspends event sources. Sleep cancels sources; wake establishes new counter baselines.

## Network implementation and limits

`SystemNetworkReader` reads macOS `sysctl` routing-interface statistics (`NET_RT_IFLIST2` / `if_msghdr2.ifm_data`), which provide **64-bit receive/send byte counters**. It does not read packets, destinations, payloads, or per-process traffic. It makes no outgoing requests and stores no traffic history.

Automatic mode sums active `en*` Wi-Fi/Ethernet interfaces and excludes loopback and tunnel interfaces to reduce VPN double counting. Choose a specific interface (such as `utun3`) for a tunnel or nonstandard adapter. These counters cover all traffic on the chosen interface, including LAN activity, broadcasts, and other apps; they are not a measurement of internet speed or network errors. Bridging and unusual virtual-interface arrangements can still count the same transfer more than once; select one interface for those setups.

Rate estimation tracks each interface separately, uses monotonic elapsed time, skips a counter reset, and establishes a baseline for newly seen interfaces. A gap longer than 15 seconds establishes a new baseline. No active matching interface or a read error gives a visible status and idle state; it is not misrepresented as a failed download. A disappeared explicitly selected interface remains selected and resumes when it returns.

## Structure and extension points

```text
Sources/
  PetCore/                  # Pure configuration, counters, detection, routing, pack schema
  DesktopPet/
    DesktopPetApp.swift     # SwiftUI menu bar and accessory app lifecycle
    AppModel.swift          # Main-actor composition, settings, event orchestration
    EventSources.swift      # Cancellable network and occasional sources
    PetWindowController.swift # Transparent, nonactivating AppKit panel and movement
    PetView.swift           # Timed image rendering and procedural fallback
    SettingsView.swift      # Pet, event mapping, and network settings
    ConfigurationStore.swift # Atomic JSON persistence and corrupt-file backup
    PetLibrary.swift        # Bundled/custom pack loading and import validation
    Assets/BlueTurtle/      # Original PNGs, manifest, and provenance hashes
Tests/
  PetCoreTests/             # Detector, timing, routing, configuration, native reader
  DesktopPetTests/          # Persistence, bundled assets, imports, path containment
Examples/Lavender/          # Importable palette-only pet pack
Resources/Info.plist       # LSUIElement and minimum system version
Scripts/build-app.sh       # Build, bundle, sign, and verify
```

**Add a trigger:** implement the `@MainActor PetEventSource` protocol with cancellable `start(deliver:)`/`stop()`. Add semantic cases to `PetEvent`/`SourceUpdate` as needed, create the source in `AppModel.restartSources`, and route its updates in `receive`. Keep blocking work off the main actor, as `CounterWorker` does. Use `EventRouter` for temporary-event priority and expiration. Settings lists enum cases automatically; provide a human-readable title and default mapping.

**Add an animation:** extend `PetAnimation` and its title/direction metadata, add a procedural fallback in `PetView`, and supply clips in packs. The menu and mapping pickers enumerate animation cases. Movement is animation metadata, not hard-wired to network events. Missing pack clips use the pack's procedural species so new animations do not break old packs.

**Add a pet:** import a folder with the schema below. No Swift change or rebuild is needed. Runtime packs are data-only, with no scripts, remote URLs, or executable plug-ins. Compiled trigger/rendering extensions are explicit source-level extension points.

## Pet pack format

Import `Examples/Lavender` from the menu to try a palette-only pack. For a sprite pack, use transparent PNGs with consistent canvas dimensions and the same registration point:

```json
{
  "schemaVersion": 1,
  "id": "my.pet",
  "name": "My Pet",
  "species": "cat",
  "bodyColor": "#BEACE3",
  "accentColor": "#F8DBEA",
  "clips": {
    "idle": {
      "frames": ["frames/idle-0.png", "frames/idle-1.png"],
      "framesPerSecond": 8,
      "frameDurations": [1.68, 0.66]
    }
  }
}
```

`species` is `cat`, `fox`, or `robot` and controls the fallback. Supported clip keys are `idle`, `runLeft`, `runRight`, `failed`, and `laptop`. `frameDurations` is optional; when present, it gives each frame's duration in seconds, overriding FPS. All clips loop for as long as their animation is selected; event lifetime belongs to the router. The original Blue Turtle `running` row is the laptop clip. Its separate left/right rows are not mirrored approximations.

IDs must be unique and use letters, numbers, periods, hyphens, or underscores. `builtin.*` is reserved. Limits: 120 frames per clip, 1–30 FPS, per-frame durations 0.03–10 seconds, PNG dimensions up to 2048 × 2048, 64 MB of referenced files, and 128 MB of decoded frame data per pack. Frames must resolve inside the folder, including through symlinks. Imports validate and copy only the manifest and referenced frames; duplicate IDs are rejected instead of overwritten. Reload packs after manually editing an installed pack. Bundled assets carry provenance hashes in `Assets/BlueTurtle/provenance.json`.

## Configuration and recovery

Settings: `~/Library/Application Support/DesktopPet/settings.json`.
Custom pets: `~/Library/Application Support/DesktopPet/Pets/<id>/`.

Settings are normalized and atomically saved after changes; the schema version is currently 1. Invalid/unsupported settings are preserved as `settings-unreadable-<UUID>.json` before defaults may replace them. If that backup fails, saving is disabled and a notice explains why. To reset manually, quit the app and move `settings.json` aside. Preserve the `Pets` folder to keep custom packs.

When adding configuration fields, update decoding/migrations explicitly and bump the schema version for incompatible changes. Version 1 uses a complete stored configuration rather than merging partial manually written files. Unknown mapping keys are retained; absent mappings use defaults. Files produced by a newer unsupported version are backed up rather than silently interpreted.

## Verification

`swift test` exercises direction hysteresis, stop grace, slowdown recovery, interface resets/churn, 64-bit counters, wake gaps, temporary-event priority, configuration round trips, corruption backups, pack containment, duplicate import handling, all 36 Blue Turtle frames, variable frame timing, and a real system-counter read. See `VERIFICATION.md` for the checks performed on the delivered build.

For a manual check: open Settings → Events; preview all five animations; change one mapping; quit/reopen to check persistence; restore defaults. During a transfer, inspect Network rates and direction. Hide/show, pause/resume, drag, enable click-through, recenter, and check external-display removal or sleep/wake on your own setup.

## Apple references

- [MenuBarExtra and LSUIElement](https://developer.apple.com/documentation/swiftui/menubarextra)
- [NSPanel](https://developer.apple.com/documentation/appkit/nspanel)
- [Routing message definitions in Apple's XNU](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/net/if.h)
- [macOS sysctl interface](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/sysctl.3.html)

This independent local app is inspired by desktop-pet behavior. It does not connect to or depend on ChatGPT, and is not an OpenAI product.
