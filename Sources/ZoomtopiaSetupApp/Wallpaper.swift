import AppKit
import Foundation
#if canImport(SetupCore)
import SetupCore
#endif

enum Wallpaper {
    @MainActor static func apply(resources: URL) async throws {
        let configURL = resources.appendingPathComponent("Payload/config/setup-config.json")
        let config = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any]
        guard let name = config?["wallpaperFilename"] as? String, !name.contains("/") else {
            throw SetupFailure("Wallpaper configuration is invalid")
        }
        let manifest = try ResourceManifest.load(resources)
        guard let entry = manifest.files.first(where: { $0.path == "assets/" + name }) else { throw SetupFailure("Wallpaper is not in the signed manifest") }
        let image = URL(fileURLWithPath: "/Library/Desktop Pictures/Zoomtopia-" + name)
        guard try SafeFiles.hash(image, maxBytes: entry.size) == entry.sha256 else {
            throw SetupFailure("Installed wallpaper needs repair. Run full setup to install the verified image.")
        }
        let screens = NSScreen.screens
        guard !screens.isEmpty else { throw SetupFailure("No displays are available; reconnect a display and retry") }
        for screen in screens {
            try NSWorkspace.shared.setDesktopImageURL(image, for: screen, options: [:])
        }
        // AppKit can return before the wallpaper service publishes its new image URL.
        // Set every display once, then yield the main actor while checking completion.
        let confirmed = try await waitForConfirmation {
            screens.allSatisfy { NSWorkspace.shared.desktopImageURL(for: $0)?.standardizedFileURL == image.standardizedFileURL }
        }
        guard confirmed else {
            throw SetupFailure("macOS did not confirm the wallpaper on every connected display; retry wallpaper")
        }
    }

    @MainActor static func waitForConfirmation(attempts: Int = 21, interval: UInt64 = 150_000_000,
                                               readback: () -> Bool) async throws -> Bool {
        for attempt in 0..<max(0, attempts) {
            try Task.checkCancellation()
            if readback() { return true }
            if attempt + 1 < attempts { try await Task.sleep(nanoseconds: interval) }
        }
        return false
    }
}
