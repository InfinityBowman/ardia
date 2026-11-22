import Foundation

public struct HLSByteRange: Equatable, Sendable {
  public var length: Int
  public var offset: Int

  public init(length: Int, offset: Int) {
    self.length = length
    self.offset = offset
  }

  public var httpHeader: String { "bytes=\(offset)-\(offset + length - 1)" }
}

public struct HLSKey: Equatable, Sendable {
  public enum Method: Equatable, Sendable {
    case none
    case aes128
    case sampleAES
    case other(String)
  }

  public var method: Method
  public var uri: URL?
  public var iv: Data?
  public var keyFormat: String?

  public var isProtected: Bool {
    switch method {
    case .none: false
    case .aes128: !(keyFormat == nil || keyFormat == "identity")
    case .sampleAES, .other: true
    }
  }

  public func initializationVector(sequence: Int) -> Data {
    if let iv { return iv }
    var bytes = [UInt8](repeating: 0, count: 16)
    var value = UInt64(max(sequence, 0))
    for index in stride(from: 15, through: 8, by: -1) {
      bytes[index] = UInt8(value & 0xFF)
      value >>= 8
    }
    return Data(bytes)
  }
}

public struct HLSMap: Equatable, Sendable {
  public var uri: URL
  public var byteRange: HLSByteRange?
  public var key: HLSKey?
}

public struct HLSSegment: Equatable, Sendable {
  public var uri: URL
  public var duration: Double
  public var sequence: Int
  public var byteRange: HLSByteRange?
  public var key: HLSKey?
  public var map: HLSMap?
  public var discontinuity: Bool
}

public struct HLSMediaPlaylist: Equatable, Sendable {
  public var targetDuration: Double
  public var mediaSequence: Int
  public var segments: [HLSSegment]
  public var hasEndList: Bool
  public var playlistType: String?
  public var isIFramesOnly: Bool

  public var duration: Double { segments.reduce(0) { $0 + $1.duration } }
  public var isLive: Bool { !hasEndList && playlistType?.uppercased() != "VOD" }
  public var usesFragmentedMP4: Bool { segments.contains { $0.map != nil } }
  public var isProtected: Bool { segments.contains { $0.key?.isProtected == true } }
}

public struct HLSResolution: Equatable, Sendable {
  public var width: Int
  public var height: Int
  public var pixels: Int { width * height }
}

public struct HLSVariant: Equatable, Sendable {
  public var uri: URL
  public var bandwidth: Int
  public var averageBandwidth: Int?
  public var resolution: HLSResolution?
  public var codecs: [String]
  public var frameRate: Double?
  public var audioGroup: String?

  public var hasVideo: Bool {
    resolution != nil || codecs.contains { HLSCodecs.isVideo($0) }
  }
}

public struct HLSRendition: Equatable, Sendable {
  public var type: String
  public var groupID: String
  public var name: String
  public var language: String?
  public var isDefault: Bool
  public var autoselect: Bool
  public var uri: URL?
  public var channels: Int?
}

public struct HLSMasterPlaylist: Equatable, Sendable {
  public var variants: [HLSVariant]
  public var renditions: [HLSRendition]
  public var sessionKeys: [HLSKey]

  public var isProtected: Bool { sessionKeys.contains { $0.isProtected } }
}

public enum HLSPlaylist: Equatable, Sendable {
  case master(HLSMasterPlaylist)
  case media(HLSMediaPlaylist)
}

public enum HLSParseError: Error, Equatable {
  case notAPlaylist
  case empty
}

public enum HLSCodecs {
  static let videoPrefixes = ["avc1", "avc3", "hvc1", "hev1", "dvh1", "dvhe", "av01", "vp09", "mp4v"]
  static let savablePrefixes = ["avc1", "avc3", "hvc1", "hev1", "mp4a", "ac-3", "ec-3"]

  public static func isVideo(_ codec: String) -> Bool {
    videoPrefixes.contains { codec.lowercased().hasPrefix($0) }
  }

  public static func isSavable(_ codec: String) -> Bool {
    savablePrefixes.contains { codec.lowercased().hasPrefix($0) }
  }
}

extension HLSPlaylist {
  public static func looksLikePlaylist(_ data: Data) -> Bool {
    let prefix = data.prefix(64)
    let bytes = prefix.starts(with: [0xEF, 0xBB, 0xBF]) ? prefix.dropFirst(3) : prefix
    return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U")
  }

  public static func parse(_ text: String, baseURL: URL) throws -> HLSPlaylist {
    let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
      .split(separator: "\n", omittingEmptySubsequences: true)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    guard let first = lines.first, first.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}")).hasPrefix("#EXTM3U") else {
      throw HLSParseError.notAPlaylist
    }
    if lines.contains(where: { $0.hasPrefix("#EXT-X-STREAM-INF") }) {
      return .master(parseMaster(lines, baseURL: baseURL))
    }
    let media = parseMedia(lines, baseURL: baseURL)
    guard !media.segments.isEmpty else { throw HLSParseError.empty }
    return .media(media)
  }

  static func parseMaster(_ lines: [String], baseURL: URL) -> HLSMasterPlaylist {
    var variants: [HLSVariant] = []
    var renditions: [HLSRendition] = []
    var sessionKeys: [HLSKey] = []
    var pending: [String: String]?
    for line in lines {
      if let value = line.tagValue("#EXT-X-STREAM-INF:") {
        pending = HLSAttributes.parse(value)
      } else if let value = line.tagValue("#EXT-X-MEDIA:") {
        let attributes = HLSAttributes.parse(value)
        guard let type = attributes["TYPE"], let group = attributes["GROUP-ID"] else { continue }
        renditions.append(HLSRendition(
          type: type.uppercased(),
          groupID: group,
          name: attributes["NAME"] ?? "",
          language: attributes["LANGUAGE"],
          isDefault: attributes["DEFAULT"]?.uppercased() == "YES",
          autoselect: attributes["AUTOSELECT"]?.uppercased() == "YES",
          uri: attributes["URI"].flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL },
          channels: attributes["CHANNELS"].flatMap { Int($0.split(separator: "/").first ?? "") }
        ))
      } else if let value = line.tagValue("#EXT-X-SESSION-KEY:") {
        sessionKeys.append(HLSAttributes.key(HLSAttributes.parse(value), baseURL: baseURL))
      } else if !line.hasPrefix("#"), let attributes = pending {
        pending = nil
        guard let uri = URL(string: line, relativeTo: baseURL)?.absoluteURL else { continue }
        variants.append(HLSVariant(
          uri: uri,
          bandwidth: attributes["BANDWIDTH"].flatMap(Int.init) ?? 0,
          averageBandwidth: attributes["AVERAGE-BANDWIDTH"].flatMap(Int.init),
          resolution: attributes["RESOLUTION"].flatMap(HLSAttributes.resolution),
          codecs: attributes["CODECS"].map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } } ?? [],
          frameRate: attributes["FRAME-RATE"].flatMap(Double.init),
          audioGroup: attributes["AUDIO"]
        ))
      }
    }
    return HLSMasterPlaylist(variants: variants, renditions: renditions, sessionKeys: sessionKeys)
  }

  static func parseMedia(_ lines: [String], baseURL: URL) -> HLSMediaPlaylist {
    var playlist = HLSMediaPlaylist(targetDuration: 0, mediaSequence: 0, segments: [], hasEndList: false, playlistType: nil, isIFramesOnly: false)
    var duration: Double?
    var byteRange: HLSByteRange?
    var pendingLength: (Int, Int?)?
    var key: HLSKey?
    var map: HLSMap?
    var discontinuity = false
    var sequence = 0
    var lastRangeEnd: [URL: Int] = [:]
    for line in lines {
      if let value = line.tagValue("#EXT-X-TARGETDURATION:") {
        playlist.targetDuration = Double(value) ?? 0
      } else if let value = line.tagValue("#EXT-X-MEDIA-SEQUENCE:") {
        playlist.mediaSequence = Int(value) ?? 0
        sequence = playlist.mediaSequence
      } else if let value = line.tagValue("#EXT-X-PLAYLIST-TYPE:") {
        playlist.playlistType = value
      } else if line.hasPrefix("#EXT-X-ENDLIST") {
        playlist.hasEndList = true
      } else if line.hasPrefix("#EXT-X-I-FRAMES-ONLY") {
        playlist.isIFramesOnly = true
      } else if line.hasPrefix("#EXT-X-DISCONTINUITY") && !line.hasPrefix("#EXT-X-DISCONTINUITY-SEQUENCE") {
        discontinuity = true
      } else if let value = line.tagValue("#EXTINF:") {
        duration = Double(value.split(separator: ",", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
      } else if let value = line.tagValue("#EXT-X-BYTERANGE:") {
        pendingLength = HLSAttributes.rangeParts(value)
      } else if let value = line.tagValue("#EXT-X-KEY:") {
        let parsed = HLSAttributes.key(HLSAttributes.parse(value), baseURL: baseURL)
        key = parsed.method == .none ? nil : parsed
      } else if let value = line.tagValue("#EXT-X-MAP:") {
        let attributes = HLSAttributes.parse(value)
        guard let uri = attributes["URI"].flatMap({ URL(string: $0, relativeTo: baseURL)?.absoluteURL }) else { continue }
        let range = attributes["BYTERANGE"].flatMap(HLSAttributes.rangeParts).map { HLSByteRange(length: $0.0, offset: $0.1 ?? 0) }
        map = HLSMap(uri: uri, byteRange: range, key: key)
      } else if !line.hasPrefix("#") {
        guard let uri = URL(string: line, relativeTo: baseURL)?.absoluteURL else { continue }
        if let (length, offset) = pendingLength {
          let start = offset ?? lastRangeEnd[uri] ?? 0
          byteRange = HLSByteRange(length: length, offset: start)
          lastRangeEnd[uri] = start + length
        }
        playlist.segments.append(HLSSegment(
          uri: uri,
          duration: duration ?? 0,
          sequence: sequence,
          byteRange: byteRange,
          key: key,
          map: map,
          discontinuity: discontinuity
        ))
        sequence += 1
        duration = nil
        byteRange = nil
        pendingLength = nil
        discontinuity = false
      }
    }
    return playlist
  }
}

enum HLSAttributes {
  static func parse(_ text: String) -> [String: String] {
    var result: [String: String] = [:]
    var index = text.startIndex
    while index < text.endIndex {
      guard let equals = text[index...].firstIndex(of: "=") else { break }
      let name = text[index..<equals].trimmingCharacters(in: .whitespaces).uppercased()
      var cursor = text.index(after: equals)
      var value = ""
      if cursor < text.endIndex, text[cursor] == "\"" {
        cursor = text.index(after: cursor)
        let close = text[cursor...].firstIndex(of: "\"") ?? text.endIndex
        value = String(text[cursor..<close])
        cursor = close < text.endIndex ? text.index(after: close) : close
        if let comma = text[cursor...].firstIndex(of: ",") { cursor = text.index(after: comma) } else { cursor = text.endIndex }
      } else {
        let comma = text[cursor...].firstIndex(of: ",") ?? text.endIndex
        value = text[cursor..<comma].trimmingCharacters(in: .whitespaces)
        cursor = comma < text.endIndex ? text.index(after: comma) : comma
      }
      if !name.isEmpty { result[name] = value }
      index = cursor
    }
    return result
  }

  static func resolution(_ text: String) -> HLSResolution? {
    let parts = text.lowercased().split(separator: "x")
    guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]) else { return nil }
    return HLSResolution(width: width, height: height)
  }

  static func rangeParts(_ text: String) -> (Int, Int?)? {
    let parts = text.split(separator: "@")
    guard let length = parts.first.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) else { return nil }
    let offset = parts.count > 1 ? Int(parts[1].trimmingCharacters(in: .whitespaces)) : nil
    return (length, offset)
  }

  static func key(_ attributes: [String: String], baseURL: URL) -> HLSKey {
    let method: HLSKey.Method = switch attributes["METHOD"]?.uppercased() {
    case nil, "NONE": .none
    case "AES-128": .aes128
    case "SAMPLE-AES", "SAMPLE-AES-CTR", "SAMPLE-AES-CENC": .sampleAES
    case let other?: .other(other)
    }
    return HLSKey(
      method: method,
      uri: attributes["URI"].flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL },
      iv: attributes["IV"].flatMap(hexData),
      keyFormat: attributes["KEYFORMAT"]
    )
  }

  static func hexData(_ text: String) -> Data? {
    var hex = text.lowercased()
    if hex.hasPrefix("0x") { hex.removeFirst(2) }
    guard hex.count % 2 == 0, !hex.isEmpty else { return nil }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
      let next = hex.index(index, offsetBy: 2)
      guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
      bytes.append(byte)
      index = next
    }
    var padded = [UInt8](repeating: 0, count: max(0, 16 - bytes.count))
    padded.append(contentsOf: bytes.suffix(16))
    return Data(padded)
  }
}

extension String {
  fileprivate func tagValue(_ tag: String) -> String? {
    hasPrefix(tag) ? String(dropFirst(tag.count)) : nil
  }
}
