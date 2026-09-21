# Zoom privacy permissions

Without MDM, macOS requires a person to approve privacy-sensitive access. If your organization has a tested, signed configuration profile, place it here as `ZoomPrivacy.mobileconfig`.

Do not copy a PPPC profile from an untrusted source. Its bundle identifier, Team ID, and designated code requirement must match the exact signed Zoom application being deployed. Test it on every supported macOS release. The app copies the profile to the target user's Desktop and opens it; the user still has to approve installation and any permissions macOS reserves for user consent.

If no profile is supplied, the setup app reports this step as requiring manual action. Approve Zoom Workplace under System Settings → Privacy & Security for Camera, Microphone, and Screen & System Audio Recording.
