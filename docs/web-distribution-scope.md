# Web distribution and online installer acquisition

Date: 2026-09-21
Status: proposed scope; application changes are not implemented.

## Outcome

Prepare approximately 220 temporary Zoomtopia lab Macs without requiring USB access. An operator types a memorable URL, downloads and opens the app, starts setup, authorizes privileged installation once, completes the existing Zoom permission checks, and sees an honest readiness result.

The public GitHub repository stores source and documentation. A future release supplies a signed, notarized app. Creating the repository does not make the current build ready for distribution.

## Recommended operator flow

1. Visit an organization-controlled short HTTPS link that leads to a small download/instructions page.
2. Download the event-approved `Zoomtopia-Setup.zip`, expand it, and open `Zoomtopia Setup.app`. The page explains the normal macOS first-launch confirmation and identifies the publisher. No Terminal commands are required.
3. Click Start Setup. The app checks installed versions, architecture, power, available disk space, and network access; prepares any required installers with visible progress.
4. Enter administrator credentials in the existing macOS authorization dialog once downloads are ready. Credentials stay in the system authorization flow.
5. The privileged bootstrap validates and installs the prepared files, applies configuration, and reports results.
6. Complete Camera, Microphone, Screen & System Audio Recording, and speaker tests. Restart and rerun if required before marking the Mac ready.

Privacy consent, profile installation, and some macOS updates can still require separate interaction. The one-password objective applies to the provisioning authorization, not every possible OS prompt.

## Hosting choices

| Option | Benefits | Trade-offs |
| --- | --- | --- |
| GitHub Releases for app downloads, GitHub Pages for instructions | Recommended default; versioned artifacts, simple public access, source and release history together | IT must permit GitHub and the actual asset redirect destinations |
| Corporate HTTPS hosting for the app and instructions | Fits existing corporate network policy and domain ownership | Requires hosting access and a publishing process |
| Approved on-site HTTPS mirror of the same artifacts | Reduces repeated external downloads during staging | Requires an operated server and approved package redistribution; not necessary for the first version |

Use a stable event link pointing to a specific approved release, not a moving latest-release target during staging. An organization-managed short redirect is preferable to an unrelated URL shortener because IT can approve the domain and the event team can control its destination. Keep the full URL available as a fallback. A short link simplifies typing; it does not change execution permissions.

Serve compiled app downloads as release assets, not as source ZIPs or files committed to Git. GitHub Pages is sufficient for the small instruction page; do not use it as the bulk installer store. No website, short link, or executable release is published by this scoping task.

## Changes by component

| Component | Required change |
| --- | --- |
| `Sources/ZoomtopiaSetupApp/SetupController.swift` | Add preparation state, package policy decisions, cancellation/retry, and a resolved staging directory; replace mandatory sibling-payload lookup for online mode |
| New app-side download/catalog components | Read a bundled approved package catalog; select hardware-appropriate packages; download via URLSession to a private cache with progress, timeouts, bounded retries, and atomic completion |
| `Sources/ZoomtopiaSetupApp/ZoomtopiaSetupApp.swift` | Show download/preparation progress and actionable network failures inside setup; retain setup → permission assistant → ready |
| `Scripts/bootstrap.sh` | Accept a prepared payload, stage it into root-owned storage, revalidate before use, preserve Bash 3.2 and JSONL events, and skip packages that meet the approved policy |
| `ZoomtopiaPayload/config` and new package catalog | Define package version policy, architecture, HTTPS URL, SHA-256, expected vendor signing identity, and installed-app identity/version checks |
| `Scripts/build-app.sh` | Bundle wallpaper, approved configuration, and package catalog inside signed Resources; produce a self-contained app without requiring adjacent files |
| `Scripts/generate-checksums.sh` | Retain optional offline payload support and add release preparation validation; incomplete package catalogs must fail release preparation |
| `Scripts/notarize-app.sh` and release packaging | Notarize, staple, validate, then generate the final downloadable ZIP from the stapled app; publish its SHA-256 and release notes |
| README/operator instructions | Document web setup, short/full URLs, version policy, network requirements, retry behavior, and the remaining manual steps |

Downloaded/quarantined apps may be translocated by macOS, so online mode must use bundle resources and an explicit cache path rather than locating files beside the executable. Never write downloads into the signed app bundle. Preserve an explicit optional local-payload mode for approved offline use.

## When to download Chrome and Zoom

Recommended default: pin tested installer versions and hashes for the event. A maintainer refreshes and tests the catalog before releasing a new setup app. A continuously updated remote catalog is outside the first release scope; it would require authenticated metadata, rollback rules, and separate lifecycle management.

| Detected state | Behavior |
| --- | --- |
| Authentic installed app with an accepted version and architecture | Skip its package download/install; still apply required configuration and run readiness checks |
| Missing or below the approved minimum | Reuse a matching verified cached package, otherwise download the catalog's approved package |
| Newer than the tested range or conflicting managed installation | Preserve it and report a policy decision/action required; do not silently downgrade or replace |
| Cached package has wrong hash, signature, architecture, or version | Reject it; download again only from the approved source |
| Offline with no acceptable installation or verified cached package | Stop the affected operation with a clear retry instruction |

Use Google's official Chrome Enterprise universal PKG. For Zoom use the official IT Admin PKG, selecting Apple Silicon or Intel as appropriate, because this project deploys `us.zoom.config.plist`. Vendor URLs can change; confirm concrete URLs, redirects, signer identities, package contents, and hashes while preparing the catalog. This scope does not assert particular package URLs or versions are ready to deploy.

Google documents a stable latest-package endpoint. Such endpoints are useful for maintainer refreshes but can change bytes at any time: a pinned release must fail on a hash mismatch, never accept a new digest automatically. If an approved vendor version is no longer downloadable, publish a newly tested catalog/app release or use an approved mirror where permitted.

## Download and privilege boundary

- Download as the logged-in operator before requesting administrator authorization, using HTTPS with normal certificate validation and explicit approved redirect destinations.
- Bundle the expected hashes and vendor identities inside the signed app. A checksum computed only after download is an integrity record, not proof the package was approved.
- Validate package signature trust and expected vendor identity, not merely the existence of any valid package signature. Check installed app identity/version when deciding to skip.
- Copy required content into a unique root-owned, non-user-writable staging directory after elevation. Reject symlinks and path traversal; validate the staged copies and execute only those copies. Do not verify a user-writable file and later install it from that same mutable location.
- Preserve persistent successful installation hashes and structured progress. Use bounded cache storage, partial-file cleanup, free-space checks, a single-run lock, and no secrets in logs.
- Distinguish proxy/TLS failure, HTTP failure, timeout, interruption, package mismatch, and installation failure. Never turn these into successful readiness.
- Keep release signing keys and notarization credentials in the maintainer's Keychain or appropriately protected release secrets, outside the public repository.

## Existing behavior to correct in this work

1. `run_as_user` currently forwards the username as part of the command because it does not shift the argument. Correct and test the user-scoped operations.
2. Readiness must require successful provisioning, all four operator checks, and no unresolved blocking restart/action. The permission assistant currently does not independently enforce successful provisioning before entering ready.
3. Bootstrap file installation operations need checked return values before emitting success. Stage a privacy profile without overwriting an unrelated Desktop file.
4. Package signature enforcement must not be disableable in the release configuration. Manifest coverage must include every file actually consumed, rather than checking only whatever files happen to be listed.

These fixes belong with the new distribution path because staging and final readiness must be dependable before offering the app to operators.

## Delivery sequence and acceptance criteria

1. **Public source baseline and scope:** create the repository and publish reviewed source, assets, and this scope. Exclude generated builds, vendor installers, credentials, and local machine metadata.
2. **Preparation and download layer:** catalog, installed-version decisions, verified cache, network progress/retry, resource bundling, and retained optional offline input.
3. **Privileged integration:** root-owned staging and verification, baseline correctness fixes, safe reruns, and readiness gating.
4. **Release delivery:** sign and notarize both architecture slices; validate the stapled app and Gatekeeper acceptance; package and publish a versioned release; add the instruction page and short redirect.
5. **Staging acceptance:** exercise real browser downloads on clean Intel and Apple Silicon staging Macs, including first-launch quarantine/translocation behavior, supported macOS versions, denied authorization, failed downloads, wrong signatures/hashes, interrupted installation, installed/cached packages, reruns, and pending restarts. Confirm existing four-check gating and preview screens. Pilot several Macs in parallel on the event network before fleet staging.

Run the repository's shell syntax, universal build, architecture, bundle, and signature checks after relevant source changes. Unit-test policy decisions and download/error handling with controlled fixtures; exercise root installation only on authorized test Macs.

For capacity planning, measure actual artifact sizes. External package traffic without a shared cache is approximately 220 × the packages each Mac needs, plus app downloads and OS updates. Treat OS updates as a separate staging bandwidth/time decision; the current configuration enables them. Do not change that setting silently.

## Decisions needed before implementation/release

- Confirm GitHub download access and corporate execution policy on representative staging Macs; identify actual redirect/CDN hosts during a test download.
- Choose the organization-controlled short domain/path or shortener account. No domain ownership is assumed.
- Select and test Chrome/Zoom versions and accepted installed-version ranges; confirm supported macOS versions against those actual installers.
- Decide whether an approved on-site mirror is necessary after measuring bandwidth and whether OS updates belong in this staging run.
- Complete notarization and controlled end-to-end testing. Existing Developer ID signing alone is not sufficient for the current downloadable build.

## Primary references

- [GitHub releases and binary assets](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
- [GitHub Pages limits](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits)
- [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple packaging and distribution testing](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)
- [Google Chrome Enterprise Mac installer](https://support.google.com/chrome/a/answer/9020580?hl=en)
- [Google's current-package endpoint](https://support.google.com/chrome/a/answer/9915669?hl=en)
- [Zoom IT Admin deployment for macOS](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0064957)
