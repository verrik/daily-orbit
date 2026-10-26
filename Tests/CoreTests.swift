import Foundation
import AppKit
import ImageIO

struct TestFailure: Error, CustomStringConvertible { let description: String }
func expect(_ truth: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !truth() { throw TestFailure(description: message) }
}
func record(date: String = "2026-10-25", type: String = "image", hd: String? = "https://assets.science.nasa.gov/example.jpg") -> APOD {
    APOD(date: date, title: "Space &amp; stars", explanation: "<b>Explanation:</b> Space.", mediaType: type,
         url: "https://science.nasa.gov/image-article/example/", hdurl: hd, permalink: nil, credit: "NASA", copyright: nil, alt: "Stars")
}

final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@main
struct CoreTests {
    static func main() async throws {
        let scratch = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        var checks = 0
        let encoder = JSONEncoder()
        let still = record()
        let object = try APODService.decode(encoder.encode(still))
        let array = try APODService.decode(encoder.encode([still]))
        try expect(object == [still] && array == [still], "Decode both NASA object and array payloads"); checks += 1
        do { _ = try APODService.decode(Data("{\"error\":\"bad\"}".utf8)); throw TestFailure(description: "Malformed API accepted") }
        catch is OrbitError { checks += 1 }
        try expect(still.imageURLs.count == 1 && still.imageURLs[0].host == "assets.science.nasa.gov", "New API url is a web page, not an image"); checks += 1
        try expect(record(type: "video").imageURLs.isEmpty, "Never use a video thumbnail as wallpaper"); checks += 1
        try expect(record(hd: "file:///etc/passwd").imageURLs.isEmpty, "Reject local image URLs"); checks += 1
        try expect(record(hd: "http://apod.nasa.gov/image.jpg").imageURLs[0].scheme == "https", "Upgrade legacy image URLs to HTTPS"); checks += 1
        try expect("A <a href='https://example.com'>star</a> &amp; &#x1F319; &#8212; &quot;sky&quot;".orbitPlainText == "A star & 🌙 — \"sky\"", "Safe plain text HTML decoding"); checks += 1
        try expect(try OrbitDate.previousDays(14, before: "2026-03-10") == "2026-02-24", "Date arithmetic over DST"); checks += 1
        let now = ISO8601DateFormatter().date(from: "2026-10-25T20:00:00Z")!
        let snapshot = OrbitSnapshot(latest: still, image: still, imageFilename: "apod-2026-10-25.jpg", checkedAt: now)
        try expect(!OrbitDate.shouldRefresh(snapshot, now: now.addingTimeInterval(7200)), "Do not refetch a published APOD repeatedly"); checks += 1
        let old = OrbitSnapshot(latest: record(date: "2026-10-24"), image: still, imageFilename: snapshot.imageFilename, checkedAt: now)
        try expect(!OrbitDate.shouldRefresh(old, now: now.addingTimeInterval(120)) && OrbitDate.shouldRefresh(old, now: now.addingTimeInterval(3601)), "Hourly retry before publication"); checks += 1
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 6, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = bitmap.representation(using: .png, properties: [:])!
        let source = scratch.appendingPathComponent("input.png")
        let jpg = scratch.appendingPathComponent("output.jpg")
        try png.write(to: source)
        try APODService.normalizeImage(at: source, to: jpg)
        let normalized = CGImageSourceCreateWithURL(jpg as CFURL, nil)!
        try expect(CGImageSourceGetType(normalized) as String? == "public.jpeg", "Validate and normalize downloaded images to JPEG"); checks += 1
        try Data("<html>not an image</html>".utf8).write(to: source)
        do { try APODService.normalizeImage(at: source, to: jpg); throw TestFailure(description: "HTML accepted as image") }
        catch is OrbitError { checks += 1 }
        let store = OrbitStore(root: scratch.appendingPathComponent("cache"))
        try FileManager.default.createDirectory(at: store.imagesURL, withIntermediateDirectories: true)
        let yesterday = record(date: "2026-10-24")
        let prior = OrbitSnapshot(latest: yesterday, image: yesterday, imageFilename: "apod-2026-10-24.jpg", checkedAt: now.addingTimeInterval(-86400))
        try Data(contentsOf: jpg).write(to: store.imageURL(for: prior))
        try store.save(prior)
        try expect(store.load()?.image == yesterday, "Cache survives a new store instance"); checks += 1
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        let todayVideo = record(type: "video", hd: nil)
        var requestedRange = false
        StubProtocol.handler = { request in
            if request.url!.query?.contains("start_date=") == true {
                requestedRange = true
                return (200, try encoder.encode([yesterday, todayVideo, record(date: "2026-10-20")]))
            }
            return (200, try encoder.encode([todayVideo]))
        }
        let service = APODService(store: store, session: session)
        let fallback = try await service.refresh(now: now)
        try expect(requestedRange && fallback.image.date == "2026-10-24" && fallback.usesFallback, "Video days select the most recent still from the date range"); checks += 1
        let cached = try Data(contentsOf: store.manifestURL)
        StubProtocol.handler = { _ in (503, Data()) }
        do { _ = try await service.refresh(now: now); throw TestFailure(description: "HTTP error accepted") }
        catch is OrbitError { checks += 1 }
        try expect(try Data(contentsOf: store.manifestURL) == cached, "Network failure preserves the last good cache"); checks += 1
        session.invalidateAndCancel()
        print("Passed \(checks) checks: API formats, safe URLs, dates, caching, video fallback, image validation, and HTTP failure recovery.")
    }
}
