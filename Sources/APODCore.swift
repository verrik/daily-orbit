import Foundation
import ImageIO
import UniformTypeIdentifiers

enum OrbitError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct APOD: Codable, Equatable, Sendable {
    let date: String
    let title: String
    let explanation: String
    let mediaType: String
    let url: String?
    let hdurl: String?
    let permalink: String?
    let credit: String?
    let copyright: String?
    let alt: String?

    enum CodingKeys: String, CodingKey {
        case date, title, explanation, url, hdurl, permalink, credit, copyright, alt
        case mediaType = "media_type"
    }

    var imageURLs: [URL] {
        guard mediaType.lowercased() == "image" else { return [] }
        var candidates = [String]()
        if let hdurl { candidates.append(hdurl) }
        if let url, let parsed = URL(string: url),
           ["jpg", "jpeg", "png", "webp", "gif", "heic", "tif", "tiff"].contains(parsed.pathExtension.lowercased()) {
            candidates.append(url)
        }
        var seen = Set<URL>()
        return candidates.compactMap { raw in
            guard var parts = URLComponents(string: raw), let host = parts.host, !host.isEmpty,
                  parts.scheme == "https" || parts.scheme == "http" else { return nil }
            parts.scheme = "https"
            guard let result = parts.url, seen.insert(result).inserted else { return nil }
            return result
        }
    }

    var storyURL: URL? {
        for raw in [permalink, url].compactMap({ $0 }) {
            if let u = URL(string: raw), u.scheme == "https", let host = u.host,
               host == "nasa.gov" || host.hasSuffix(".nasa.gov") { return u }
        }
        return URL(string: "https://apod.nasa.gov/apod/ap" + date.replacingOccurrences(of: "-", with: "").suffix(6) + ".html")
    }
}

struct OrbitSnapshot: Codable, Sendable {
    let latest: APOD
    let image: APOD
    let imageFilename: String
    let checkedAt: Date
    var usesFallback: Bool { latest.date != image.date }
}

struct OrbitStore: Sendable {
    let root: URL
    static var standard: OrbitStore {
        OrbitStore(root: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Daily Orbit", isDirectory: true))
    }
    var manifestURL: URL { root.appendingPathComponent("current.json") }
    var imagesURL: URL { root.appendingPathComponent("Images", isDirectory: true) }
    func imageURL(for snapshot: OrbitSnapshot) -> URL {
        imagesURL.appendingPathComponent(URL(fileURLWithPath: snapshot.imageFilename).lastPathComponent)
    }
    func load() -> OrbitSnapshot? {
        guard let data = try? Data(contentsOf: manifestURL),
              let snapshot = try? JSONDecoder().decode(OrbitSnapshot.self, from: data),
              FileManager.default.fileExists(atPath: imageURL(for: snapshot).path) else { return nil }
        return snapshot
    }
    func save(_ snapshot: OrbitSnapshot) throws {
        try FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: manifestURL, options: .atomic)
    }
}

enum OrbitDate {
    static func day(_ date: Date = Date()) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "America/New_York")
        format.dateFormat = "yyyy-MM-dd"
        return format.string(from: date)
    }
    static func previousDays(_ count: Int, before day: String) throws -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(secondsFromGMT: 0)
        format.dateFormat = "yyyy-MM-dd"
        format.isLenient = false
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = format.date(from: day), format.string(from: date) == day,
              let earlier = calendar.date(byAdding: .day, value: -count, to: date) else {
            throw OrbitError.message("NASA returned an invalid date.")
        }
        return format.string(from: earlier)
    }
    static func shouldRefresh(_ snapshot: OrbitSnapshot?, now: Date = Date()) -> Bool {
        guard let snapshot else { return true }
        if snapshot.latest.date == day(now), day(snapshot.checkedAt) == day(now) { return false }
        return now.timeIntervalSince(snapshot.checkedAt) >= 3600 || day(snapshot.checkedAt) != day(now)
    }
}

// This intentionally strips markup without loading HTML or external resources.
extension String {
    var orbitPlainText: String {
        var text = replacingOccurrences(of: "(?i)<br\\s*/?>|</p>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        for (entity, value) in [("&nbsp;", " "), ("&quot;", "\""), ("&#039;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        let pattern = try! NSRegularExpression(pattern: "&#(x[0-9A-Fa-f]+|[0-9]+);")
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: text), let digits = Range(match.range(at: 1), in: text) else { continue }
            let raw = String(text[digits])
            let value = raw.hasPrefix("x") ? UInt32(raw.dropFirst(), radix: 16) : UInt32(raw)
            if let value, let scalar = UnicodeScalar(value) { text.replaceSubrange(whole, with: String(scalar)) }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

actor APODService {
    static let endpoint = URL(string: "https://science.nasa.gov/wp-json/wp/v2/apod-basic")!
    let session: URLSession
    let store: OrbitStore

    init(store: OrbitStore = .standard, session: URLSession = .shared) {
        self.store = store
        self.session = session
    }

    static func decode(_ data: Data) throws -> [APOD] {
        let decoder = JSONDecoder()
        if let records = try? decoder.decode([APOD].self, from: data) { return records }
        if let record = try? decoder.decode(APOD.self, from: data) { return [record] }
        throw OrbitError.message("NASA returned an unexpected response. Your saved picture is safe; try again later.")
    }

    func fetch(_ query: [URLQueryItem] = []) async throws -> [APOD] {
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 35
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("DailyOrbit/1.0 (personal desktop app)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        guard data.count <= 4_000_000 else { throw OrbitError.message("NASA’s response was too large.") }
        return try Self.decode(data)
    }

    static func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw OrbitError.message("Could not read NASA’s response.") }
        guard (200...299).contains(response.statusCode) else {
            let hint = response.statusCode == 429 ? "NASA’s request limit was reached. Try again in an hour." : "NASA is unavailable (HTTP \(response.statusCode)). Try again later."
            throw OrbitError.message(hint)
        }
    }

    func refresh(now: Date = Date()) async throws -> OrbitSnapshot {
        guard let latest = try await fetch().sorted(by: { $0.date > $1.date }).first else {
            throw OrbitError.message("NASA has not published a picture yet. Try again later.")
        }
        _ = try OrbitDate.previousDays(0, before: latest.date)
        let previous = store.load()
        var image = latest
        if image.imageURLs.isEmpty {
            let start = try OrbitDate.previousDays(14, before: latest.date)
            let recent = try await fetch([
                URLQueryItem(name: "start_date", value: start),
                URLQueryItem(name: "end_date", value: latest.date)
            ])
            guard let still = recent.filter({ $0.date <= latest.date && !$0.imageURLs.isEmpty })
                .sorted(by: { $0.date > $1.date }).first else {
                throw OrbitError.message("No still image was found in the past two weeks. Keeping your saved picture.")
            }
            image = still
        }
        _ = try OrbitDate.previousDays(0, before: image.date)
        let filename: String
        if let previous, previous.image.date == image.date, previous.image.imageURLs == image.imageURLs {
            filename = previous.imageFilename
        } else {
            filename = "apod-\(image.date)-\(UUID().uuidString.prefix(8)).jpg"
            try await download(image, filename: filename)
        }
        let snapshot = OrbitSnapshot(latest: latest, image: image, imageFilename: filename, checkedAt: now)
        try store.save(snapshot)
        // Keep a small local collection. Never remove the current image or a file outside Images.
        if let files = try? FileManager.default.contentsOfDirectory(at: store.imagesURL, includingPropertiesForKeys: [.contentModificationDateKey]) {
            let old = files.filter { $0.lastPathComponent.hasPrefix("apod-") && $0.pathExtension == "jpg" && $0.lastPathComponent != filename }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }.dropFirst(13)
            for file in old { try? FileManager.default.removeItem(at: file) }
        }
        return snapshot
    }

    private func download(_ image: APOD, filename: String) async throws {
        try FileManager.default.createDirectory(at: store.imagesURL, withIntermediateDirectories: true)
        var lastError: Error = OrbitError.message("This APOD has no downloadable still image.")
        for url in image.imageURLs {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 90
                let (temporary, response) = try await session.download(for: request)
                defer { try? FileManager.default.removeItem(at: temporary) }
                try Self.validate(response)
                let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0, size <= 80_000_000 else { throw OrbitError.message("NASA’s image exceeded the 80 MB download limit.") }
                try Self.normalizeImage(at: temporary, to: store.imagesURL.appendingPathComponent(filename))
                return
            } catch { lastError = error }
        }
        throw lastError
    }

    static func normalizeImage(at sourceURL: URL, to destinationURL: URL) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, Double(width) * Double(height) <= 150_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 7680
              ] as CFDictionary) else {
            throw OrbitError.message("The downloaded file was not a usable image. Your saved picture is safe.")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw OrbitError.message("Could not prepare the wallpaper file.")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.94] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw OrbitError.message("Could not save the wallpaper.") }
        try (output as Data).write(to: destinationURL, options: .atomic)
    }
}
