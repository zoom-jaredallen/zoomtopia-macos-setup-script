import Foundation
let ready = URL(fileURLWithPath: CommandLine.arguments[1])
let proceed = CommandLine.arguments[2]
try Data().write(to: ready)
let deadline = Date().addingTimeInterval(10)
while !FileManager.default.fileExists(atPath: proceed), Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
do { print(try SigningIdentity.runningRequirement()) }
catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
