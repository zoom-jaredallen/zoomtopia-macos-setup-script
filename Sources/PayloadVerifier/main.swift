import Foundation
import Darwin
#if canImport(SetupCore)
import SetupCore
#endif

let resources = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
let args = Array(CommandLine.arguments.dropFirst())
let ids = ["validate", "payload", "chrome", "zoom", "zoom-config", "trackpad", "wallpaper", "aliases", "privacy", "updates", "verify"]

func appendStatus(_ path: String, data: Data) throws {
    let fd = open(path, O_WRONLY | O_APPEND | O_NOFOLLOW | O_NONBLOCK)
    guard fd >= 0 else { throw SetupFailure("Cannot open status file") }
    let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    var info = stat(), console = stat()
    guard fstat(fd, &info) == 0, stat("/dev/console", &console) == 0,
          (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1, info.st_uid == console.st_uid else {
        throw SetupFailure("Unsafe status file")
    }
    try file.write(contentsOf: data)
}
func event(_ path: String, id: String, state: String, detail: String) {
    let index = (ids.firstIndex(of: id) ?? 0) + 1
    let object: [String: Any] = ["id": id, "title": id == "payload" ? "Verify prepared payload" : id == "validate" ? "Validate Mac" : "Final verification", "state": state, "detail": detail, "index": index, "total": 11]
    if var data = try? JSONSerialization.data(withJSONObject: object) { data.append(10); try? appendStatus(path, data: data) }
}
func runSetup(source: URL, status: String) throws -> Int32 {
    guard geteuid() == 0 else { throw SetupFailure("Installation requires administrator authorization") }
    let lock = try RunLock(url: URL(fileURLWithPath: "/var/run/com.zoom.zoomtopiasetup.lock"))
    defer { withExtendedLifetime(lock) {} }
    event(status, id: "validate", state: "running", detail: "Checking user, power, and signed resources")
    let app = resources.deletingLastPathComponent().deletingLastPathComponent()
    let (signatureStatus, _) = try Command.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    guard signatureStatus == 0 else { throw SetupFailure("Setup application signature is invalid") }
    let (_, user) = try Command.run("/usr/bin/stat", ["-f", "%Su", "/dev/console"])
    guard !["root", "loginwindow", ""].contains(user.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw SetupFailure("Log into the student account before setup") }
    let config = try JSONSerialization.jsonObject(with: Data(contentsOf: resources.appendingPathComponent("Payload/config/setup-config.json"))) as? [String: Any]
    if config?["requireACPower"] as? Bool != false {
        let (powerStatus, power) = try Command.run("/usr/bin/pmset", ["-g", "batt"])
        guard powerStatus == 0, power.contains("AC Power") else { throw SetupFailure("Connect this Mac to AC power and retry") }
    }
    var template = Array("/private/var/tmp/zoomtopia-root.XXXXXX".utf8CString)
    guard let path = mkdtemp(&template) else { throw SetupFailure("Cannot create root-owned staging directory") }
    let stage = URL(fileURLWithPath: String(cString: path))
    defer { try? FileManager.default.removeItem(at: stage) }
    event(status, id: "validate", state: "passed", detail: "Administrator authorization and preflight passed")
    event(status, id: "payload", state: "running", detail: "Copying and verifying approved files in private storage")
    try PayloadStager.stage(resources: resources, source: source, destination: stage)
    event(status, id: "payload", state: "passed", detail: "Approved resources and vendor packages verified")
    return try Command.run("/bin/bash", [resources.appendingPathComponent("bootstrap.sh").path, "--payload", stage.path, "--status", status, "--resources", resources.path]).0
}

do {
    switch args.first {
    case "--event":
        guard args.count == 3 else { throw SetupFailure("Invalid event arguments") }
        try appendStatus(args[1], data: Data((args[2] + "\n").utf8))
    case "--decision":
        guard args.count == 2 else { throw SetupFailure("Missing package ID") }
        let catalog = try PackageCatalog.load(resources.appendingPathComponent("package-catalog.json"))
        guard let spec = catalog.packages.first(where: { $0.id == args[1] }) else { throw SetupFailure("Unknown package") }
        switch try PackageVerifier.decision(spec) {
        case .skip: print("skip")
        case .install: print("install")
        case .blocked: throw SetupFailure("\(spec.name) version is newer than the approved release; it was preserved")
        }
    case "--verify-apps":
        for spec in try PackageCatalog.load(resources.appendingPathComponent("package-catalog.json")).packages {
            guard try PackageVerifier.decision(spec) == .skip else { throw SetupFailure("\(spec.name) is not the approved version") }
        }
    case "--verify-package":
        guard args.count == 3 else { throw SetupFailure("Expected ID and path") }
        let catalog = try PackageCatalog.load(resources.appendingPathComponent("package-catalog.json"))
        guard let spec = catalog.packages.first(where: { $0.id == args[1] }) else { throw SetupFailure("Unknown package") }
        try PackageVerifier.verify(URL(fileURLWithPath: args[2]), spec: spec)
    case "--validate-resources":
        _ = try PackageCatalog.load(resources.appendingPathComponent("package-catalog.json"))
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: target) }
        try ResourceManifest.load(resources).copy(from: resources.appendingPathComponent("Payload"), to: target)
        print("Catalog and bundled resources verified")
    case "--run":
        guard args.count == 3 else { throw SetupFailure("Expected prepared payload and status file") }
        exit(try runSetup(source: URL(fileURLWithPath: args[1]), status: args[2]))
    default: throw SetupFailure("Unknown verifier operation")
    }
} catch {
    let message = error.localizedDescription
    fputs(message + "\n", stderr)
    if args.first == "--run", args.count == 3 {
        for id in ids { event(args[2], id: id, state: id == "verify" ? "failed" : "skipped", detail: message) }
        if geteuid() == 0 {
            let fd = open("/var/log/zoomtopia-setup.log", O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_NONBLOCK, 0o644)
            if fd >= 0 {
                let log = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                var info = stat()
                if fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == 0, info.st_nlink == 1 {
                    try? log.write(contentsOf: Data(("Preparation failed: " + message + "\n").utf8))
                }
            }
        }
    }
    exit(1)
}
