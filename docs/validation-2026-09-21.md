# Web distribution validation — 2026-09-21

## Completed

- Final development build contains both `x86_64` and `arm64` in the app and verifier; strict bundle/signature, plist, and resource-manifest checks pass. Release packaging correctly rejects the unstapled development app.

- Official Chrome 153.0.8010.53 and Zoom IT Admin 7.2.0.88195 downloaded without installing. Trusted Apple vendor installer signatures, SHA-256, package metadata, minimum macOS versions, and universal app architectures inspected.
- Extracted Chrome and Zoom app signatures verified against their expected bundle identifiers and vendor Team IDs.
- Real Foundation URLSession download of the pinned Chrome package completed and passed the production digest/vendor-signature checks.
- `Scripts/test.sh` passed policy, path/URL validation, digest mismatch/symlink/oversize copy rejection, concurrent lock exclusion, manifest completeness, readiness, TLS failure/cancellation, user-command forwarding, update restart persistence, and launched-executable replacement checks.
- The shell forwarding regression was also run against the baseline implementation and failed as expected.
- Independent review identified two blockers: disk-derived root trust and unsupported restart detection. Fixed with a running-process CDHash requirement and persistent boot-session tracking; regression tests pass.
- Permission preview: ready disabled with zero or three confirmations, enabled with four. Ready screen rendered correctly. No Zoom privacy settings were changed.

## Release qualifications not completed

- `security find-identity -v -p codesigning` returned zero valid identities in the current session. The previous build's certificate identity is not available for signing the new app.
- The documented `zoomtopia-notary` Keychain profile was not found. New executable release was not notarized or published.
- No organization-owned short-link domain/account was provided.
- The Mac locked during UI verification; the final setup-screen check needs an unlocked session.
- Privileged provisioning, actual camera/microphone/screen/audio tests, browser quarantine/translocation on clean machines, and event-network fleet pilot still require authorized staging Macs.

These gaps are release prerequisites, not permission to disable signature checks, Gatekeeper, or privacy controls.

## Current-vendor upgrade follow-up

- Changed installed newer-version policy from blocking to skip; missing/older apps install, equal/newer apps continue without intervention. Tests cover Chrome and Zoom plus the real bootstrap skip path.
- Online mode now downloads current vendor packages on every run and reads version metadata after checking the expected vendor signature. Offline mode remains checksum-pinned and makes no latest-online claim.
- Regression suite passed, including absent/wrong/ambiguous/malformed metadata and package versions below the release minimum.
- Production URLSession downloader fetched both current endpoints successfully; vendor signatures and signed versions resolved to Chrome 153.0.8010.53 and Zoom 7.2.0.88195.
- Production PayloadStager copied both actual packages into an isolated temporary directory, reauthenticated them, generated its catalog, and passed checksum/signature verification of the resulting copies. This test ran without privilege and did not invoke installation.
- Final universal app and verifier build passed; both contain x86_64 and arm64. Strict bundle/signature, plist and resource checks passed.
- Independent review identified abandoned-download cleanup removal; restored recognized stale artifact cleanup under the run lock before the final build.
- No root provisioning or fresh UI inspection was performed for this follow-up. The native workflow and four-check readiness gate remain unchanged. Signing/notarization will be performed on the user's other machine after staging acceptance.
