import AppKit
import ScreenSaver
import Darwin

@objc(DailyOrbitScreenSaverView)
public final class DailyOrbitScreenSaverView: ScreenSaverView {
    private var picture: NSImage?
    private var title = "Daily Orbit"
    private var credit = "Open Daily Orbit to download your first picture."
    private var date = ""
    private var lastRead = Date.distantPast
    private var start = Date()
    private var filename = ""

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 24.0
        readPicture()
    }
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        animationTimeInterval = 1.0 / 24.0
        readPicture()
    }
    public override func startAnimation() {
        start = Date()
        readPicture()
        super.startAnimation()
    }
    public override func animateOneFrame() {
        if Date().timeIntervalSince(lastRead) > 60 { readPicture() }
        needsDisplay = true
    }
    private func readPicture() {
        lastRead = Date()
        // The system hosts .saver bundles in another process. Resolve the real user
        // home instead of that host process's possible container home directory.
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        let root = URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("Library/Application Support/Daily Orbit", isDirectory: true)
        let store = OrbitStore(root: root)
        guard let snapshot = store.load() else { return }
        guard snapshot.imageFilename != filename || picture == nil else { return }
        guard let image = NSImage(contentsOf: store.imageURL(for: snapshot)) else { return }
        picture = image
        filename = snapshot.imageFilename
        title = snapshot.image.title.orbitPlainText
        date = snapshot.image.date
        credit = (snapshot.image.credit ?? snapshot.image.copyright ?? "NASA APOD").orbitPlainText
    }
    public override func draw(_ rect: NSRect) {
        NSColor.black.setFill(); bounds.fill()
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if let picture, picture.size.width > 0, picture.size.height > 0 {
            let t = reducedMotion ? 0 : Date().timeIntervalSince(start)
            let zoom = reducedMotion ? 1 : 1.035 + 0.025 * sin(t / 28)
            let scale = max(bounds.width / picture.size.width, bounds.height / picture.size.height) * zoom
            let width = picture.size.width * scale
            let height = picture.size.height * scale
            let dx = (width - bounds.width) * (0.5 + (reducedMotion ? 0 : 0.18 * sin(t / 38)))
            let dy = (height - bounds.height) * (0.5 + (reducedMotion ? 0 : 0.18 * cos(t / 43)))
            picture.draw(in: NSRect(x: -dx, y: -dy, width: width, height: height), from: .zero, operation: .sourceOver, fraction: 1)
        }
        guard !isPreview || picture == nil else { return }
        let margin = min(60, bounds.width * 0.05)
        NSGradient(starting: NSColor.black.withAlphaComponent(0.65), ending: .clear)?
            .draw(in: NSRect(x: 0, y: 0, width: bounds.width, height: min(280, bounds.height * 0.4)), angle: 90)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let titleSize = max(12, min(30, bounds.width / 45))
        (title as NSString).draw(in: NSRect(x: margin, y: margin + 32, width: bounds.width - margin * 2, height: titleSize * 1.5), withAttributes: [
            .font: NSFont.systemFont(ofSize: titleSize, weight: .medium), .foregroundColor: NSColor.white, .paragraphStyle: paragraph
        ])
        ((date.isEmpty ? "" : date + "  ·  ") + credit as NSString).draw(in: NSRect(x: margin, y: margin, width: bounds.width - margin * 2, height: 28), withAttributes: [
            .font: NSFont.systemFont(ofSize: max(9, titleSize * 0.45)), .foregroundColor: NSColor.white.withAlphaComponent(0.7), .paragraphStyle: paragraph
        ])
    }
}
