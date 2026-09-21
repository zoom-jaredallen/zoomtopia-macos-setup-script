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
        let validNames = Set(catalog.packages.map { $0.sha256 + ".pkg" }).union(["setup.lock"])
        for url in try fm.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil) where !validNames.contains(url.lastPathComponent) {
            let name = url.lastPathComponent
            // Delete only artifacts this component owns, never arbitrary files in the directory.
            if name.range(of: "^[a-f0-9]{64}\\.pkg$|^[A-Fa-f0-9-]{36}\\.partial$|^run-[A-Fa-f0-9-]{36}$", options: .regularExpression) != nil {
                try fm.removeItem(at: url)
            }
        }
        let destination = cache.appendingPathComponent("run-\(UUID().uuidString)")
        try fm.createDirectory(at: destination.appendingPathComponent("Installers"), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let prepared = PreparedPayload(url: destination, lock: lock)
        for spec in catalog.packages {
            try Task.checkCancellation()
            progress(spec.id, "Checking installed \(spec.name)", 0)
            switch try PackageVerifier.decision(spec) {
            case .skip: progress(spec.id, "Approved version already installed", 1); continue
            case .blocked: throw SetupFailure("\(spec.name) is newer than this release's approved version. It was preserved; ask the staging administrator to approve it.")
            case .install: break
            }
            let cached = cache.appendingPathComponent(spec.sha256 + ".pkg")
            if fm.fileExists(atPath: cached.path), (try? PackageVerifier.verify(cached, spec: spec)) == nil {
                try fm.removeItem(at: cached)
            }
            if !fm.fileExists(atPath: cached.path) {
                let available = try cache.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
                guard available >= spec.size * 3 + 2_000_000_000 else { throw SetupFailure("Free at least \((spec.size * 3 + 2_000_000_000) / 1_000_000_000 + 1) GB on this Mac before setup") }
                if let offline {
                    let architectureSpecific = try SafeFiles.child("Installers/\(spec.filename.replacingOccurrences(of: ".pkg", with: "-\(Hardware.architecture).pkg"))", in: offline)
                    let universal = try SafeFiles.child("Installers/\(spec.filename)", in: offline)
                    let input = fm.fileExists(atPath: architectureSpecific.path) ? architectureSpecific : universal
                    try SafeFiles.copyVerified(from: input, to: cached, sha256: spec.sha256, maxBytes: spec.size)
                } else {
                    var attempt = 1
                    while true {
                        try Task.checkCancellation()
                        let partial = cache.appendingPathComponent("\(UUID().uuidString).partial")
                        defer { try? fm.removeItem(at: partial) }
                        do {
                            progress(spec.id, "Downloading \(spec.name) \(spec.version) (attempt \(attempt)/3)", 0)
                            try await PackageDownload(spec: spec, destination: partial) { fraction in
                                progress(spec.id, "Downloading \(spec.name) \(Int(fraction * 100))%", fraction)
                            }.run()
                            try Task.checkCancellation()
                            try PackageVerifier.verify(partial, spec: spec)
                            try fm.moveItem(at: partial, to: cached)
                            break
                        } catch {
                            guard DownloadPolicy.shouldRetry(error, attempt: attempt) else { throw error }
                            attempt += 1
                            try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                        }
                    }
                }
            }
            try PackageVerifier.verify(cached, spec: spec)
            try Task.checkCancellation()
            try SafeFiles.copyVerified(from: cached, to: destination.appendingPathComponent("Installers/\(spec.filename)"), sha256: spec.sha256, maxBytes: spec.size)
            progress(spec.id, "Verified \(spec.name) \(spec.version)", 1)
        }
        return prepared
    }
}
