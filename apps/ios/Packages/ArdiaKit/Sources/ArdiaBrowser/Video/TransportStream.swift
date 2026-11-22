import Foundation

public enum ElementaryCodec: Equatable, Sendable {
  case h264
  case hevc
  case aac
}

public struct ElementarySample: Equatable, Sendable {
  public var data: Data
  public var pts: Int64
  public var dts: Int64
  public var isSync: Bool
}

public struct ADTSConfig: Equatable, Sendable {
  public var objectType: Int
  public var sampleRateIndex: Int
  public var channelConfiguration: Int

  static let sampleRates = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]

  public var sampleRate: Int { sampleRateIndex < Self.sampleRates.count ? Self.sampleRates[sampleRateIndex] : 44100 }

  public var audioSpecificConfig: Data {
    let value = UInt16(objectType & 0x1F) << 11 | UInt16(sampleRateIndex & 0x0F) << 7 | UInt16(channelConfiguration & 0x0F) << 3
    return Data([UInt8(value >> 8), UInt8(value & 0xFF)])
  }

  public var elementaryStreamDescriptor: Data {
    let specific = audioSpecificConfig
    let decoderSpecific: [UInt8] = [0x05, UInt8(specific.count)] + specific
    let decoderConfig: [UInt8] = [0x04, UInt8(13 + decoderSpecific.count), 0x40, 0x15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] + decoderSpecific
    let slConfig: [UInt8] = [0x06, 0x01, 0x02]
    let body: [UInt8] = [0, 0, 0] + decoderConfig + slConfig
    return Data([0x03, UInt8(body.count)] + body)
  }
}

public struct PESPacket: Equatable, Sendable {
  public var pid: Int
  public var codec: ElementaryCodec
  public var pts: Int64?
  public var dts: Int64?
  public var payload: Data
}

public enum TransportStreamError: Error, Equatable {
  case notTransportStream
  case noSupportedStreams
  case missingParameterSets
}

public struct TransportStreamDemuxer {
  static let packetSize = 188
  static let streamTypes: [UInt8: ElementaryCodec] = [0x1B: .h264, 0x24: .hevc, 0x0F: .aac]

  private var pmtPID: Int?
  private(set) var streams: [Int: ElementaryCodec] = [:]
  public private(set) var sawUnsupportedAudio = false
  static let unsupportedAudioTypes: Set<UInt8> = [0x03, 0x04, 0x11, 0x81, 0x87, 0xC1, 0xC2]
  private var assembling: [Int: (pts: Int64?, dts: Int64?, payload: Data)] = [:]

  public init() {}

  public static func looksLikeTransportStream(_ data: Data) -> Bool {
    guard data.count >= packetSize * 2 else { return data.first == 0x47 }
    return data[data.startIndex] == 0x47 && data[data.startIndex + packetSize] == 0x47
  }

  public mutating func demux(_ data: Data) throws -> [PESPacket] {
    let bytes = [UInt8](data)
    guard let start = Self.syncOffset(bytes) else { throw TransportStreamError.notTransportStream }
    var packets: [PESPacket] = []
    var offset = start
    while offset + Self.packetSize <= bytes.count {
      guard bytes[offset] == 0x47 else {
        guard let resync = Self.syncOffset(bytes, from: offset + 1) else { break }
        offset = resync
        continue
      }
      parsePacket(bytes, at: offset, into: &packets)
      offset += Self.packetSize
    }
    for pid in assembling.keys.sorted() {
      if let packet = finish(pid) { packets.append(packet) }
    }
    return packets
  }

  static func syncOffset(_ bytes: [UInt8], from: Int = 0) -> Int? {
    var index = from
    while index + packetSize < bytes.count {
      if bytes[index] == 0x47 && bytes[index + packetSize] == 0x47 { return index }
      index += 1
    }
    if index < bytes.count, bytes.count - index == packetSize, bytes[index] == 0x47 { return index }
    return nil
  }

  private mutating func parsePacket(_ bytes: [UInt8], at offset: Int, into packets: inout [PESPacket]) {
    let unitStart = bytes[offset + 1] & 0x40 != 0
    let pid = Int(bytes[offset + 1] & 0x1F) << 8 | Int(bytes[offset + 2])
    let adaptation = (bytes[offset + 3] >> 4) & 0x03
    var payloadStart = offset + 4
    if adaptation == 2 || adaptation == 0 { return }
    if adaptation == 3 { payloadStart += 1 + Int(bytes[offset + 4]) }
    let end = offset + Self.packetSize
    guard payloadStart < end else { return }
    let payload = bytes[payloadStart..<end]
    if pid == 0 {
      if unitStart { parsePAT(Array(payload)) }
    } else if pid == pmtPID {
      if unitStart { parsePMT(Array(payload)) }
    } else if let codec = streams[pid] {
      if unitStart {
        if let packet = finish(pid) { packets.append(packet) }
        startPES(pid, codec: codec, payload: payload)
      } else if assembling[pid] != nil {
        assembling[pid]?.payload.append(contentsOf: payload)
      }
    }
  }

  private mutating func parsePAT(_ payload: [UInt8]) {
    guard let section = Self.section(payload), section.count >= 12, section[0] == 0x00 else { return }
    let length = Int(section[1] & 0x0F) << 8 | Int(section[2])
    let end = min(3 + length - 4, section.count)
    var index = 8
    while index + 4 <= end {
      let program = Int(section[index]) << 8 | Int(section[index + 1])
      let pid = Int(section[index + 2] & 0x1F) << 8 | Int(section[index + 3])
      if program != 0 {
        pmtPID = pid
        return
      }
      index += 4
    }
  }

  private mutating func parsePMT(_ payload: [UInt8]) {
    guard let section = Self.section(payload), section.count >= 16, section[0] == 0x02 else { return }
    let length = Int(section[1] & 0x0F) << 8 | Int(section[2])
    let end = min(3 + length - 4, section.count)
    let infoLength = Int(section[10] & 0x0F) << 8 | Int(section[11])
    var index = 12 + infoLength
    while index + 5 <= end {
      let type = section[index]
      let pid = Int(section[index + 1] & 0x1F) << 8 | Int(section[index + 2])
      let esLength = Int(section[index + 3] & 0x0F) << 8 | Int(section[index + 4])
      if Self.unsupportedAudioTypes.contains(type) { sawUnsupportedAudio = true }
      if let codec = Self.streamTypes[type], !streams.values.contains(where: { Self.sameKind($0, codec) }) || streams[pid] != nil {
        streams[pid] = codec
      }
      index += 5 + esLength
    }
  }

  static func sameKind(_ lhs: ElementaryCodec, _ rhs: ElementaryCodec) -> Bool {
    (lhs == .aac) == (rhs == .aac)
  }

  static func section(_ payload: [UInt8]) -> [UInt8]? {
    guard let pointer = payload.first else { return nil }
    let start = 1 + Int(pointer)
    guard start < payload.count else { return nil }
    return Array(payload[start...])
  }

  private mutating func startPES(_ pid: Int, codec: ElementaryCodec, payload: ArraySlice<UInt8>) {
    let bytes = Array(payload)
    guard bytes.count >= 9, bytes[0] == 0, bytes[1] == 0, bytes[2] == 1 else {
      assembling[pid] = nil
      return
    }
    let flags = bytes[7]
    let headerLength = Int(bytes[8])
    var pts: Int64?
    var dts: Int64?
    if flags & 0x80 != 0, bytes.count >= 14 { pts = Self.timestamp(bytes, at: 9) }
    if flags & 0x40 != 0, bytes.count >= 19 { dts = Self.timestamp(bytes, at: 14) }
    let dataStart = 9 + headerLength
    let data = dataStart < bytes.count ? Data(bytes[dataStart...]) : Data()
    assembling[pid] = (pts, dts ?? pts, data)
  }

  private mutating func finish(_ pid: Int) -> PESPacket? {
    guard let entry = assembling.removeValue(forKey: pid), let codec = streams[pid], !entry.payload.isEmpty else { return nil }
    return PESPacket(pid: pid, codec: codec, pts: entry.pts, dts: entry.dts, payload: entry.payload)
  }

  static func timestamp(_ bytes: [UInt8], at index: Int) -> Int64 {
    let a = Int64(bytes[index] >> 1) & 0x07
    let b = Int64(bytes[index + 1])
    let c = Int64(bytes[index + 2] >> 1)
    let d = Int64(bytes[index + 3])
    let e = Int64(bytes[index + 4] >> 1)
    return a << 30 | b << 22 | c << 15 | d << 7 | e
  }
}

public enum NALUnits {
  public static func split(_ data: Data) -> [Data] {
    let bytes = [UInt8](data)
    var units: [Data] = []
    var start: Int?
    var index = 0
    while index + 2 < bytes.count {
      if bytes[index] == 0, bytes[index + 1] == 0, bytes[index + 2] == 1 {
        if let start { units.append(trimmed(bytes, start, index)) }
        index += 3
        start = index
        continue
      }
      index += 1
    }
    if let start, start < bytes.count { units.append(trimmed(bytes, start, bytes.count)) }
    return units.filter { !$0.isEmpty }
  }

  static func trimmed(_ bytes: [UInt8], _ start: Int, _ end: Int) -> Data {
    var stop = end
    while stop > start, bytes[stop - 1] == 0 { stop -= 1 }
    return Data(bytes[start..<stop])
  }

  public static func type(_ unit: Data, codec: ElementaryCodec) -> Int {
    guard let first = unit.first else { return -1 }
    return codec == .hevc ? Int(first >> 1) & 0x3F : Int(first & 0x1F)
  }

  public static func isParameterSet(_ type: Int, codec: ElementaryCodec) -> Bool {
    codec == .hevc ? (32...34).contains(type) : type == 7 || type == 8
  }

  public static func isDelimiter(_ type: Int, codec: ElementaryCodec) -> Bool {
    codec == .hevc ? type == 35 : type == 9
  }

  public static func isSync(_ type: Int, codec: ElementaryCodec) -> Bool {
    codec == .hevc ? (16...21).contains(type) : type == 5
  }

  public static func splitWithOffsets(_ data: Data) -> [(Int, Data)] {
    let bytes = [UInt8](data)
    var units: [(Int, Data)] = []
    var start: Int?
    var startCode = 0
    var index = 0
    while index + 2 < bytes.count {
      if bytes[index] == 0, bytes[index + 1] == 0, bytes[index + 2] == 1 {
        if let start {
          let unit = trimmed(bytes, start, index)
          if !unit.isEmpty { units.append((startCode, unit)) }
        }
        startCode = index > 0 && bytes[index - 1] == 0 ? index - 1 : index
        index += 3
        start = index
        continue
      }
      index += 1
    }
    if let start, start < bytes.count {
      let unit = trimmed(bytes, start, bytes.count)
      if !unit.isEmpty { units.append((startCode, unit)) }
    }
    return units
  }

  public static func isPicture(_ type: Int, codec: ElementaryCodec) -> Bool {
    codec == .hevc ? (0...31).contains(type) : (1...5).contains(type)
  }

  public static func isPrefix(_ type: Int, codec: ElementaryCodec) -> Bool {
    codec == .hevc ? (32...34).contains(type) || type == 39 : [6, 7, 8].contains(type)
  }

  public static func isFirstSlice(_ unit: Data, codec: ElementaryCodec) -> Bool {
    let headerLength = codec == .hevc ? 2 : 1
    guard unit.count > headerLength else { return false }
    return unit[unit.startIndex + headerLength] & 0x80 != 0
  }

  public static func lengthPrefixed(_ units: [Data]) -> Data {
    var out = Data()
    for unit in units {
      let length = UInt32(unit.count)
      out.append(contentsOf: [UInt8(length >> 24), UInt8(length >> 16 & 0xFF), UInt8(length >> 8 & 0xFF), UInt8(length & 0xFF)])
      out.append(unit)
    }
    return out
  }
}

public struct ADTSFrame: Equatable, Sendable {
  public var config: ADTSConfig
  public var payload: Data
}

public enum ADTS {
  public static func frames(_ data: Data) -> [ADTSFrame] {
    framesWithOffsets(data).map(\.frame)
  }

  public static func framesWithOffsets(_ data: Data) -> [(offset: Int, frame: ADTSFrame)] {
    let bytes = [UInt8](data)
    var frames: [(offset: Int, frame: ADTSFrame)] = []
    var index = 0
    while index + 7 <= bytes.count {
      guard bytes[index] == 0xFF, bytes[index + 1] & 0xF6 == 0xF0 else {
        index += 1
        continue
      }
      let protectionAbsent = bytes[index + 1] & 0x01 == 1
      let profile = Int(bytes[index + 2] >> 6)
      let rateIndex = Int(bytes[index + 2] >> 2) & 0x0F
      let channels = Int(bytes[index + 2] & 0x01) << 2 | Int(bytes[index + 3] >> 6)
      let length = Int(bytes[index + 3] & 0x03) << 11 | Int(bytes[index + 4]) << 3 | Int(bytes[index + 5] >> 5)
      let header = protectionAbsent ? 7 : 9
      guard length > header, index + length <= bytes.count else { break }
      frames.append((index, ADTSFrame(
        config: ADTSConfig(objectType: profile + 1, sampleRateIndex: rateIndex, channelConfiguration: channels),
        payload: Data(bytes[(index + header)..<(index + length)])
      )))
      index += length
    }
    return frames
  }
}

public enum PackedAudio {
  static let timestampOwner = "com.apple.streaming.transportStreamTimestamp"

  public static func split(_ data: Data) -> (timestamp: Int64?, audio: Data) {
    let bytes = [UInt8](data)
    guard bytes.count >= 10, bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 else { return (nil, data) }
    let size = Int(bytes[6] & 0x7F) << 21 | Int(bytes[7] & 0x7F) << 14 | Int(bytes[8] & 0x7F) << 7 | Int(bytes[9] & 0x7F)
    let end = min(10 + size + (bytes[5] & 0x10 != 0 ? 10 : 0), bytes.count)
    var timestamp: Int64?
    var index = 10
    while index + 10 <= end {
      let id = String(decoding: bytes[index..<(index + 4)], as: UTF8.self)
      let frameSize = Int(bytes[index + 4]) << 24 | Int(bytes[index + 5]) << 16 | Int(bytes[index + 6]) << 8 | Int(bytes[index + 7])
      let body = index + 10
      guard frameSize > 0, body + frameSize <= end else { break }
      if id == "PRIV", let zero = bytes[body..<(body + frameSize)].firstIndex(of: 0) {
        let owner = String(decoding: bytes[body..<zero], as: UTF8.self)
        let value = bytes[(zero + 1)..<(body + frameSize)]
        if owner == timestampOwner, value.count >= 8 {
          timestamp = value.prefix(8).reduce(Int64(0)) { $0 << 8 | Int64($1) } & 0x1_FFFF_FFFF
        }
      }
      index = body + frameSize
    }
    return (timestamp, Data(bytes[end...]))
  }
}

public struct TimestampUnwrapper: Sendable {
  private var last: Int64?
  private var offset: Int64 = 0

  public init() {}

  public mutating func unwrap(_ value: Int64) -> Int64 {
    var candidate = value + offset
    if let last {
      if candidate < last - (1 << 32) {
        offset += 1 << 33
        candidate += 1 << 33
      } else if candidate > last + (1 << 32) {
        offset -= 1 << 33
        candidate -= 1 << 33
      }
    }
    last = candidate
    return candidate
  }
}

public struct ElementaryTrack: Equatable, Sendable {
  public var codec: ElementaryCodec
  public var parameterSets: [Data]
  public var audioConfig: ADTSConfig?
  public var samples: [ElementarySample]
}

public struct ElementaryExtractor {
  public static let clock: Int64 = 90000

  private var demuxer = TransportStreamDemuxer()
  private var videoUnwrapper = TimestampUnwrapper()
  private var audioUnwrapper = TimestampUnwrapper()
  public private(set) var videoCodec: ElementaryCodec?
  public private(set) var parameterSets: [Int: Data] = [:]
  public private(set) var audioConfig: ADTSConfig?

  public init() {}

  public var sawUnsupportedAudio: Bool { demuxer.sawUnsupportedAudio }

  public var orderedParameterSets: [Data] {
    parameterSets.keys.sorted().compactMap { parameterSets[$0] }
  }

  public mutating func extract(_ data: Data, includeAudio: Bool = true) throws -> (video: [ElementarySample], audio: [ElementarySample]) {
    if TransportStreamDemuxer.looksLikeTransportStream(data) {
      return try extractTransportStream(data, includeAudio: includeAudio)
    }
    let packed = PackedAudio.split(data)
    let frames = ADTS.frames(packed.audio)
    guard !frames.isEmpty else { throw TransportStreamError.notTransportStream }
    return ([], includeAudio ? audioSamples(frames, pts: packed.timestamp ?? nextAudioPTS ?? 0, continuing: packed.timestamp == nil && nextAudioPTS != nil) : [])
  }

  struct TimestampMark {
    var offset: Int
    var pts: Int64
    var dts: Int64
  }

  private mutating func extractTransportStream(_ data: Data, includeAudio: Bool) throws -> (video: [ElementarySample], audio: [ElementarySample]) {
    let packets = try demuxer.demux(data)
    var videoStream = Data()
    var videoMarks: [TimestampMark] = []
    var audioStream = Data()
    var audioMarks: [TimestampMark] = []
    for packet in packets {
      switch packet.codec {
      case .h264, .hevc:
        if videoCodec == nil { videoCodec = packet.codec }
        guard packet.codec == videoCodec else { continue }
        if let pts = packet.pts { videoMarks.append(TimestampMark(offset: videoStream.count, pts: pts, dts: packet.dts ?? pts)) }
        videoStream.append(packet.payload)
      case .aac:
        guard includeAudio else { continue }
        if let pts = packet.pts { audioMarks.append(TimestampMark(offset: audioStream.count, pts: pts, dts: pts)) }
        audioStream.append(packet.payload)
      }
    }
    let video = videoCodec.map { accessUnits(videoStream, marks: videoMarks, codec: $0) } ?? []
    let audio = includeAudio ? timedAudio(audioStream, marks: audioMarks) : []
    return (video, audio)
  }

  private mutating func accessUnits(_ stream: Data, marks: [TimestampMark], codec: ElementaryCodec) -> [ElementarySample] {
    struct Unit {
      var start: Int
      var nals: [Data] = []
      var hasPicture = false
      var sync = false
    }
    var units: [Unit] = []
    for (offset, nal) in NALUnits.splitWithOffsets(stream) {
      let type = NALUnits.type(nal, codec: codec)
      let opensUnit: Bool
      if units.isEmpty {
        opensUnit = true
      } else if NALUnits.isDelimiter(type, codec: codec) {
        opensUnit = true
      } else if units[units.count - 1].hasPicture {
        opensUnit = NALUnits.isPrefix(type, codec: codec) || (NALUnits.isPicture(type, codec: codec) && NALUnits.isFirstSlice(nal, codec: codec))
      } else {
        opensUnit = false
      }
      if opensUnit { units.append(Unit(start: offset)) }
      if NALUnits.isParameterSet(type, codec: codec) {
        let key = codec == .hevc ? type : (type == 7 ? 33 : 34)
        if parameterSets[key] == nil { parameterSets[key] = nal }
        continue
      }
      if NALUnits.isDelimiter(type, codec: codec) { continue }
      if NALUnits.isPicture(type, codec: codec) { units[units.count - 1].hasPicture = true }
      if NALUnits.isSync(type, codec: codec) { units[units.count - 1].sync = true }
      units[units.count - 1].nals.append(nal)
    }
    var samples: [ElementarySample] = []
    var markIndex = 0
    for unit in units where unit.hasPicture {
      while markIndex + 1 < marks.count, marks[markIndex + 1].offset <= unit.start { markIndex += 1 }
      var timing: (pts: Int64, dts: Int64)?
      if markIndex < marks.count, marks[markIndex].offset <= unit.start, !usedVideoMarks.contains(markIndex) {
        usedVideoMarks.insert(markIndex)
        let mark = marks[markIndex]
        let dts = videoUnwrapper.unwrap(mark.dts)
        timing = (dts + max(0, Self.delta(mark.pts, mark.dts)), dts)
      } else if let last = samples.last ?? lastVideoSample {
        let step = lastVideoStep ?? 3000
        timing = (last.pts + step, last.dts + step)
      }
      guard let timing else { continue }
      if let previous = samples.last ?? lastVideoSample, timing.dts > previous.dts { lastVideoStep = timing.dts - previous.dts }
      samples.append(ElementarySample(data: NALUnits.lengthPrefixed(unit.nals), pts: timing.pts, dts: timing.dts, isSync: unit.sync))
    }
    usedVideoMarks = []
    if let last = samples.last { lastVideoSample = last }
    return samples
  }

  private var usedVideoMarks: Set<Int> = []
  private var lastVideoSample: ElementarySample?
  private var lastVideoStep: Int64?

  private var audioAnchor: (time: Int64, frames: Int64)?

  private mutating func timedAudio(_ stream: Data, marks: [TimestampMark]) -> [ElementarySample] {
    let frames = ADTS.framesWithOffsets(stream)
    guard let first = frames.first else { return [] }
    if audioConfig == nil { audioConfig = first.frame.config }
    let rate = Int64(audioConfig?.sampleRate ?? first.frame.config.sampleRate)
    var samples: [ElementarySample] = []
    var markIndex = 0
    var used: Set<Int> = []
    for (offset, frame) in frames {
      while markIndex + 1 < marks.count, marks[markIndex + 1].offset <= offset { markIndex += 1 }
      if markIndex < marks.count, marks[markIndex].offset <= offset, !used.contains(markIndex) {
        used.insert(markIndex)
        audioAnchor = (audioUnwrapper.unwrap(marks[markIndex].pts), 0)
      }
      guard let anchor = audioAnchor else { continue }
      let time = anchor.time + anchor.frames * 1024 * Self.clock / rate
      audioAnchor = (anchor.time, anchor.frames + 1)
      samples.append(ElementarySample(data: frame.payload, pts: time, dts: time, isSync: true))
    }
    return samples
  }

  static func delta(_ pts: Int64, _ dts: Int64) -> Int64 {
    var value = pts - dts
    if value < -(1 << 32) { value += 1 << 33 }
    if value > 1 << 32 { value -= 1 << 33 }
    return value
  }

  private var nextAudioPTS: Int64?

  private mutating func audioSamples(_ frames: [ADTSFrame], pts: Int64, continuing: Bool = false) -> [ElementarySample] {
    guard let first = frames.first else { return [] }
    if audioConfig == nil { audioConfig = first.config }
    let rate = Int64(audioConfig?.sampleRate ?? first.config.sampleRate)
    let base = continuing ? pts : audioUnwrapper.unwrap(pts)
    let samples = frames.enumerated().map { index, frame in
      let time = base + Int64(index) * 1024 * Self.clock / rate
      return ElementarySample(data: frame.payload, pts: time, dts: time, isSync: true)
    }
    nextAudioPTS = base + Int64(frames.count) * 1024 * Self.clock / rate
    return samples
  }
}
