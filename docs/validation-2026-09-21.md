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
