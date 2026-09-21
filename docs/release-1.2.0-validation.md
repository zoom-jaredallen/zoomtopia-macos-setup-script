# Version 1.2.0 (build 3) validation

Release source: `e553bcc7dc12705e6de2608e6610084b5d78c936`. Documentation updates after that commit do not change the release binary.

ZIP SHA-256: `f7c9296f30badf71d847cceb4e8b7f4934bd9af033a332c366e60f318cac3414`.

## Verified on 2026-09-21

- Developer ID signature: Jared Allen, team `3U87MZTYPX`; hardened runtime, secure timestamp and Intel/Apple Silicon executable slices.
- Apple notarization accepted submission `862bf21a-04fd-4e61-8dd5-47a63eaad460`; ticket stapled and validated. Gatekeeper accepts the app as Notarized Developer ID.
- Two operator downloads from the draft GitHub release through Chrome matched the ZIP checksum and retained browser quarantine.
- Finder/Archive Utility extraction preserved quarantine; extracted signature and stapled ticket validated.
- The downloaded app launched under macOS App Translocation on Apple Silicon, macOS 26.6.2 (25G83). Its running CDHash matched the signed release. No quarantine removal or security bypass was used.
- Source tests and universal build checks passed before signing. Earlier development-build tests exercised actual Chrome upgrades, current-app skips, wallpaper application and visible OS update handoff.

## Coverage still outstanding

- Full provisioning and final readiness from this exact downloaded signed build. A name-based UI lookup opened an older development copy during the attempted run; that run is excluded from release qualification. The exact downloaded app was subsequently launched, but the UI-control tool could not attach to its translocated window.
- Actual Zoom camera, microphone, speaker and screen-sharing confirmations for this release; fresh privacy-consent behavior on a clean Mac.
- Clean Intel Macs, other supported macOS versions, and representative event-network/fleet testing.
- Restart completion and revalidation on this test Mac, which previously had a same-major OS update pending.

The maintainer requested publication with these limitations recorded. This release is available for staging and evaluation; publication and notarization do not establish that every lab Mac is ready.
