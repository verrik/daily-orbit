import AppKit
let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for name in ["icon_64x64.png", "icon_64x64@2x.png"] {
    try? FileManager.default.removeItem(at: URL(fileURLWithPath: directory).appendingPathComponent(name))
}
var iconChunks = Data()
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 1024, height: 1024), xRadius: 220, yRadius: 220)
    NSGradient(starting: NSColor(red: 0.07, green: 0.13, blue: 0.24, alpha: 1), ending: NSColor(red: 0.015, green: 0.03, blue: 0.08, alpha: 1))!.draw(in: background, angle: 50)
    NSGraphicsContext.saveGraphicsState()
    let rotation = NSAffineTransform(); rotation.translateX(by: 512, yBy: 512); rotation.rotate(byDegrees: 34); rotation.translateX(by: -512, yBy: -512); rotation.concat()
    let orbit = NSBezierPath(ovalIn: NSRect(x: 115, y: 310, width: 794, height: 404)); orbit.lineWidth = 18
    NSColor(red: 0.61, green: 0.8, blue: 1, alpha: 0.85).setStroke(); orbit.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let planet = NSBezierPath(ovalIn: NSRect(x: 300, y: 300, width: 424, height: 424))
    NSGradient(starting: NSColor(red: 0.68, green: 0.84, blue: 1, alpha: 1), ending: NSColor(red: 0.16, green: 0.35, blue: 0.62, alpha: 1))!.draw(in: planet, angle: -60)
    NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: 783, y: 657, width: 40, height: 40)).fill()
    let star = NSBezierPath(); star.move(to: NSPoint(x: 264,y: 776)); star.line(to: NSPoint(x: 279,y: 733)); star.line(to: NSPoint(x: 322,y: 718)); star.line(to: NSPoint(x: 279,y: 703)); star.line(to: NSPoint(x: 264,y: 660)); star.line(to: NSPoint(x: 249,y: 703)); star.line(to: NSPoint(x: 206,y: 718)); star.line(to: NSPoint(x: 249,y: 733)); star.close(); star.fill()
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    if let type = [128: "ic07", 256: "ic08", 512: "ic09", 1024: "ic10"][size] {
        iconChunks.append(contentsOf: type.utf8)
        var length = UInt32(data.count + 8).bigEndian
        iconChunks.append(withUnsafeBytes(of: &length) { Data($0) })
        iconChunks.append(data)
    }
    if [16, 32, 128, 256, 512].contains(size) { try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("icon_\(size)x\(size).png")) }
    if [32, 64, 256, 512, 1024].contains(size) { try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("icon_\(size/2)x\(size/2)@2x.png")) }
}
var icon = Data("icns".utf8)
var length = UInt32(iconChunks.count + 8).bigEndian
icon.append(withUnsafeBytes(of: &length) { Data($0) })
icon.append(iconChunks)
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
