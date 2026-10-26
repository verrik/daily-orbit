import AppKit
import SwiftUI
import ScreenSaver

@main
struct RenderPreview {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let args = CommandLine.arguments
        let model = OrbitModel(store: OrbitStore(root: URL(fileURLWithPath: args[1])))
        guard model.image != nil else { throw OrbitError.message("No cached image for preview") }
        model.status = "Wallpaper set on your display."
        let size = NSSize(width: 1080, height: 820)
        let view = NSHostingView(rootView: OrbitWindow(model: model).preferredColorScheme(.dark).frame(width: size.width, height: size.height))
        view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
        model.page = 1
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        view.layoutSubtreeIfNeeded()
        view.cacheDisplay(in: view.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
        let saverURL = URL(fileURLWithPath: args[4])
        let bundle = Bundle(url: saverURL)!
        try bundle.loadAndReturnError()
        guard let saverClass = bundle.principalClass as? ScreenSaverView.Type,
              let saver = saverClass.init(frame: NSRect(x: 0, y: 0, width: 1280, height: 800), isPreview: false) else {
            throw OrbitError.message("Screen saver bundle failed to load its principal class")
        }
        window.contentView = saver
        let saverRep = saver.bitmapImageRepForCachingDisplay(in: saver.bounds)!
        saver.cacheDisplay(in: saver.bounds, to: saverRep)
        try saverRep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[5]))
        print("Rendered Today, Preferences, and the real screen saver bundle.")
    }
}
