import Foundation
import CryptoKit
import Darwin

public enum SafeFiles {
    public static func validateRelativePath(_ path: String) throws {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw SetupFailure("Unsafe payload path: \(path)")
        }
    }
    public static func child(_ path: String, in root: URL) throws -> URL {
        try validateRelativePath(path)
        var result = root
        for component in path.split(separator: "/") {
            result.appendPathComponent(String(component))
            var info = stat()
            if lstat(result.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFLNK {
                throw SetupFailure("Symbolic links are not permitted in the payload: \(path)")
            }
        }
        return result
    }
    public static func hash(_ url: URL, maxBytes: Int64 = 2_000_000_000) throws -> String {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw SetupFailure("Cannot safely open \(url.lastPathComponent)") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size <= maxBytes else {
            throw SetupFailure("Not a regular file or file too large: \(url.lastPathComponent)")
        }
        var digest = SHA256(); var count: Int64 = 0
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            count += Int64(data.count)
            guard count <= maxBytes else { throw SetupFailure("File exceeds approved size") }
            digest.update(data: data)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func copyVerified(from source: URL, to destination: URL, sha256: String, maxBytes: Int64) throws {
        let input = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard input >= 0 else { throw SetupFailure("Cannot safely open \(source.lastPathComponent)") }
        let reader = FileHandle(fileDescriptor: input, closeOnDealloc: true)
        var info = stat()
        guard fstat(input, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size <= maxBytes else {
            throw SetupFailure("Invalid input type or size: \(source.lastPathComponent)")
        }
        let output = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard output >= 0 else { throw SetupFailure("Cannot create private staged file: \(destination.lastPathComponent)") }
        let writer = FileHandle(fileDescriptor: output, closeOnDealloc: true)
        var success = false
        defer { if !success { try? FileManager.default.removeItem(at: destination) } }
        var digest = SHA256(); var count: Int64 = 0
        while let data = try reader.read(upToCount: 1_048_576), !data.isEmpty {
            count += Int64(data.count)
            guard count <= maxBytes else { throw SetupFailure("File exceeds approved size") }
            digest.update(data: data)
            try writer.write(contentsOf: data)
        }
        try writer.synchronize()
        let actual = digest.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == sha256 else { throw SetupFailure("Checksum mismatch: \(source.lastPathComponent). Obtain the approved payload or a newer setup release.") }
        success = true
    }
}

public enum Command {
    public static func run(_ executable: String, _ arguments: [String]) throws -> (Int32, String) {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = pipe; process.standardError = pipe
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"; process.environment = environment
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
