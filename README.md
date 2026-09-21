# Zoomtopia Mac Setup

Prepare a Mac for Zoomtopia labs with a guided macOS app. It installs or updates Google Chrome and Zoom Workplace, applies the event setup, and walks you through the Zoom checks.

**[Download Zoomtopia Setup 1.2.0](https://github.com/zoom-jaredallen/zoomtopia-macos-setup-script/releases/download/v1.2.0/Zoomtopia-Setup.zip)** · [Release notes](https://github.com/zoom-jaredallen/zoomtopia-macos-setup-script/releases/tag/v1.2.0) · [Download and setup page](https://zoom-jaredallen.github.io/zoomtopia-macos-setup-script/)

Version 1.2.0, build 3 is signed by Jared Allen and notarized by Apple. Browser download, archive integrity and launch under macOS App Translocation were verified on an Apple Silicon Mac running macOS 26.6.2. Full end-to-end qualification of this signed release, fresh Zoom permission checks and clean Intel testing remain outstanding. Pilot it on your lab machines before wider deployment. See [test coverage](docs/release-1.2.0-validation.md).

## Before you start

- Use a Mac running macOS 13 or later, with Intel or Apple Silicon. Chrome and Zoom may impose newer minimum versions; setup checks compatibility.
- Log into the account students will use, connect power, and allow at least **8 GB free space**.
- Connect to the approved network and have administrator credentials available. Online setup downloads both vendor installers, even when the apps are already current.
- Save your work. Full setup changes the wallpaper, Zoom preferences and trackpad settings, and adds Chrome and Zoom Desktop shortcuts.

## Download and run

1. Download **Zoomtopia-Setup.zip** using the link above. On the release page, choose this file under **Assets**; the source-code archives are for developers.
2. Double-click the ZIP in Downloads to extract **Zoomtopia Setup.app**, then open the app. The ZIP preserves the app's files and signature; no installer or USB drive is required.
3. Confirm the normal macOS first-launch dialog if shown. If your organization blocks the app, contact IT rather than disabling macOS security.
4. Click **Start Setup** (or **Run Again**), review the run mode, and choose **Begin reviewed setup**.
5. Wait while the app downloads and verifies Chrome and Zoom. Enter your administrator password in the macOS authorization prompt when requested.

| Run mode | What it does |
| --- | --- |
| **Full lab setup** | Installs/checks Chrome and Zoom, applies Zoom preferences, wallpaper and bottom-right secondary click, adds Desktop shortcuts, checks macOS updates, and guides the final permission checks. |
| **Limited application test** | Installs/checks Chrome and Zoom only. It changes installed software and is not a dry run. It cannot mark a Mac ready. |

An authentic current or newer Chrome/Zoom installation is skipped automatically. Missing or older versions are installed or upgraded. Newer versions are not downgraded. Online “current” means the version served by the vendor's installer endpoint at the time of the run.

## Finish the setup

1. Resolve any warnings shown in the summary. **Retry Wallpaper** and **Recheck Updates** let you retry those steps individually.
2. If updates are required, click **Authorize Update / Restart…**. In Apple's Software Update, install updates for the current macOS major version and recommended app updates. The app does not install macOS updates or reboot automatically.
3. If macOS explicitly asks to restart, select **macOS requested a restart…** in the app, save your work, and restart through Software Update. Reopen setup and run again afterward.
4. Open **Permission Assistant**. In Zoom Workplace, open the settings cog and visit **Video & effects**, then **Audio**. Approve camera/microphone prompts, check the camera preview, and use **Test microphone** and **Test speaker**. Use the test-meeting option if needed.
5. Test a screen share and approve **Screen & System Audio Recording** when macOS asks. Restart Zoom if requested. Confirm all four checks only after testing them.
6. Choose **Mark Mac Ready** once full setup and all four checks pass.

Saved results are a summary, not proof of readiness: reopening the app requires a new run. The permission checkboxes record your confirmation; the app does not automatically inspect Zoom's privacy permissions.

## Customize for your event

Run mode and online/offline installer selection are available in the app. Event-wide settings are built into the signed app, so a maintainer must change the source inputs and produce a new signed, notarized build. Editing a downloaded `.app` invalidates its signature.

| Customize | Source file or folder |
| --- | --- |
| Power requirement, trackpad setup, update checks and wallpaper selection | [setup-config.json](ZoomtopiaPayload/config/setup-config.json) |
| Zoom preferences | [us.zoom.config.plist](ZoomtopiaPayload/config/us.zoom.config.plist) |
| Event wallpaper | [ZoomtopiaPayload/assets](ZoomtopiaPayload/assets) |
| App colors and wordmark | [Branding.swift](Sources/ZoomtopiaSetupApp/Branding.swift) and [AppResources](AppResources) |
| Approved offline installers and online vendor sources | [package-catalog.json](AppResources/package-catalog.json) |

For example, a maintainer can set `configureTrackpad` to `false`, or choose another bundled JPEG with `wallpaperFilename`. Despite its legacy name, `installOSUpdates` controls the update-check workflow; it never enables unattended OS installation. Optional privacy profiles must also be bundled at build time and may still require user approval.

See the [developer contribution guide](CONTRIBUTING.md) for configuration details, building, tests, signing and publishing a customized app.

## Offline setup

Ask your staging lead for the installer versions approved for your app release. Place them in this folder structure, click **Offline Payload…**, and select the `ZoomtopiaPayload` folder:

```text
ZoomtopiaPayload/
└── Installers/
    ├── GoogleChrome.pkg
    └── ZoomWorkplace.pkg
```

Both packages must match the release's approved hashes and signatures. Offline mode cannot check the latest online version and does not download missing packages. The folder supplies installers only; event settings still come from the signed app. Choose **Use Online Downloads** to switch back.

## Troubleshooting

- **Download or launch blocked:** ask IT to approve the app and download hosts. GitHub assets use `release-assets.githubusercontent.com`; vendor downloads use Google and Zoom hosts. No security bypass is needed for the signed app.
- **Download or verification failed:** check the network and retry. Do not replace packages with unverified downloads.
- **Administrator authorization cancelled:** run setup again when credentials are available.
- **Mac cannot be marked ready:** resolve the listed failures, update/restart requirements and all four Zoom checks. Limited mode cannot establish readiness.
- **Need diagnostic information:** choose **Open Log**. The log is at `/var/log/zoomtopia-setup.log`. Review logs for private information before sharing them in a [GitHub issue](https://github.com/zoom-jaredallen/zoomtopia-macos-setup-script/issues).

Developers: see [CONTRIBUTING.md](CONTRIBUTING.md) for architecture references, tests and the release workflow.
