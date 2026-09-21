# Live-test follow-up implementation record

Goal: complete the authorized six-item next-round scope while preserving signed provisioning and explicit operator consent.

Decisions:
- OS update execution moves to Apple's visible Software Update UI. Background checks list only; no unattended install, credential collection or reboot. Available updates are not evidence that restart is pending. The operator can record an actual restart request from macOS; that checkpoint requires a new boot and clean policy check.
- Current-major macOS updates and recommended ancillary updates are required; higher-major upgrades are excluded by default.
- Permission navigation is guided and operator initiated. Probe the installed signed-out Zoom UI; do not add Accessibility permissions or undocumented deep links to production.
- Limited test mode installs/verifies vendor apps only, skips personal configuration and OS updates, and can never claim readiness.
- Recovery provides separate wallpaper and update retries. Stored summaries are informational after relaunch; privileged work must be revalidated by a new run. No restored summary grants readiness.

Work:
- [x] Read-only update policy and regression cases.
- [x] Preflight review; full/limited mode enforced at privileged boundary.
- [x] Native wallpaper application/readback with targeted retry.
- [x] Permission assistant available with unrelated warnings; readiness still strict.
- [x] Guided Zoom settings/tests and signed-out feasibility check.
- [x] Persistent summary, explicit recovery, update/restart checkpoints and progress.
- [x] Tests, universal build, UI previews, independent review and existing PR update.

Validation note: automated checks, universal build, preflight UI and independent review passed. Live limited/full runs requiring macOS credentials are tracked separately in docs/validation-round2.md; no OS installation or reboot is part of automated validation.
