// A paper-coloured backdrop for the PlaygroundNook captures.
//
// Scripts/reel-backdrop.swift sits *above* normal app windows (statusBar + 4)
// because the ShowcaseNook captures only ever have the nook on camera. The
// playground shot needs the controls window too, and that is an ordinary
// window, so a backdrop at that level would cover the subject. This one sits
// one level *below* normal windows instead: it hides the desktop and the
// wallpaper, while the controls window and the nook stay in front of it.
//
// It paints the README paper (#EAF1F8) rather than the recording cream, so the
// clip needs no colour key: what is recorded is already the surface the README
// composites its stills onto. Keep this colour and `paper` in
// make-readme-media.sh in step.
//
// Usage: playground-backdrop   (runs until killed)

import AppKit

final class App: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let paper = NSColor(srgbRed: 234 / 255, green: 241 / 255, blue: 248 / 255, alpha: 1)
        // One below .normal: over the wallpaper and the desktop icons, under
        // every ordinary window, including the playground's controls window.
        let level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        for screen in NSScreen.screens {
            let window = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.level = level
            window.isOpaque = true
            window.backgroundColor = paper
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
