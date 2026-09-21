import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

let application = NSApplication.shared
let applicationDelegate = AppDelegate()
application.delegate = applicationDelegate
application.setActivationPolicy(.regular)
application.appearance = NSAppearance(named: .darkAqua)

let content = ContentView()
    .frame(minWidth: 820, minHeight: 700)
let mainWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 900, height: 780),
    styleMask: [.titled, .closable, .miniaturizable, .resizable],
    backing: .buffered,
    defer: false
)
mainWindow.title = "Zoomtopia Setup"
mainWindow.appearance = NSAppearance(named: .darkAqua)
mainWindow.backgroundColor = NSColor(red: 7.0 / 255.0, green: 12.0 / 255.0, blue: 35.0 / 255.0, alpha: 1)
mainWindow.center()
mainWindow.contentView = NSHostingView(rootView: content)
mainWindow.setFrameAutosaveName("ZoomtopiaSetupMainWindow")
mainWindow.isReleasedWhenClosed = false
mainWindow.makeKeyAndOrderFront(nil)
application.activate(ignoringOtherApps: true)
application.run()
