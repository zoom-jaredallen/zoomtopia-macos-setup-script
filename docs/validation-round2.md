# Workflow follow-up validation

## Implemented behavior

- Read-only Software Update checks classify current-major macOS and recommended ancillary updates. Major upgrades are excluded by policy. No background OS installation, credential collection or reboot.
- Native handoff opens Software Update. An operator can explicitly record that macOS requested a restart; readiness requires a new known boot and a clean update-policy check before that checkpoint clears.
- Legacy boot markers are ignored because they were written before authentication in the first implementation.
- Preflight distinguishes full provisioning from limited application installation/testing. The selected enum is checked again by the privileged verifier; limited bootstrap excludes configuration, personal preferences, shortcuts, profile staging and OS checks.
- Native NSWorkspace wallpaper application verifies the root-installed image against the bundled manifest and reads back connected display image URLs. No System Events automation is used.
- Permission assistant entry depends on verified Zoom, independently of unrelated warnings. Unexecuted privileged steps use notRun, distinct from a verified package skip.
- All full-mode requirements and four current operator confirmations are still required for readiness. A restored summary cannot authorize readiness; a new run revalidates the Mac.
- Wallpaper/update retries are independent. Restart checkpoint and summary survive relaunch; no launch agent is installed.

## Automated / development verification

- Swift regression suite passes, including warnings vs permission access, limited-mode readiness denial, restored-state denial, same/previous-boot checkpoint denial, version policy, downloader failure/cancellation, file integrity, and signing identity.
- 19 mocked update-policy cases pass: same-major, major-only, mixed applications/OS, optional offers, legacy markers, malformed/unknown/contradictory listings and command failures. No update installation is invoked.
- Bash syntax and universal build pass. App and verifier contain x86_64 and arm64. Strict bundle signature, Info.plist and resource validation pass.
- Independent review identified and confirmed fixes for the limited-to-full preflight update-check guard and failed preflight being confused with a verified skip.

## UI / environment observations

- Zoom 7.2.0.88195 exposes Settings, Video & effects, Audio, Test microphone and Test speaker while signed out on this Mac. Navigation was inspected without signing in or marking permissions granted. No fresh-permission prompt or microphone/speaker functional outcome is claimed.
- Full and limited preflight views display the distinct effects correctly. Cancel dismisses without starting provisioning.
- Authorized limited run completed: both current applications skipped; configuration, wallpaper, shortcuts and OS checks excluded. Modification times of four configuration/wallpaper/shortcut paths matched the recorded pre-run values. Permission assistant opened and explicitly disabled lab readiness.
- Authorized full run completed: Chrome/Zoom skipped as current; preferences and shortcuts passed; OS checking returned actionRequired without any installation/download invocation.
- Native wallpaper initially set successfully but readback was stale; targeted retry passed. Fixed by applying all displays once and asynchronously checking readback for at most three seconds. New tests cover delayed success, bounded failure and cancellation. Patched retry passed on the Mac; the controlled delayed-readback test covers the timing condition.
- Software Update handoff opened the correct macOS page. It showed Restart Now for Tahoe 26.7 under Other Updates, separate from macOS 27 Upgrade Now. Neither install/restart control was clicked.
- Permission assistant remained accessible despite pending updates; Mark Mac Ready stayed disabled. No operator confirmations were fabricated.
- Reopening the rebuilt app restored the summary with an explicit revalidation requirement. Wallpaper retry worked independently; the update recheck showed a read-only progress state.
- Targeted independent review found no remaining lifecycle/readiness issue in the asynchronous wallpaper fix.

## Remaining release qualifications

Developer ID signing/notarization will be performed on the user's other machine. A genuine OS update/authentication/reboot cycle and fresh camera/microphone/screen/audio grants on representative lab Intel/Apple Silicon machines still require staging acceptance. Mocked update-state tests are not proof of a real OS installation. Multi-Space wallpaper behavior and future display connections also need lab validation.
