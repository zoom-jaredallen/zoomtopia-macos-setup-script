import Foundation

/// The bundle remains the authority for vendor identity and application locations.
/// Only version, digest and byte count are derived from a freshly verified package.
public enum LatestPackage {
    public static func version(distribution: Data, spec: PackageSpec) throws -> String {
        let document = try XMLDocument(data: distribution, options: [.nodeLoadExternalEntitiesNever])
        let bundles = try document.nodes(forXPath: "//bundle[@id='\(spec.bundleID)']")
        let versions = Set(bundles.compactMap { ($0 as? XMLElement)?.attribute(forName: spec.versionKey)?.stringValue })
        guard versions.count == 1, let version = versions.first else {
            throw SetupFailure("Cannot identify the signed \(spec.name) installer version")
        }
        _ = try PackagePolicy.decision(installed: nil, approved: version)
        guard try PackagePolicy.decision(installed: version, approved: spec.version) == .skip else {
            throw SetupFailure("Vendor returned a \(spec.name) package older than this setup release's minimum version")
        }
        return version
    }

    public static func resolve(_ package: URL, trusted spec: PackageSpec) throws -> PackageSpec {
        let digest = try SafeFiles.hash(package)
        try PackageVerifier.verifySignature(package, spec: spec)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let (status, _) = try Command.run("/usr/bin/xar", ["-xf", package.path, "-C", folder.path, "Distribution"])
        guard status == 0 else { throw SetupFailure("Cannot read signed installer metadata") }
        let metadata = try SafeFiles.child("Distribution", in: folder)
        _ = try SafeFiles.hash(metadata, maxBytes: 4_000_000)
        let version = try version(distribution: Data(contentsOf: metadata), spec: spec)
        let size = (try FileManager.default.attributesOfItem(atPath: package.path)[.size] as! NSNumber).int64Value
        let result = PackageSpec(id: spec.id, name: spec.name, filename: spec.filename, version: version, versionKey: spec.versionKey,
                                 architectures: spec.architectures, url: spec.url, allowedHosts: spec.allowedHosts, sha256: digest, size: size,
                                 teamID: spec.teamID, installerIdentity: spec.installerIdentity, bundleID: spec.bundleID, applicationPaths: spec.applicationPaths)
        try result.validate()
        return result
    }
}
