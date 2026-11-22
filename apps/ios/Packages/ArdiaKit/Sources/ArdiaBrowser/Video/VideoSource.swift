import Foundation

public enum VideoSourceKind: Equatable, Sendable {
  case file(URL)
  case hls(URL)
  case mediaSource
  case protected
  case dash
  case unavailable

  public var isSavable: Bool {
    switch self {
    case .file, .hls: true
    default: false
    }
  }

  public var url: URL? {
    switch self {
    case .file(let url), .hls(let url): url
    default: nil
    }
  }
}

public struct VideoElementReport: Codable, Equatable, Sendable {
  public var index: Int
  public var src: String
  public var sources: [VideoSourceReport]
  public var poster: String?
  public var duration: Double?
  public var width: Int?
  public var height: Int?
  public var visibleArea: Double
  public var rect: VideoRect?
  public var isPlaying: Bool
  public var hasMediaKeys: Bool
  public var hasStream: Bool
  public var frameURL: String?

  public init(index: Int, src: String, sources: [VideoSourceReport] = [], poster: String? = nil, duration: Double? = nil, width: Int? = nil, height: Int? = nil, visibleArea: Double = 0, rect: VideoRect? = nil, isPlaying: Bool = false, hasMediaKeys: Bool = false, hasStream: Bool = false, frameURL: String? = nil) {
    self.index = index
    self.src = src
    self.sources = sources
    self.poster = poster
    self.duration = duration
    self.width = width
    self.height = height
    self.visibleArea = visibleArea
    self.rect = rect
    self.isPlaying = isPlaying
    self.hasMediaKeys = hasMediaKeys
    self.hasStream = hasStream
    self.frameURL = frameURL
  }
}

public struct VideoSourceReport: Codable, Equatable, Sendable {
  public var src: String
  public var type: String?

  public init(src: String, type: String? = nil) {
    self.src = src
    self.type = type
  }
}

public struct VideoRect: Codable, Equatable, Sendable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
}

public struct VideoPageReport: Codable, Equatable, Sendable {
  public var pageURL: String
  public var title: String
  public var userAgent: String?
  public var videos: [VideoElementReport]
  public var streams: [String]
  public var metaVideos: [String]

  public init(pageURL: String, title: String, userAgent: String? = nil, videos: [VideoElementReport], streams: [String] = [], metaVideos: [String] = []) {
    self.pageURL = pageURL
    self.title = title
    self.userAgent = userAgent
    self.videos = videos
    self.streams = streams
    self.metaVideos = metaVideos
  }
}

public struct DetectedVideo: Identifiable, Equatable, Sendable {
  public var id: String
  public var kind: VideoSourceKind
  public var element: VideoElementReport?
  public var pageURL: URL?
  public var title: String

  public var duration: Double? { element?.duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }
  public var isPlaying: Bool { element?.isPlaying ?? false }
}

public enum VideoUnsavableReason: Equatable, Sendable {
  case noVideo
  case mediaSource
  case protected
  case live
}

public struct VideoScan: Equatable, Sendable {
  public var savable: [DetectedVideo]
  public var unsavable: [DetectedVideo]
  public var userAgent: String?
  public var pageURL: URL?
  public var title: String

  public var reason: VideoUnsavableReason {
    if unsavable.contains(where: { $0.kind == .protected }) { return .protected }
    if unsavable.contains(where: { $0.kind == .mediaSource || $0.kind == .dash }) { return .mediaSource }
    return .noVideo
  }
}

public enum VideoClassifier {
  static let fileExtensions: Set<String> = ["mp4", "m4v", "mov", "webm", "mkv", "3gp", "3g2", "ogv", "avi", "qt"]
  static let playlistExtensions: Set<String> = ["m3u8", "m3u"]
  static let fileTypes = ["video/mp4", "video/quicktime", "video/webm", "video/x-m4v", "video/3gpp", "video/ogg", "video/x-matroska"]
  static let playlistTypes = ["application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl", "audio/x-mpegurl"]

  public static func classify(src: String, type: String? = nil, hasMediaKeys: Bool = false, streams: [URL] = []) -> VideoSourceKind {
    if hasMediaKeys { return .protected }
    let trimmed = src.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return .unavailable }
    let lower = trimmed.lowercased()
    if lower.hasPrefix("blob:") || lower.hasPrefix("mediasource:") {
      if let stream = preferredStream(streams) { return .hls(stream) }
      return streams.contains(where: isDASH) ? .dash : .mediaSource
    }
    guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
      return .unavailable
    }
    let mime = type?.lowercased().split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) }
    if let mime, playlistTypes.contains(mime) { return .hls(url) }
    if let mime, mime == "application/dash+xml" { return .dash }
    let ext = url.pathExtension.lowercased()
    if playlistExtensions.contains(ext) { return .hls(url) }
    if ext == "mpd" { return .dash }
    if fileExtensions.contains(ext) { return .file(url) }
    if let mime, fileTypes.contains(mime) { return .file(url) }
    if isPlaylistLike(url) { return .hls(url) }
    return .file(url)
  }

  public static func isPlaylistLike(_ url: URL) -> Bool {
    let lower = url.absoluteString.lowercased()
    return lower.contains(".m3u8") || lower.contains("format=m3u8") || lower.contains("/hls/") && lower.hasSuffix("playlist")
  }

  static func isDASH(_ url: URL) -> Bool {
    url.pathExtension.lowercased() == "mpd" || url.absoluteString.lowercased().contains(".mpd?")
  }

  public static func preferredStream(_ streams: [URL]) -> URL? {
    let playlists = streams.filter { playlistExtensions.contains($0.pathExtension.lowercased()) || isPlaylistLike($0) }
    let masterNamed = playlists.first { url in
      let name = url.lastPathComponent.lowercased()
      return name.contains("master") || name.contains("index") || name.contains("playlist") || name.contains("manifest")
    }
    return masterNamed ?? playlists.first
  }

  public static func scan(_ report: VideoPageReport) -> VideoScan {
    let playedDirectly = Set(report.videos.flatMap { [$0.src] + $0.sources.map(\.src) }.filter { !$0.lowercased().hasPrefix("blob:") })
    let streams = report.streams.filter { !playedDirectly.contains($0) }.compactMap(URL.init(string:))
    var savable: [DetectedVideo] = []
    var unsavable: [DetectedVideo] = []
    var claimedStreams = false
    var seen: Set<String> = []
    let ranked = report.videos.sorted(by: rank)
    for element in ranked {
      var kind = classify(src: element.src, hasMediaKeys: element.hasMediaKeys, streams: claimedStreams ? [] : streams)
      if kind == .unavailable {
        for source in element.sources {
          let candidate = classify(src: source.src, type: source.type, hasMediaKeys: element.hasMediaKeys)
          if candidate != .unavailable {
            kind = candidate
            break
          }
        }
      }
      if case .hls = kind, element.src.lowercased().hasPrefix("blob:") { claimedStreams = true }
      let detected = DetectedVideo(id: "video-\(element.index)", kind: kind, element: element, pageURL: URL(string: element.frameURL ?? report.pageURL), title: report.title)
      if let url = kind.url {
        guard seen.insert(url.absoluteString).inserted else { continue }
        savable.append(detected)
      } else if kind != .unavailable {
        unsavable.append(detected)
      }
    }
    if savable.isEmpty, !claimedStreams, let stream = preferredStream(streams), seen.insert(stream.absoluteString).inserted {
      savable.append(DetectedVideo(id: "stream", kind: .hls(stream), element: nil, pageURL: URL(string: report.pageURL), title: report.title))
    }
    if savable.isEmpty {
      for (offset, meta) in report.metaVideos.enumerated() {
        let kind = classify(src: meta)
        guard let url = kind.url, seen.insert(url.absoluteString).inserted else { continue }
        savable.append(DetectedVideo(id: "meta-\(offset)", kind: kind, element: nil, pageURL: URL(string: report.pageURL), title: report.title))
      }
    }
    return VideoScan(savable: savable, unsavable: unsavable, userAgent: report.userAgent, pageURL: URL(string: report.pageURL), title: report.title)
  }

  static func rank(_ lhs: VideoElementReport, _ rhs: VideoElementReport) -> Bool {
    if lhs.isPlaying != rhs.isPlaying { return lhs.isPlaying }
    if lhs.visibleArea != rhs.visibleArea { return lhs.visibleArea > rhs.visibleArea }
    let lhsPixels = (lhs.width ?? 0) * (lhs.height ?? 0)
    let rhsPixels = (rhs.width ?? 0) * (rhs.height ?? 0)
    if lhsPixels != rhsPixels { return lhsPixels > rhsPixels }
    return lhs.index < rhs.index
  }
}

extension HLSVariant {
  var prefersAAC: Bool {
    let audio = codecs.filter { !HLSCodecs.isVideo($0) }
    return audio.isEmpty || audio.contains { $0.lowercased().hasPrefix("mp4a") }
  }
}

public struct HLSSelection: Equatable, Sendable {
  public var variant: HLSVariant
  public var audio: HLSRendition?
}

extension HLSMasterPlaylist {
  public func bestSelection(preferredLanguages: [String] = Locale.preferredLanguages) -> HLSSelection? {
    let usable = variants.filter { variant in variant.codecs.isEmpty || variant.codecs.allSatisfy(HLSCodecs.isSavable) }
    let pool = usable.isEmpty ? variants : usable
    let withVideo = pool.filter(\.hasVideo)
    let candidates = withVideo.isEmpty ? pool : withVideo
    guard let best = candidates.max(by: { lhs, rhs in
      let lhsPixels = lhs.resolution?.pixels ?? 0
      let rhsPixels = rhs.resolution?.pixels ?? 0
      if lhsPixels != rhsPixels { return lhsPixels < rhsPixels }
      if lhs.prefersAAC != rhs.prefersAAC { return !lhs.prefersAAC }
      return (lhs.averageBandwidth ?? lhs.bandwidth) < (rhs.averageBandwidth ?? rhs.bandwidth)
    }) else { return nil }
    return HLSSelection(variant: best, audio: audioRendition(for: best, preferredLanguages: preferredLanguages))
  }

  public func audioRendition(for variant: HLSVariant, preferredLanguages: [String] = Locale.preferredLanguages) -> HLSRendition? {
    guard let group = variant.audioGroup else { return nil }
    let members = renditions.filter { $0.type == "AUDIO" && $0.groupID == group }
    guard !members.isEmpty else { return nil }
    let languages = preferredLanguages.map { String($0.prefix(2)).lowercased() }
    func matchesLanguage(_ rendition: HLSRendition) -> Bool {
      guard let language = rendition.language?.prefix(2).lowercased() else { return false }
      return languages.first == language
    }
    let chosen = members.first { $0.isDefault }
      ?? members.first { $0.autoselect && matchesLanguage($0) }
      ?? members.first { $0.autoselect }
      ?? members.first
    guard let chosen, chosen.uri != nil else { return nil }
    return chosen
  }
}
