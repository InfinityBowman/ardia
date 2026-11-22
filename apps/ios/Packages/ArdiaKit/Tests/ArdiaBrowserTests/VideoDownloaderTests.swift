import Foundation
import Synchronization
import Testing
@testable import ArdiaBrowser

final class FixtureServer: URLProtocol, @unchecked Sendable {
  struct Site: Sendable {
    var requiredCookie: String?
    var files: [String: Data] = [:]
    var types: [String: String] = [:]
    var status: [String: Int] = [:]
    var inFlight = 0
    var maxInFlight = 0
    var requests: [String] = []
    var referers: Set<String> = []
  }

  static let sites = Mutex<[String: Site]>([:])

  static func host(_ configure: (inout Site) throws -> Void) rethrows -> String {
    let host = "media-\(UUID().uuidString.prefix(8).lowercased()).test"
    var site = Site()
    try configure(&site)
    sites.withLock { $0[host] = site }
    return host
  }

  static func site(_ host: String) -> Site? {
    sites.withLock { $0[host] }
  }

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host().map { $0.hasSuffix(".test") } ?? false
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url, let host = url.host() else { return }
    let path = url.path()
    let cookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
    let referer = request.value(forHTTPHeaderField: "Referer")
    let snapshot = Self.sites.withLock { sites -> Site? in
      sites[host]?.inFlight += 1
      if let site = sites[host] { sites[host]?.maxInFlight = max(site.maxInFlight, site.inFlight) }
      sites[host]?.requests.append(path)
      if let referer { sites[host]?.referers.insert(referer) }
      return sites[host]
    }
    let client = client
    let request = request
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.01) { [self] in
      defer { Self.sites.withLock { $0[host]?.inFlight -= 1 } }
      guard let site = snapshot else { return }
      var status = site.status[path] ?? 200
      if let required = site.requiredCookie, !cookie.contains(required) { status = 403 }
      var body = site.files[path] ?? Data()
      if site.files[path] == nil, status == 200 { status = 404 }
      if status == 200, let range = request.value(forHTTPHeaderField: "Range"), range.hasPrefix("bytes=") {
        let bounds = range.dropFirst(6).split(separator: "-").compactMap { Int($0) }
        if bounds.count == 2, bounds[1] < body.count {
          body = body.subdata(in: bounds[0]..<(bounds[1] + 1))
          status = 206
        }
      }
      var headers = ["Content-Length": "\(body.count)"]
      if let type = site.types[path] { headers["Content-Type"] = type }
      let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: body)
      client?.urlProtocolDidFinishLoading(self)
    }
  }

  override func stopLoading() {}
}

extension FixtureServer.Site {
  mutating func serve(_ folder: String, at prefix: String = "") throws {
    let directory = try #require(Bundle.module.resourceURL).appending(path: "Fixtures/Video/\(folder)", directoryHint: .isDirectory)
    for name in try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) {
      files["\(prefix)/\(folder)/\(name)"] = try Data(contentsOf: directory.appending(path: name))
    }
  }
}

struct VideoDownloaderTests {
  func fetcher(cookies: [HTTPCookie] = [], referer: URL? = nil) -> VideoFetcher {
    VideoFetcher(context: VideoRequestContext(cookies: cookies, userAgent: "ArdiaTest/1", referer: referer), protocolClasses: [FixtureServer.self], attempts: 2)
  }

  func run(_ kind: VideoSourceKind, fetcher: VideoFetcher, concurrency: Int = 6) async throws -> (VideoDownloadResult, VideoFixtures.Summary, [VideoDownloadProgress]) {
    let directory = try VideoFixtures.scratch()
    let updates = Mutex<[VideoDownloadProgress]>([])
    let result = try await VideoDownloader.run(kind, fetcher: fetcher, workDirectory: directory, concurrency: concurrency) { update in
      updates.withLock { $0.append(update) }
    }
    let summary = try await VideoFixtures.summary(result.file)
    return (result, summary, updates.withLock { $0 })
  }

  @Test func downloadsFragmentedMasterWithSeparateAudioUsingCookies() async throws {
    let host = try FixtureServer.host { site in
      site.requiredCookie = "session=abc"
      try site.serve("fmp4")
    }
    let cookie = try #require(HTTPCookie(properties: [.domain: host, .path: "/", .name: "session", .value: "abc", .secure: "TRUE"]))
    let page = URL(string: "https://\(host)/watch")!
    let (result, summary, updates) = try await run(.hls(URL(string: "https://\(host)/fmp4/master.m3u8")!), fetcher: fetcher(cookies: [cookie], referer: page))
    #expect(result.fileExtension == "mp4")
    #expect(summary.hasVideo && summary.hasAudio)
    #expect(abs(summary.duration - 2) < 0.15)
    #expect(summary.videoSamples == 30)
    #expect(FixtureServer.site(host)?.referers == [page.absoluteString])
    let fractions = updates.compactMap(\.fraction)
    #expect(fractions == fractions.sorted())
    #expect(updates.last?.stage == .assembling)
    #expect(fractions.last == 1)
  }

  @Test func refusesWithoutTheTabsCookies() async throws {
    let host = try FixtureServer.host { site in
      site.requiredCookie = "session=abc"
      try site.serve("fmp4")
    }
    await #expect(throws: VideoDownloadError.refused(403)) {
      _ = try await run(.hls(URL(string: "https://\(host)/fmp4/master.m3u8")!), fetcher: fetcher())
    }
  }

  @Test func downloadsTransportStreamPlaylistWithBoundedConcurrency() async throws {
    let host = try FixtureServer.host { site in try site.serve("ts") }
    let (_, summary, _) = try await run(.hls(URL(string: "https://\(host)/ts/media.m3u8")!), fetcher: fetcher(), concurrency: 1)
    #expect(summary.hasVideo && summary.hasAudio)
    #expect(summary.videoSamples == 30)
    #expect(FixtureServer.site(host)?.maxInFlight == 1)
  }

  @Test func downloadsTransportStreamWithPackedAudioRendition() async throws {
    let host = try FixtureServer.host { site in try site.serve("packed") }
    let (_, summary, _) = try await run(.hls(URL(string: "https://\(host)/packed/master.m3u8")!), fetcher: fetcher())
    #expect(summary.hasVideo && summary.hasAudio)
    #expect(abs(summary.duration - 2.09) < 0.15)
  }

  @Test func downloadsByteRangeSegments() async throws {
    let host = try FixtureServer.host { site in try site.serve("range") }
    let (_, summary, _) = try await run(.hls(URL(string: "https://\(host)/range/media.m3u8")!), fetcher: fetcher())
    #expect(summary.hasVideo && summary.hasAudio)
    #expect(summary.videoSamples == 30)
    #expect(FixtureServer.site(host)?.requests.filter { $0 == "/range/media.ts" }.count == 2)
  }

  @Test func decryptsAES128Segments() async throws {
    let key = Data((0..<16).map { UInt8($0 * 7 + 3) })
    let iv = Data((0..<16).map { UInt8(255 - $0) })
    let host = try FixtureServer.host { site in
      site.files["/enc/key"] = key
      site.files["/enc/seg0.ts"] = SegmentCipher.encrypt(try VideoFixtures.data("ts", "seg0.ts"), key: key, iv: iv)
      site.files["/enc/seg1.ts"] = SegmentCipher.encrypt(try VideoFixtures.data("ts", "seg1.ts"), key: key, iv: key.initializationVectorForTest(sequence: 8))
      site.files["/enc/media.m3u8"] = Data("""
      #EXTM3U
      #EXT-X-TARGETDURATION:1
      #EXT-X-MEDIA-SEQUENCE:7
      #EXT-X-KEY:METHOD=AES-128,URI="key",IV=0x\(iv.map { String(format: "%02x", $0) }.joined())
      #EXTINF:1,
      seg0.ts
      #EXT-X-KEY:METHOD=AES-128,URI="key"
      #EXTINF:1,
      seg1.ts
      #EXT-X-ENDLIST
      """.utf8)
    }
    let (_, summary, _) = try await run(.hls(URL(string: "https://\(host)/enc/media.m3u8")!), fetcher: fetcher())
    #expect(summary.hasVideo && summary.hasAudio)
    #expect(summary.videoSamples == 30)
    #expect(FixtureServer.site(host)?.requests.filter { $0 == "/enc/key" }.count == 1)
  }

  @Test func downloadsPlainFileAndSniffsPlaylists() async throws {
    let host = try FixtureServer.host { site in
      try site.serve("plain")
      try site.serve("ts")
      site.types["/plain/clip.mp4"] = "video/mp4"
      site.files["/watch/stream"] = site.files["/ts/media.m3u8"].map { String(decoding: $0, as: UTF8.self).replacingOccurrences(of: "seg", with: "/ts/seg") }.map { Data($0.utf8) }
      site.types["/watch/stream"] = "application/vnd.apple.mpegurl"
    }
    let (file, summary, updates) = try await run(.file(URL(string: "https://\(host)/plain/clip.mp4")!), fetcher: fetcher())
    #expect(file.fileExtension == "mp4")
    #expect(summary.hasVideo && summary.hasAudio)
    #expect(updates.contains { $0.receivedBytes == 14610 })
    let (sniffed, sniffedSummary, _) = try await run(.file(URL(string: "https://\(host)/watch/stream")!), fetcher: fetcher())
    #expect(sniffed.file.lastPathComponent == "video.mp4")
    #expect(sniffedSummary.videoSamples == 30)
  }

  @Test func explainsStreamsThatCannotBeSaved() async throws {
    let host = FixtureServer.host { site in
      site.files["/live.m3u8"] = Data("#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\na.ts\n".utf8)
      site.files["/drm.m3u8"] = Data("#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-KEY:METHOD=SAMPLE-AES,URI=\"skd://k\",KEYFORMAT=\"com.apple.streamingkeydelivery\"\n#EXTINF:2,\na.ts\n#EXT-X-ENDLIST\n".utf8)
      site.files["/page.html"] = Data("<html>".utf8)
      site.types["/page.html"] = "text/html"
      site.status["/gone.mp4"] = 410
    }
    await #expect(throws: VideoDownloadError.live) { _ = try await run(.hls(URL(string: "https://\(host)/live.m3u8")!), fetcher: fetcher()) }
    await #expect(throws: VideoDownloadError.protected) { _ = try await run(.hls(URL(string: "https://\(host)/drm.m3u8")!), fetcher: fetcher()) }
    await #expect(throws: VideoDownloadError.unsupportedFormat) { _ = try await run(.file(URL(string: "https://\(host)/page.html")!), fetcher: fetcher()) }
    await #expect(throws: VideoDownloadError.refused(410)) { _ = try await run(.file(URL(string: "https://\(host)/gone.mp4")!), fetcher: fetcher()) }
    await #expect(throws: VideoDownloadError.mediaSource) { _ = try await run(.mediaSource, fetcher: fetcher()) }
  }

  @Test func cancellationStopsTheDownload() async throws {
    let host = try FixtureServer.host { site in try site.serve("ts") }
    let directory = try VideoFixtures.scratch()
    let task = Task {
      try await VideoDownloader.run(.hls(URL(string: "https://\(host)/ts/media.m3u8")!), fetcher: fetcher(), workDirectory: directory) { _ in }
    }
    task.cancel()
    await #expect(throws: (any Error).self) { _ = try await task.value }
  }
}

extension Data {
  func initializationVectorForTest(sequence: Int) -> Data {
    HLSKey(method: .aes128, uri: nil, iv: nil, keyFormat: nil).initializationVector(sequence: sequence)
  }
}
