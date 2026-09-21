import AppKit
import Foundation
#if canImport(SetupCore)
import SetupCore
#endif

enum Wallpaper {
    @MainActor static func apply(resources: URL) throws {
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
        guard !NSScreen.screens.isEmpty else { throw SetupFailure("No displays are available; reconnect a display and retry") }
        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(image, for: screen, options: [:])
            guard NSWorkspace.shared.desktopImageURL(for: screen)?.standardizedFileURL == image.standardizedFileURL else {
                throw SetupFailure("macOS did not confirm the wallpaper on every connected display; retry wallpaper")
            }
        }
    }
}
