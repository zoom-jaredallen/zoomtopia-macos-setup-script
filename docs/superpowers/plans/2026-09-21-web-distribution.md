# Web Distribution Implementation Plan

> Execute inline using executing-plans; the user requested implementation of the scoped recommendation.

**Goal:** Run setup from a browser-downloaded app with verified selective vendor downloads and truthful readiness.
**Architecture:** Shared Foundation core owns package policy, SHA-256 and signer verification, staged payload validation and download handling. SwiftUI prepares the payload as the operator; a bundled command-line verifier copies approved bytes to private privileged storage before Bash installs them. A bundled catalog and resource manifest anchor trust.
**Tech Stack:** Swift 5.9, macOS 13+, SwiftUI/AppKit, Foundation URLSession, CryptoKit, Bash 3.2.
**Spec:** docs/web-distribution-scope.md

## Global constraints

Universal x86_64/arm64 build; one provisioning authorization; no unattended reboot; no TCC modifications; preserve unrelated files; no installer packages or credentials in Git; keep offline payload support and existing permission assistant.

## Review focus

- Quarantined/translocated app must resolve resources without adjacent payload.
- Invalid cache, interrupted download, redirected HTTP, or newer installed version must fail safely.
- User-mutable staged files must never be executed by root before copying and verifying.
- Missing events, authorization cancellation, warnings, or pending restart must not reach ready.
- Final ZIP must contain the stapled app, not the pre-notarization submission.

## Tasks

- [x] 1. Shared package policy and validation. Add SetupCore target, catalog models, installed-app inspection, hash/signature checks, strict resources and staging. Write tests for version policy, unsafe paths, modified bytes, symlinks and redirects first; run `swift test` red then green.
- [x] 2. Download preparation. Add URLSession downloader with strict redirect/size/time limits, three attempts for transient errors, cancellation, atomic cache promotion and file lock. Test controlled transport failures and cache invalidation. Inspect real official installers and record pinned hashes, signers, versions and architectures.
- [x] 3. Privileged integration and UI. Add PayloadVerifier CLI; validate selected inputs in private root staging. Correct user command forwarding and file-operation failures. Add setup preparation/retry/cancel state and gate ready on terminal success and four confirmations. Test readiness transitions and shell function behavior without provisioning the host.
- [x] 4. Distribution. Bundle resources/catalog/helper, update checksum/build/notarization scripts, add release packaging validation and a static download instructions page, update README. Run shell syntax and tests before universal build. Verify both slices, signing and plist.
- [x] 5. Development acceptance and review (release qualifications recorded separately). Preview setup/permissions/ready without installing. Obtain independent whole-branch review; fix important findings with regression tests. Commit and publish feature branch/PR. Publish executable only with successful notarization; document staging-Mac acceptance still outstanding.

## Execution record

- Baseline source reviewed; shell syntax previously passed. No existing test target.
- Ruling: proceed with the user's explicit implementation request without another approval round; keep external release prerequisites visible.

- Shared policy/validation, download layer, privileged snapshot/staging, UI integration and distribution tooling implemented. Core tests, TLS-failure/cancellation tests, shell forwarding, executable-replacement and update-restart regression tests pass.
- Ruling: use the observed universal vendor packages for both architectures; fixed approved versions rather than a moving latest policy. Cost: a new Chrome package at its moving URL requires a newly reviewed release.
- Ruling: use a standalone Swift test runner in this Command Line Tools environment because XCTest is unavailable; retain XCTest-compatible test classes for full Xcode.
- Independent review identified mutable-disk trust and restart-state blockers; fixed by running-process Security identity/CDHash and persistent boot-session tracking. Both have regression tests.
- Ruling: conservatively require restart after any software-update installation; cost: some updates incur an extra reboot. No unattended reboot is performed.
- Release prerequisites unavailable in this session: zero valid Developer ID signing identities; no `zoomtopia-notary` Keychain profile; no organization-owned short URL supplied. No executable release published.
- UI permission preview verified zero/three confirmations disabled and four enabled; ready screen rendered. Mac subsequently locked, preventing the remaining setup-screen check.

- Final universal ad-hoc development build, both architecture checks, strict codesign, plist and bundled-resource validation passed. Real URLSession Chrome download smoke passed; release packaging correctly refused unstapled output. See docs/validation-2026-09-21.md for remaining external acceptance.
