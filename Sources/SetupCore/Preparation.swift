import Foundation

public final class PreparedPayload {
    public let url: URL
    private let lock: RunLock
    init(url: URL, lock: RunLock) { self.url = url; self.lock = lock }
    deinit { try? FileManager.default.removeItem(at: url) }
}

public enum PayloadPreparation {
    public static func prepare(resources: URL, offline: URL?, progress: @escaping @Sendable (String, String, Double) -> Void) async throws -> PreparedPayload {
        let fm = FileManager.default
        let cache = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("com.zoom.zoomtopiasetup")
        try fm.createDirectory(at: cache, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let attributes = try fm.attributesOfItem(atPath: cache.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw SetupFailure("Setup cache is not a private directory owned by this user") }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cache.path)
        let lock = try RunLock(url: cache.appendingPathComponent("setup.lock"))
        let catalog = try PackageCatalog.load(resources.appendingPathComponent("package-catalog.json"))
        // The lock makes these artifacts stale; normal deinit cannot clean up a killed process.
        for entry in try fm.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil) {
            if entry.lastPathComponent.range(of: "^[a-f0-9]{64}\\.pkg$|^[A-Fa-f0-9-]{36}\\.partial$|^run-[A-Fa-f0-9-]{36}$", options: .regularExpression) != nil {
                try fm.removeItem(at: entry)
            }
        }
        let destination = cache.appendingPathComponent("run-\(UUID().uuidString)")
        try fm.createDirectory(at: destination.appendingPathComponent("Installers"), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let prepared = PreparedPayload(url: destination, lock: lock)
        for spec in catalog.packages {
            try Task.checkCancellation()
            let output = destination.appendingPathComponent("Installers/\(spec.filename)")
            let available = try cache.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
            guard available >= 8_000_000_000 else { throw SetupFailure("Free at least 8 GB on this Mac before setup") }
            let resolved: PackageSpec
            if let offline {
                let architectureSpecific = try SafeFiles.child("Installers/\(spec.filename.replacingOccurrences(of: ".pkg", with: "-\(Hardware.architecture).pkg"))", in: offline)
                let universal = try SafeFiles.child("Installers/\(spec.filename)", in: offline)
                let input = fm.fileExists(atPath: architectureSpecific.path) ? architectureSpecific : universal
                try SafeFiles.copyVerified(from: input, to: output, sha256: spec.sha256, maxBytes: spec.size)
                try PackageVerifier.verify(output, spec: spec)
                resolved = spec
            } else {
                var attempt = 1
                while true {
                    try Task.checkCancellation()
                    do {
                        progress(spec.id, "Checking latest \(spec.name): downloading signed installer (attempt \(attempt)/3)", 0)
                        try await PackageDownload(spec: spec, destination: output, latest: true) { fraction in
                            progress(spec.id, "Checking latest \(spec.name): \(Int(fraction * 100))%", fraction)
                        }.run()
                        break
                    } catch {
                        try? fm.removeItem(at: output)
                        guard DownloadPolicy.shouldRetry(error, attempt: attempt) else { throw error }
                        attempt += 1
                        try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                    }
                }
                resolved = try LatestPackage.resolve(output, trusted: spec)
            }
            try Task.checkCancellation()
            let installed = try PackageVerifier.installedVersion(resolved)
            let decision = try PackagePolicy.decision(installed: installed, approved: resolved.version)
            let scope = offline == nil ? "current vendor" : "offline approved"
            progress(spec.id, decision == .skip
                     ? "Installed \(installed ?? resolved.version) meets \(scope) version \(resolved.version); no upgrade needed"
                     : "Verified \(scope) version \(resolved.version); ready to \(installed == nil ? "install" : "upgrade")", 1)
        }
        return prepared
    }
}
