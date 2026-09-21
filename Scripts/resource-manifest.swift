import Foundation
import CryptoKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
var entries: [[String: Any]] = []
let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])!
for case let url as URL in enumerator {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard values.isSymbolicLink != true else { fatalError("Resource symlinks are forbidden") }
    if values.isRegularFile == true {
        let data = try Data(contentsOf: url)
        entries.append(["path": String(url.path.dropFirst(root.path.count + 1)), "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), "size": data.count])
    }
}
entries.sort { ($0["path"] as! String) < ($1["path"] as! String) }
try JSONSerialization.data(withJSONObject: ["files": entries], options: [.prettyPrinted, .sortedKeys]).write(to: output)
