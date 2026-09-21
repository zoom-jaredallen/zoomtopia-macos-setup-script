# Zoomtopia Mac Setup agent guide

## Purpose

This repository builds a one-click macOS provisioning app for approximately 220 temporary student lab MacBooks. The machines are used for one week, then wiped. The intended deployment is a USB drive containing the signed app and a sibling payload folder; this is deliberately lighter than fleet MDM.

Optimize for a staging operator preparing many Macs in parallel: one administrator authorization, visible progress, safe reruns, clear failures, and an explicit final readiness check.

Read [README.md](README.md) when changing payload preparation, Developer ID signing, notarization, or the operator workflow.

## Architecture

The system has two trust contexts:

1. The native Swift app runs as the logged-in operator. It owns the UI, status display, permission assistant, and administrator authorization prompt.
2. `Scripts/bootstrap.sh` runs as root after authorization. It validates and installs the external payload, writes JSON-lines progress events, and records persistent installation hashes.

Key components:

- `Sources/ZoomtopiaSetupApp/main.swift`: AppKit lifecycle and SwiftUI hosting window.
- `Sources/ZoomtopiaSetupApp/ZoomtopiaSetupApp.swift`: provisioning UI, Zoom permission assistant, and final-ready screen.
- `Sources/ZoomtopiaSetupApp/SetupController.swift`: phase/state model, root-script invocation, progress-file polling, Zoom launch/test actions, and System Settings links.
- `Sources/ZoomtopiaSetupApp/Branding.swift` and `AppResources/`: dark Zoomtopia design tokens and bundled wordmark.
- `Scripts/bootstrap.sh`: privileged, idempotent provisioning engine.
- `ZoomtopiaPayload/`: external packages, wallpaper, managed Zoom preferences, optional privacy profile, and checksums.
- `scripts/build-app.sh`: creates a universal Intel/Apple Silicon app and copies the payload into `dist/`.
- `scripts/generate-checksums.sh`: regenerates the external payload manifest.
- `scripts/notarize-app.sh`: submits and staples the Developer ID build.

`dist/` and `.build/` are generated outputs. Make source changes elsewhere, then rebuild.

## Core invariants

- **Idempotent:** every privileged operation detects existing state. Package installs use the payload SHA-256 stored under `/var/db/com.zoom.zoomtopiasetup`; the same successful payload is skipped on rerun.
- **Authentic:** verify payload checksums and vendor package signatures before installation. Keep the app separately Developer ID signed and notarized.
- **Observable:** every bootstrap step emits running and terminal JSONL events. A failure must be visible in the UI and `/var/log/zoomtopia-setup.log`.
- **Architecture-aware:** prefer `Name-arm64.pkg` or `Name-x86_64.pkg`, falling back to a universal `Name.pkg`. Preserve both app slices in release builds.
- **User-scoped preferences:** trackpad, wallpaper, and Desktop links target the console user while installation and managed preferences remain system-scoped.
- **Least privilege:** request only permissions needed for Zoom labs. Zoom normally needs Camera, Microphone, and Screen & System Audio Recording; speaker output is tested rather than granted. Accessibility is out of scope unless a concrete lab requirement is added.
- **Honest consent:** macOS privacy grants remain user-controlled. The permission assistant may launch Zoom, open the relevant settings, and provide a draggable Zoom tile. It records operator confirmation; it must not claim to inspect another signed app's TCC state.
- **Safe TCC handling:** use supported prompts, System Settings, and tested configuration profiles. Preserve SIP and the TCC database.
- **Non-destructive:** preserve unrelated Desktop items and user files. A naming collision becomes a warning, never an overwrite.

## Change workflow

1. Identify whether the change belongs to the user app, root bootstrap, or external payload. Keep responsibility in one layer.
2. For a bootstrap change, preserve Bash 3.2 compatibility because `/bin/bash` on supported macOS releases may be old. Emit a terminal status for every affected step and retain safe rerun behavior.
3. For a UI change, preserve the three phases: provisioning summary → permission assistant → ready. Operator checkboxes are attestations, not automatic permission detection.
4. For a new payload file or package name, update payload resolution, example configuration, checksum generation, and README instructions together.
5. Rebuild generated output only after source validation succeeds.

## Validation

Run the non-destructive checks after every relevant change:

```bash
bash -n Scripts/bootstrap.sh scripts/build-app.sh scripts/generate-checksums.sh scripts/notarize-app.sh
./scripts/build-app.sh
file "dist/Zoomtopia Setup.app/Contents/MacOS/Zoomtopia Setup"
lipo -archs "dist/Zoomtopia Setup.app/Contents/MacOS/Zoomtopia Setup"
codesign --verify --deep --strict --verbose=2 "dist/Zoomtopia Setup.app"
plutil -lint "dist/Zoomtopia Setup.app/Contents/Info.plist"
```

Preview the permission assistant without installing software or changing system settings:

```bash
open -n "dist/Zoomtopia Setup.app" --args --permission-preview
open -n "dist/Zoomtopia Setup.app" --args --ready-preview
```

The completed build must contain `x86_64 arm64`, pass bundle/signature checks, render both the setup and permission views, and leave **Mark Mac Ready** disabled until all four operator checks are selected.

Run the real **Start Setup** flow only on an authorized staging/test Mac with prepared installer packages and wallpaper. It installs software as root and may apply macOS updates.

## Deployment boundaries

- The repository does not contain vendor installer packages or the event wallpaper. Populate `ZoomtopiaPayload`, then regenerate `checksums.txt`.
- Development builds are ad-hoc signed. Distribution requires the user's Developer ID Application identity and notarization credentials described in the README.
- A local `.mobileconfig` may still require user approval and cannot provide the guarantees of supervised MDM. Keep the guided permission flow functional when no profile is present.
- macOS updates may require a volume-owner password or restart. Report that state; do not force an unattended reboot.
