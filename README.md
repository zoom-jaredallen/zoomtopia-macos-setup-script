# Zoomtopia Mac Setup

A native macOS provisioning app for approximately 220 short-lived Zoomtopia lab MacBooks. It checks the current vendor Chrome and Zoom installers and upgrades older installations, requests administrator authorization once for provisioning, reports live progress, and guides the operator through the final Zoom checks.

**Web workflow implemented; release qualification is still required.** The candidate catalog contains Chrome **153.0.8010.53** and Zoom IT Admin **7.2.0.88195**, downloaded from the official vendors on 2026-09-21. Package signatures, hashes, metadata and both executable architectures were inspected. These are candidate versions, not a claim of lab acceptance testing. A deployment download must be notarized and piloted on representative staging Macs.

## Operator workflow

1. Log into the account students will use, connect AC power, and join the approved network.
2. Visit the staging lead's short link or the [release page](https://github.com/zoom-jaredallen/zoomtopia-macos-setup-script/releases). Download the approved release's **Zoomtopia-Setup.zip**, not GitHub's source-code ZIP.
3. Expand the ZIP and open **Zoomtopia Setup.app**. Confirm the normal macOS first-launch dialog.
4. Click **Start Setup**. The app downloads the current vendor installers, verifies their signatures, and compares their signed versions with installed Chrome and Zoom before requesting administrator credentials. Current or newer installations continue automatically; older versions are upgraded.
5. Authorize setup in the macOS dialog. The app installs/configures software, trackpad preferences, wallpaper and Desktop shortcuts, and processes macOS updates.
6. Resolve any warnings, including required restarts, and rerun. Once automated checks pass, confirm Camera, Microphone, Screen & System Audio Recording, and speaker testing. **Mark Mac Ready** requires all four confirmations.

Privacy consent, optional profile approval, and some macOS updates can require further interaction. Passwords are handled by macOS authorization. The app does not inspect Zoom's private TCC state or bypass corporate application controls.

## Online and offline inputs

The app is self-contained: wallpapers, configuration, the package catalog, and verifier are inside its signed bundle. It works without a sibling payload folder, including when macOS translocates a downloaded app.

Online mode uses the official current Chrome stable and Zoom IT Admin installer URLs in `AppResources/package-catalog.json`. Each run downloads both packages to determine the versions from vendor-signed `Distribution` metadata. An authentic installed app at that version or newer is skipped automatically; an older or missing app is installed. Newer installations are never downgraded. Conflicting, unverifiable or incompatible installations still stop with a specific error.

The bundled catalog fixes vendor signing identities, bundle identifiers, permitted HTTPS hosts, minimum versions and offline package hashes. Online packages may change without rebuilding the setup app: the downloaded package must have the expected trusted vendor signature and a signed version at least as new as the bundled minimum. Its SHA-256 is computed locally to protect subsequent copies; this is distinct from offline mode's release-pinned checksum. A failed online check stops visibly rather than claiming a cached version is latest. “Current” means the package served by the vendor endpoint at preparation time; staged vendor rollouts can differ from another Mac's auto-update channel.

Vendor sources: [Google's current stable package guidance](https://support.google.com/chrome/a/answer/9915669?hl=en) and [Zoom's current IT Admin installer](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0060407).

For offline staging, choose **Offline Payload…** and select:

```text
ZoomtopiaPayload/
└── Installers/
    ├── GoogleChrome.pkg
    └── ZoomWorkplace.pkg
```

Architecture-suffixed names (`GoogleChrome-arm64.pkg`, for example) take precedence, but the bytes must match this app's approved catalog. Both installers must be supplied in offline mode, which compares against the bundled approved versions and cannot establish the latest online version. Offline mode never fetches a missing package from the web. **Use Online Downloads** restores network mode. `ZOOMTOPIA_PAYLOAD_ROOT` is also supported for controlled local launches.

Offline folders supply installers only. Configuration and optional privacy profiles must be selected at build time and sealed into the signed bundle; arbitrary external configuration is not trusted at runtime. The optional `checksums.txt` is an inventory aid, not the trust anchor.

## Configuration and catalog maintenance

- `ZoomtopiaPayload/config/setup-config.json`: power requirement, trackpad, OS updates, wallpaper choice, Zoom plist and optional profile filenames.
- `ZoomtopiaPayload/config/us.zoom.config.plist`: active managed Zoom preferences. An example is retained alongside it.
- `ZoomtopiaPayload/assets/`: blue and green event wallpapers.
- `ZoomtopiaPayload/config/ZoomPrivacy.mobileconfig`: optional tested profile, bundled only when present. Never commit profiles containing private enrollment data.
- `AppResources/package-catalog.json`: offline approved versions/hashes/sizes, online minimum versions, current vendor URLs, bundle identifiers, version keys and expected vendor signing identities.

To refresh a candidate, download its official Enterprise/IT Admin package on the maintainer Mac; run `pkgutil --check-signature`, calculate `shasum -a 256`, and inspect `pkgutil --expand-full` output for app versions, supported macOS releases and architectures. Update the catalog with those observed values. Use `CFBundleShortVersionString` for Chrome and `CFBundleVersion` for Zoom. Keep the redirect host list explicit. Build, use the bundled verifier's `--verify-package ID PATH`, and pilot before release. Do not install vendor packages just to inspect them.

Package signature checks are mandatory. The legacy `requireSignedPackages` configuration toggle has been removed. Both current packages support Intel and Apple Silicon; a future architecture-specific release requires catalog selection changes, not just a filename change.

## Build and tests

macOS 13+, Swift 5.9 or later, and Apple command-line developer tools are required. No third-party runtime dependencies are used.

```bash
./Scripts/test.sh
bash -n Scripts/*.sh Tests/bootstrap-test.sh
./Scripts/build-app.sh
file "dist/Zoomtopia Setup.app/Contents/MacOS/Zoomtopia Setup"
lipo -archs "dist/Zoomtopia Setup.app/Contents/MacOS/Zoomtopia Setup"
lipo -archs "dist/Zoomtopia Setup.app/Contents/Resources/PayloadVerifier"
codesign --verify --deep --strict --verbose=2 "dist/Zoomtopia Setup.app"
plutil -lint "dist/Zoomtopia Setup.app/Contents/Info.plist"
```

The test script works with Command Line Tools and runs policy, file integrity, locking, download failure/cancellation, readiness, signed-executable replacement, update-restart persistence and shell regression tests. The Swift tests also support `swift test` when full Xcode supplies XCTest. CI runs non-destructive checks and builds both architecture slices.

Development builds are ad-hoc signed. Distribution signing:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Company (TEAMID)" \
  ./Scripts/build-app.sh
```

The verifier and app are signed separately with hardened runtime. Build output contains the app only; no vendor packages are bundled. `APP_VERSION` overrides the default version, currently `1.1.0`.

Non-destructive UI previews:

```bash
open -n "dist/Zoomtopia Setup.app" --args --permission-preview
open -n "dist/Zoomtopia Setup.app" --args --ready-preview
```

## Notarization and release

Store credentials locally using Apple's interactive prompt (never put passwords into Git):

```bash
xcrun notarytool store-credentials "zoomtopia-notary"
NOTARY_PROFILE="zoomtopia-notary" ./Scripts/notarize-app.sh
```

The notarization script submits the signed app, staples it, checks Gatekeeper, then invokes `Scripts/package-release.sh`. The final **Zoomtopia-Setup.zip is rebuilt after stapling** and accompanied by `SHA256SUMS`. Packaging refuses an unstapled/rejected app and verifies both architecture slices and bundled resources. The submission ZIP is not the release download.

After staging acceptance, create a versioned GitHub Release and upload `dist/Zoomtopia-Setup.zip` and `dist/SHA256SUMS`. Release notes must name tested package versions, macOS versions, publisher, and any restart requirements. Keep the event download link pinned to that release for consistent staging.

`docs/site/index.html` supplies the operator instructions page. The Pages workflow deploys it after merge to `main` (or manual dispatch), once GitHub Pages is configured to use GitHub Actions. It currently says the release is in preparation rather than linking to an unavailable executable. Update that notice and link to the exact approved release when publishing. Point an organization-owned short redirect to the page; domain ownership and shortener credentials are intentionally not assumed.

## Integrity, reruns, and diagnostics

The operator downloads into a private run directory under `~/Library/Caches/com.zoom.zoomtopiasetup`. Downloads use HTTPS, approved redirect hosts, a 2 GB per-package size bound and vendor signature verification. Network interruptions have bounded retries; TLS, policy and integrity failures stop preparation. Cancel is available before authorization. Both installers are downloaded on each online run, including when both installed apps are current; packages are removed when the run ends. Allow at least 8 GB of free space for download and staging. A single-run lock prevents competing preparations.

Before privileged execution, the app reads its running-process identity from the Security framework, copies its complete bundle into private root-owned storage, and verifies the snapshot against that exact running CDHash. The helper copies only manifest-approved resources and both packages into a second private directory, verifies their vendor signatures and signed versions again, and creates a root-owned per-run catalog before Bash uses them. The user cannot supply a replacement vendor identity or application path. Another root-level lock prevents concurrent installations across users. Temporary privileged copies are removed after completion; a process killed forcibly may leave a private temporary directory for administrator cleanup.

Bootstrap events are written to the operator-owned status file; persistent diagnostics go to `/var/log/zoomtopia-setup.log`. Successful installation hashes live under `/var/db/com.zoom.zoomtopiasetup`. Existing Desktop collisions are preserved. Warnings block final readiness until resolved and the run succeeds. For conservative restart handling, any software-update installation records the current boot session and requires a restart, even if that particular update might not strictly require one. A same-boot rerun cannot clear the requirement; a new boot and clean update check can.

## Staging acceptance still required

Test a real browser download on clean Intel and Apple Silicon staging Macs and each supported macOS version. Exercise first-launch quarantine/translocation, authorization denial, offline/missing packages, proxy/TLS failure, bad hashes/signatures, cancellation, interruption, reruns, profile collisions and pending restarts. Confirm the four-check gate and actual camera/microphone/screen/audio behavior.

Corporate IT must allow execution and the actual download destinations. The current package hosts are `dl.google.com`, `zoom.us` and `cdn.zoom.us`; GitHub release asset redirects and Apple's trust/notarization services also need to work. Measure staging bandwidth: the current two packages total approximately 647 MB per online run on each Mac (about 142 GB for 220 Macs), excluding app downloads and OS updates. A corporate/on-site HTTPS mirror can be added as an explicitly approved catalog source if needed.

The architecture and original rationale are in [Web distribution scope](docs/web-distribution-scope.md).
