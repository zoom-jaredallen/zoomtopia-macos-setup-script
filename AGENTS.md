# Zoomtopia Mac Setup agent guide

## Purpose

This repository builds a one-click macOS provisioning app for approximately 220 temporary student lab MacBooks. The machines are used for one week, then wiped. The primary deployment is a browser-downloaded, signed and notarized self-contained app. Optional offline installer folders remain supported; this is deliberately lighter than fleet MDM.

Optimize for a staging operator preparing many Macs in parallel: one administrator authorization, visible progress, safe reruns, clear failures, and an explicit final readiness check.

Read [README.md](README.md) when changing payload preparation, Developer ID signing, notarization, or the operator workflow.

## Architecture

The system has two trust contexts:

1. The native Swift app runs as the logged-in operator. It owns the UI, status display, permission assistant, and administrator authorization prompt.
2. `Sources/PayloadVerifier/main.swift` runs from a verified root-owned snapshot after authorization. It validates and stages approved payload files before invoking `Scripts/bootstrap.sh`, which installs them, emits JSON-lines progress, and records persistent installation hashes.

Key components:

- `Sources/ZoomtopiaSetupApp/main.swift`: AppKit lifecycle and SwiftUI hosting window.
- `Sources/ZoomtopiaSetupApp/ZoomtopiaSetupApp.swift`: provisioning UI, Zoom permission assistant, and final-ready screen.
- `Sources/ZoomtopiaSetupApp/SetupController.swift`: phase/state model, root-script invocation, progress-file polling, Zoom launch/test actions, and System Settings links.
- `Sources/ZoomtopiaSetupApp/Branding.swift` and `AppResources/`: dark Zoomtopia design tokens and bundled wordmark.
- `Sources/SetupCore/`: package catalog/policy, downloader, signed installer metadata, resource validation, signing identity, and readiness rules.
- `Sources/PayloadVerifier/main.swift`: privileged verification/staging entry point and safe event writer.
- `Scripts/bootstrap.sh`: privileged, idempotent provisioning engine.
- `Scripts/update-policy.sh`: restart tracking across boot sessions.
- `ZoomtopiaPayload/`: build-time wallpaper/configuration/profile inputs and optional offline packages.
- `AppResources/package-catalog.json`: offline package bytes, minimum online versions, current vendor sources, and trusted vendor identities.
- `scripts/build-app.sh`: creates a self-contained universal Intel/Apple Silicon app and verifier in `dist/`.
- `scripts/generate-checksums.sh`: regenerates the external payload manifest.
- `scripts/notarize-app.sh`: submits and staples the Developer ID build.

`dist/` and `.build/` are generated outputs. Make source changes elsewhere, then rebuild.

## Core invariants

- **Idempotent:** every privileged operation detects existing state. An authentic installed app at or above the current signed installer version is skipped; successful installer hashes remain recorded under `/var/db/com.zoom.zoomtopiasetup`. Never silently downgrade newer apps.
- **Authentic:** verify every consumed resource/package against the signed manifest/catalog and vendor identity before installation from private root-owned staging. Keep the app separately Developer ID signed and notarized.
- **Observable:** every bootstrap step emits running and terminal JSONL events. A failure must be visible in the UI and `/var/log/zoomtopia-setup.log`.
- **Architecture-aware:** offline filenames prefer `Name-arm64.pkg` or `Name-x86_64.pkg`, falling back to `Name.pkg`; bytes must match the catalog. The current approved packages are universal. Preserve both app slices in release builds.
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
./Scripts/test.sh
bash -n Scripts/*.sh Tests/*.sh
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

- The repository contains the event wallpapers and build-time configuration, but no vendor installers. Online mode downloads current vendor packages and authenticates signed version metadata; offline mode accepts only packages matching the bundled catalog. Root derives its per-run catalog from authenticated private package copies.
- The final downloadable ZIP must be created after stapling and pass `Scripts/package-release.sh`.
- Development builds are ad-hoc signed. Distribution requires the user's Developer ID Application identity and notarization credentials described in the README.
- A local `.mobileconfig` may still require user approval and cannot provide the guarantees of supervised MDM. Keep the guided permission flow functional when no profile is present.
- macOS updates may require a volume-owner password or restart. Record the boot session before installing updates; require a new boot and clean update check before readiness. Do not force an unattended reboot.
