import AppKit

enum WallpaperFit: String, Codable, CaseIterable {
    case fill = "Fill screen"
    case fit = "Fit image"
}

struct WallpaperBackup: Codable {
    let displayID: String
    let path: String
    let scaling: Int?
    let clipping: Bool?
}

@MainActor
enum Desktop {
    static func displayID(_ screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? "main"
    }

    static func apply(_ image: URL, fit: WallpaperFit, store: OrbitStore) throws -> Int {
        guard !NSScreen.screens.isEmpty else { throw OrbitError.message("No connected display was found.") }
        let backupURL = store.root.appendingPathComponent("previous-wallpapers.json")
        var backups = (try? JSONDecoder().decode([WallpaperBackup].self, from: Data(contentsOf: backupURL))) ?? []
        for screen in NSScreen.screens where !backups.contains(where: { $0.displayID == displayID(screen) }) {
            if let previous = NSWorkspace.shared.desktopImageURL(for: screen), previous != image {
                let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
                backups.append(WallpaperBackup(displayID: displayID(screen), path: previous.path,
                    scaling: (options[.imageScaling] as? NSNumber)?.intValue, clipping: options[.allowClipping] as? Bool))
            }
        }
        try FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true)
        try JSONEncoder().encode(backups).write(to: backupURL, options: .atomic)
        var count = 0
        for screen in NSScreen.screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(image, for: screen, options: [
                    .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                    .allowClipping: fit == .fill,
                    .fillColor: NSColor.black
                ])
                count += 1
            } catch {
                throw OrbitError.message("Updated \(count) of \(NSScreen.screens.count) displays. \(error.localizedDescription)")
            }
        }
        return count
    }

    static func restore(store: OrbitStore) throws {
        let url = store.root.appendingPathComponent("previous-wallpapers.json")
        guard let data = try? Data(contentsOf: url),
              let backups = try? JSONDecoder().decode([WallpaperBackup].self, from: data), !backups.isEmpty else {
            throw OrbitError.message("There is no previous wallpaper saved yet.")
        }
        var restored = Set<String>()
        for screen in NSScreen.screens {
            guard let backup = backups.first(where: { $0.displayID == displayID(screen) }) else { continue }
            let image = URL(fileURLWithPath: backup.path)
            guard FileManager.default.fileExists(atPath: image.path) else {
                throw OrbitError.message("Your previous image has moved. Choose a wallpaper in System Settings.")
            }
            var options = [NSWorkspace.DesktopImageOptionKey: Any]()
            if let scaling = backup.scaling { options[.imageScaling] = scaling }
            if let clipping = backup.clipping { options[.allowClipping] = clipping }
            try NSWorkspace.shared.setDesktopImageURL(image, for: screen, options: options)
            restored.insert(backup.displayID)
        }
        guard !restored.isEmpty else { throw OrbitError.message("Connect the display that has a saved wallpaper first.") }
        let remaining = backups.filter { !restored.contains($0.displayID) }
        if remaining.isEmpty { try FileManager.default.removeItem(at: url) }
        else { try JSONEncoder().encode(remaining).write(to: url, options: .atomic) }
    }
}
