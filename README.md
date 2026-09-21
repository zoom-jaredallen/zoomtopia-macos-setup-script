# Zoomtopia Mac Setup

A native macOS provisioning app for short-lived Zoomtopia lab MacBooks. It runs from a USB drive, shows live step-by-step status, asks for administrator authorization once, and safely supports repeat runs.

## Web distribution proposal

The current implementation requires a local payload. The proposed browser-download workflow, online Chrome/Zoom acquisition, and release requirements are documented in [Web distribution scope](docs/web-distribution-scope.md). These changes are scoped but not implemented; this repository does not yet provide a deployment-ready web release.

## USB layout

Keep the signed app and payload as siblings:

```text
USB/
├── Zoomtopia Setup.app
└── ZoomtopiaPayload/
    ├── Installers/
    │   ├── GoogleChrome.pkg
    │   ├── ZoomWorkplace-arm64.pkg
    │   └── ZoomWorkplace-x86_64.pkg
    ├── assets/
    │   ├── wallpaper.jpg
    │   └── wallpaper-green.jpg
    ├── config/
    │   ├── setup-config.json
    │   ├── us.zoom.config.plist
    │   └── ZoomPrivacy.mobileconfig   # optional; still user-approved
    └── checksums.txt
```

Generic packages are supported when a vendor package is universal. Architecture-specific packages take precedence.

## Prepare the payload

1. Download the official Chrome Enterprise PKG and Zoom IT Admin PKGs.
2. Rename and place them as shown above.
3. Choose the included blue `assets/wallpaper.jpg` or green `assets/wallpaper-green.jpg` in `config/setup-config.json`.
4. Copy `config/us.zoom.config.plist.example` to `config/us.zoom.config.plist` and adjust it if required.
5. Optionally add a tested `config/ZoomPrivacy.mobileconfig`.
6. Generate checksums:

   ```bash
   ./scripts/generate-checksums.sh
   ```

## Build

An ad-hoc signed development build works on this Mac:

```bash
./scripts/build-app.sh
```

The build output includes both `dist/Zoomtopia Setup.app` and its sibling `dist/ZoomtopiaPayload` folder, ready to copy to a USB drive after the payload is populated.

For distribution, install Xcode and use your Developer ID Application certificate:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Company (TEAMID)" \
  ./scripts/build-app.sh
```

Store notarization credentials once:

```bash
xcrun notarytool store-credentials "zoomtopia-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "APP-SPECIFIC-PASSWORD"
```

Then notarize:

```bash
NOTARY_PROFILE="zoomtopia-notary" ./scripts/notarize-app.sh
```

## What is idempotent

- A package is skipped when the application exists and the package SHA-256 matches the last successful installation.
- Vendor installer signatures are verified before any package executes.
- Managed Zoom preferences are safely replaced with the payload version.
- Trackpad preferences can be applied repeatedly.
- Existing correct desktop links are preserved; unrelated files are never overwritten.
- The wallpaper can be reapplied.
- Software Update is safe to rerun.

Persistent state is stored under `/var/db/com.zoom.zoomtopiasetup`, and logs are written to `/var/log/zoomtopia-setup.log`.

## Privacy limitation

An unmanaged Mac cannot silently grant every Zoom privacy permission. The app stages and opens a supplied profile, but macOS may still require local approval. It deliberately reports this as **Action required**, then opens a guided permission assistant for Camera, Microphone, Screen & System Audio Recording, and speaker testing. The assistant includes a draggable Zoom app tile for Screen Recording settings and records explicit operator confirmation. Never patch the TCC database or disable SIP to bypass consent.

## Operator workflow

1. Log into the account students will use.
2. Connect AC power and the USB drive.
3. Double-click `Zoomtopia Setup.app`.
4. Click **Start Setup** and enter an administrator password.
5. Complete the privacy approval indicated by the app.
6. Restart if Software Update requires it, then run the app again for final verification.
