import AppKit

final class App: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let cream = NSColor(srgbRed: 243 / 255, green: 240 / 255, blue: 232 / 255, alpha: 1)
        // Sit above normal apps, below the nook (statusBar + 8).
        let level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 4)
        for screen in NSScreen.screens {
            let window = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.level = level
            window.isOpaque = true
            window.backgroundColor = cream
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
