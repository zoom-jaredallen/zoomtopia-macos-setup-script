import Foundation

public struct PackageSpec: Codable {
    public let id: String
    public let name: String
    public let filename: String
    public let version: String
    public let versionKey: String
    public let architectures: [String]
    public let url: URL
    public let allowedHosts: [String]
    public let sha256: String
    public let size: Int64
    public let teamID: String
    public let installerIdentity: String
    public let bundleID: String
    public let applicationPaths: [String]

    public func validate() throws {
        try SafeFiles.validateRelativePath(filename)
        guard ["chrome", "zoom"].contains(id), !filename.contains("/"), filename.hasSuffix(".pkg"),
              sha256.count == 64, sha256.allSatisfy({ $0.isHexDigit && !$0.isUppercase }), size > 0, size < 2_000_000_000,
              teamID.count == 10, teamID.allSatisfy({ $0.isASCII && ($0.isNumber || $0.isUppercase) }),
              installerIdentity.hasPrefix("Developer ID Installer: "), installerIdentity.hasSuffix("(\(teamID))"),
              ["CFBundleVersion", "CFBundleShortVersionString"].contains(versionKey),
              !architectures.isEmpty, Set(architectures).isSubset(of: ["arm64", "x86_64"]),
              !applicationPaths.isEmpty, applicationPaths.allSatisfy({ $0.hasPrefix("/Applications/") && $0.hasSuffix(".app") && !$0.dropFirst(14).contains("/") }),
              bundleID.range(of: "^[A-Za-z0-9.-]+$", options: .regularExpression) != nil,
              DownloadPolicy.allows(url, hosts: allowedHosts) else { throw SetupFailure("Invalid package catalog entry: \(id)") }
        _ = try PackagePolicy.decision(installed: nil, approved: version)
    }
}

public struct PackageCatalog: Codable {
    public let schemaVersion: Int
    public let packages: [PackageSpec]
    public static func load(_ url: URL) throws -> PackageCatalog {
        let catalog = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard catalog.schemaVersion == 1, Set(catalog.packages.map(\.id)) == ["chrome", "zoom"], catalog.packages.count == 2 else {
            throw SetupFailure("Catalog must contain exactly Chrome and Zoom")
        }
        try catalog.packages.forEach { try $0.validate() }
        return catalog
    }
}

public enum Hardware {
    public static var architecture: String {
        var arm: Int32 = 0; var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &arm, &size, nil, 0) == 0, arm == 1 { return "arm64" }
        return "x86_64"
    }
}

public enum PackageVerifier {
    public static func verify(_ url: URL, spec: PackageSpec) throws {
        guard try SafeFiles.hash(url, maxBytes: spec.size) == spec.sha256 else {
            throw SetupFailure("\(spec.name) checksum does not match this setup release. Download a newer setup app or supply the approved package.")
        }
        let (status, output) = try Command.run("/usr/sbin/pkgutil", ["--check-signature", url.path])
        guard status == 0, output.contains("Status: signed by a developer certificate issued by Apple for distribution"),
              output.split(separator: "\n").contains(where: { $0.trimmingCharacters(in: .whitespaces) == "1. \(spec.installerIdentity)" }) else {
            throw SetupFailure("\(spec.name) does not have the expected trusted vendor signature")
        }
    }

    public static func installedVersion(_ spec: PackageSpec, architecture: String = Hardware.architecture) throws -> String? {
        let paths = spec.applicationPaths.filter { FileManager.default.fileExists(atPath: $0) }
        guard paths.count <= 1 else { throw SetupFailure("Multiple \(spec.name) installations found. Ask the staging administrator to resolve them.") }
        guard let path = paths.first else { return nil }
        let app = URL(fileURLWithPath: path)
        guard try app.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw SetupFailure("Application links are not accepted: \(path)") }
        let requirement = "anchor apple generic and identifier \"\(spec.bundleID)\" and certificate leaf[subject.OU] = \"\(spec.teamID)\""
        let (status, _) = try Command.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R", "=" + requirement, path])
        guard status == 0 else { throw SetupFailure("Existing \(spec.name) identity could not be verified; it was preserved.") }
        let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any]
        guard let version = info?[spec.versionKey] as? String, let executable = info?["CFBundleExecutable"] as? String,
              !executable.contains("/"), !executable.isEmpty else { throw SetupFailure("Cannot read installed \(spec.name) version") }
        let (archStatus, archs) = try Command.run("/usr/bin/lipo", ["-archs", app.appendingPathComponent("Contents/MacOS/\(executable)").path])
        guard archStatus == 0, archs.split(whereSeparator: \.isWhitespace).contains(Substring(architecture)) else {
            throw SetupFailure("Existing \(spec.name) does not support this Mac's architecture; it was preserved.")
        }
        return version
    }
    public static func decision(_ spec: PackageSpec) throws -> PackageDecision {
        guard spec.architectures.contains(Hardware.architecture) else { throw SetupFailure("No approved \(spec.name) package for this Mac") }
        return try PackagePolicy.decision(installed: installedVersion(spec), approved: spec.version)
    }
}
