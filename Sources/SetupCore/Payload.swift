import Foundation
import Darwin

public final class RunLock {
    private let descriptor: Int32
    public init(url: URL) throws {
        let fd = open(url.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard fd >= 0 else { throw SetupFailure("Cannot create setup lock") }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd); throw SetupFailure("Another setup is running. Close it before retrying.")
        }
        descriptor = fd
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}

public struct ResourceEntry: Codable {
    public let path: String
    public let sha256: String
    public let size: Int64
}
public struct ResourceManifest: Codable {
    public let files: [ResourceEntry]
    public static func load(_ resources: URL) throws -> ResourceManifest {
        let manifest = try JSONDecoder().decode(Self.self, from: Data(contentsOf: resources.appendingPathComponent("resource-manifest.json")))
        try manifest.validate(); return manifest
    }
    public func validate() throws {
        let paths = Set(files.map(\.path))
        guard paths.count == files.count,
              paths.contains("config/setup-config.json"), paths.contains("config/us.zoom.config.plist"), paths.contains("assets/wallpaper.jpg") else {
            throw SetupFailure("Incomplete bundled resource manifest")
        }
        for file in files {
            try SafeFiles.validateRelativePath(file.path)
            guard (file.path.hasPrefix("assets/") || file.path.hasPrefix("config/")),
                  file.sha256.count == 64, file.sha256.allSatisfy(\.isHexDigit), file.size > 0, file.size < 25_000_000 else {
                throw SetupFailure("Invalid resource manifest entry")
            }
        }
    }
    public func copy(from source: URL, to destination: URL) throws {
        for entry in files {
            let input = try SafeFiles.child(entry.path, in: source)
            let output = try SafeFiles.child(entry.path, in: destination)
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try SafeFiles.copyVerified(from: input, to: output, sha256: entry.sha256, maxBytes: entry.size)
        }
        let config = try JSONSerialization.jsonObject(with: Data(contentsOf: destination.appendingPathComponent("config/setup-config.json"))) as? [String: Any]
        for (key, prefix) in [("wallpaperFilename", "assets/"), ("zoomConfigurationFilename", "config/")] {
            guard let name = config?[key] as? String, !name.contains("/"), files.contains(where: { $0.path == prefix + name }) else {
                throw SetupFailure("Configuration references an unapproved resource: \(key)")
            }
        }
        if let name = config?["privacyProfileFilename"] as? String { try SafeFiles.validateRelativePath(name); guard !name.contains("/") else { throw SetupFailure("Invalid profile filename") } }
    }
}

public enum PayloadStager {
    // Destination is created by the privileged caller beneath a private mktemp directory.
    public static func stage(resources: URL, source: URL, destination: URL) throws {
        let catalog = try PackageCatalog.load(resources.appendingPathComponent("package-catalog.json"))
        let manifest = try ResourceManifest.load(resources)
        try manifest.copy(from: resources.appendingPathComponent("Payload"), to: destination)
        let installers = destination.appendingPathComponent("Installers")
        try FileManager.default.createDirectory(at: installers, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        for spec in catalog.packages {
            switch try PackageVerifier.decision(spec) {
            case .skip: continue
            case .blocked: throw SetupFailure("\(spec.name) is newer than the approved version. Existing installation preserved; ask the staging administrator to approve it.")
            case .install:
                let input = try SafeFiles.child("Installers/\(spec.filename)", in: source)
                let output = installers.appendingPathComponent(spec.filename)
                try SafeFiles.copyVerified(from: input, to: output, sha256: spec.sha256, maxBytes: spec.size)
                try PackageVerifier.verify(output, spec: spec)
            }
        }
    }
}
