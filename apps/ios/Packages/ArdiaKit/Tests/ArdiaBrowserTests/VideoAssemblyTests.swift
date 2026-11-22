import AVFoundation
import Foundation
import Testing
@testable import ArdiaBrowser

enum VideoFixtures {
  static func url(_ folder: String, _ name: String) throws -> URL {
    let file = name as NSString
    return try #require(Bundle.module.url(forResource: file.deletingPathExtension, withExtension: file.pathExtension, subdirectory: "Fixtures/Video/\(folder)"))
  }

  static func data(_ folder: String, _ name: String) throws -> Data {
    try Data(contentsOf: url(folder, name))
  }

  static func scratch() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(path: "ardia-video-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  struct Summary {
    var duration: Double
    var hasVideo: Bool
    var hasAudio: Bool
    var videoSize: CGSize?
    var videoSamples: Int
  }

  static func summary(_ url: URL) async throws -> Summary {
    let asset = AVURLAsset(url: url)
    let duration = CMTimeGetSeconds(try await asset.load(.duration))
    let tracks = try await asset.load(.tracks)
    let video = tracks.first { $0.mediaType == .video }
    let audio = tracks.first { $0.mediaType == .audio }
    var samples = 0
    var decoded = 0
    if let video {
      let reader = try AVAssetReader(asset: asset)
      let compressed = AVAssetReaderTrackOutput(track: video, outputSettings: nil)
      reader.add(compressed)
      reader.startReading()
      while let buffer = compressed.copyNextSampleBuffer() { samples += CMSampleBufferGetNumSamples(buffer) }
      #expect(reader.status == .completed)
      let decoder = try AVAssetReader(asset: asset)
      let frames = AVAssetReaderTrackOutput(track: video, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
      decoder.add(frames)
      decoder.startReading()
      while let buffer = frames.copyNextSampleBuffer() {
        if CMSampleBufferGetImageBuffer(buffer) != nil { decoded += 1 }
      }
      #expect(decoder.status == .completed)
      #expect(decoded >= samples)
    }
    return Summary(duration: duration, hasVideo: video != nil, hasAudio: audio != nil, videoSize: try await video?.load(.naturalSize), videoSamples: samples)
  }
}

struct TransportStreamTests {
  @Test func demuxesPATPMTAndPES() throws {
    var demuxer = TransportStreamDemuxer()
    let packets = try demuxer.demux(VideoFixtures.data("ts", "seg0.ts"))
    #expect(Set(packets.map(\.codec)) == [.h264, .aac])
    let video = packets.filter { $0.codec == .h264 }
    #expect(video.count == 15)
    #expect(video.first?.dts == 126000)
    #expect(video.first?.pts == 138000)
  }

  @Test func extractsAccessUnitsAndAudioFrames() throws {
    var extractor = ElementaryExtractor()
    let first = try extractor.extract(VideoFixtures.data("ts", "seg0.ts"))
    #expect(extractor.videoCodec == .h264)
    #expect(extractor.orderedParameterSets.count == 2)
    #expect(first.video.first?.isSync == true)
    #expect(first.video.dropFirst().allSatisfy { !$0.isSync })
    #expect(extractor.audioConfig == ADTSConfig(objectType: 2, sampleRateIndex: 7, channelConfiguration: 1))
    #expect(extractor.audioConfig?.sampleRate == 22050)
    #expect(extractor.audioConfig?.audioSpecificConfig == Data([0x13, 0x88]))
    #expect(first.audio.count > 15)
    let gaps = zip(first.audio, first.audio.dropFirst()).map { $1.pts - $0.pts }
    #expect(gaps.allSatisfy { abs($0 - 4180) <= 1 })
    let units = first.video[0].data
    let length = Int(units[0]) << 24 | Int(units[1]) << 16 | Int(units[2]) << 8 | Int(units[3])
    #expect(length > 0 && length + 4 <= units.count)
  }

  @Test(arguments: [false, true])
  func joinsAccessUnitsSplitAcrossPESPackets(repeatingTimestamps: Bool) throws {
    let original = try VideoFixtures.data("ts", "seg0.ts")
    var demuxer = TransportStreamDemuxer()
    let packets = try demuxer.demux(original)
    let split = TransportStreamWriter.write(packets, splittingVideo: true, repeatingTimestamps: repeatingTimestamps)
    var reference = ElementaryExtractor()
    var rebuilt = ElementaryExtractor()
    let expected = try reference.extract(original)
    let actual = try rebuilt.extract(split)
    #expect(actual.video.count == expected.video.count)
    #expect(actual.video == expected.video)
    #expect(actual.audio == expected.audio)
  }

  @Test func assignsTimestampsWhenPESPacketsStartMidFrame() throws {
    let original = try VideoFixtures.data("ts", "seg0.ts")
    var demuxer = TransportStreamDemuxer()
    let packets = try demuxer.demux(original)
    let video = packets.filter { $0.codec != .aac }
    var stream = Data()
    var starts: [Int] = []
    for packet in video {
      starts.append(stream.count)
      stream.append(packet.payload)
    }
    var shifted: [PESPacket] = []
    let bounds = [0] + starts.dropFirst().map { $0 - 3 } + [stream.count]
    for index in 0..<(bounds.count - 1) {
      shifted.append(PESPacket(pid: video[0].pid, codec: video[0].codec, pts: video[index].pts, dts: video[index].dts, payload: stream.subdata(in: bounds[index]..<bounds[index + 1])))
    }
    shifted.append(contentsOf: packets.filter { $0.codec == .aac })
    var reference = ElementaryExtractor()
    var rebuilt = ElementaryExtractor()
    let expected = try reference.extract(original)
    let actual = try rebuilt.extract(TransportStreamWriter.write(shifted, splittingVideo: false))
    #expect(actual.video.map(\.dts) == expected.video.map(\.dts))
    #expect(actual.video.map(\.pts) == expected.video.map(\.pts))
    #expect(actual.video.map(\.data) == expected.video.map(\.data))
  }

  @Test func readsPackedAudioTimestamps() throws {
    let split = PackedAudio.split(try VideoFixtures.data("packed", "audio0.aac"))
    #expect(split.timestamp == 126000)
    #expect(ADTS.frames(split.audio).count == 22)
  }

  @Test func splitsAnnexBAndUnwrapsTimestamps() {
    let units = NALUnits.split(Data([0, 0, 0, 1, 0x67, 1, 2, 0, 0, 1, 0x68, 3, 0, 0, 0, 1, 0x65, 9, 9, 0]))
    #expect(units == [Data([0x67, 1, 2]), Data([0x68, 3]), Data([0x65, 9, 9])])
    var unwrapper = TimestampUnwrapper()
    #expect(unwrapper.unwrap((1 << 33) - 3000) == (1 << 33) - 3000)
    #expect(unwrapper.unwrap(3000) == (1 << 33) + 3000)
  }

  @Test func sniffsSegmentFormats() throws {
    #expect(SegmentFormat.sniff(try VideoFixtures.data("ts", "seg0.ts")) == .transportStream)
    #expect(SegmentFormat.sniff(try VideoFixtures.data("fmp4", "video-init.mp4")) == .fragmentedMP4)
    #expect(SegmentFormat.sniff(try VideoFixtures.data("fmp4", "video0.m4s")) == .fragmentedMP4)
    #expect(SegmentFormat.sniff(try VideoFixtures.data("packed", "audio0.aac")) == .packedAudio)
    #expect(SegmentFormat.sniff(Data("<html>".utf8)) == nil)
  }
}

struct VideoAssemblyTests {
  @Test func remuxesMuxedTransportStream() async throws {
    let directory = try VideoFixtures.scratch()
    defer { try? FileManager.default.removeItem(at: directory) }
    let output = directory.appending(path: "out.mp4")
    try await VideoAssembler.remuxTransportStreams(video: [VideoFixtures.url("ts", "seg0.ts"), VideoFixtures.url("ts", "seg1.ts")], audio: nil, to: output)
    let summary = try await VideoFixtures.summary(output)
    #expect(summary.hasVideo && summary.hasAudio)
    #expect(abs(summary.duration - 2) < 0.15)
    #expect(summary.videoSize == CGSize(width: 160, height: 90))
    #expect(summary.videoSamples == 30)
  }

  @Test func remuxesTransportStreamWithPackedAudioRendition() async throws {
    let directory = try VideoFixtures.scratch()
    defer { try? FileManager.default.removeItem(at: directory) }
    let output = directory.appending(path: "out.mp4")
    try await VideoAssembler.remuxTransportStreams(
      video: [VideoFixtures.url("packed", "video0.ts"), VideoFixtures.url("packed", "video1.ts")],
      audio: [VideoFixtures.url("packed", "audio0.aac"), VideoFixtures.url("packed", "audio1.aac")],
      to: output
    )
    let summary = try await VideoFixtures.summary(output)
    #expect(summary.hasVideo && summary.hasAudio)
    #expect(abs(summary.duration - 2.09) < 0.15)
    #expect(summary.videoSamples == 30)
  }

  @Test func concatenatesAndExportsFragmentedRenditions() async throws {
    let directory = try VideoFixtures.scratch()
    defer { try? FileManager.default.removeItem(at: directory) }
    let video = directory.appending(path: "video.mp4")
    let audio = directory.appending(path: "audio.mp4")
    try VideoAssembler.concatenateFragments(initialization: VideoFixtures.data("fmp4", "video-init.mp4"), segments: [VideoFixtures.url("fmp4", "video0.m4s"), VideoFixtures.url("fmp4", "video1.m4s")], to: video)
    try VideoAssembler.concatenateFragments(initialization: VideoFixtures.data("fmp4", "audio-init.mp4"), segments: [VideoFixtures.url("fmp4", "audio0.m4s"), VideoFixtures.url("fmp4", "audio1.m4s"), VideoFixtures.url("fmp4", "audio2.m4s")], to: audio)
    let output = directory.appending(path: "out.mp4")
    try await VideoAssembler.export([video, audio], to: output)
    let summary = try await VideoFixtures.summary(output)
    #expect(summary.hasVideo && summary.hasAudio)
    #expect(abs(summary.duration - 2) < 0.15)
    #expect(summary.videoSamples == 30)
    let boxes = MP4Boxes.topLevel(try Data(contentsOf: output)).map(\.type)
    #expect(boxes.contains("moov"))
    #expect(!boxes.contains("moof"))
  }

  @Test func keepsOnlyFragmentBoxesFromSegments() {
    func box(_ type: String, _ body: [UInt8]) -> Data {
      let size = UInt32(8 + body.count)
      return Data([UInt8(size >> 24), UInt8(size >> 16 & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size & 0xFF)]) + Data(type.utf8) + Data(body)
    }
    let segment = box("styp", [1, 2]) + box("sidx", [3]) + box("moof", [4]) + box("mdat", [5, 6]) + box("emsg", [7])
    #expect(MP4Boxes.mediaFragments(segment) == box("moof", [4]) + box("mdat", [5, 6]))
  }
}

enum TransportStreamWriter {
  static func write(_ packets: [PESPacket], splittingVideo: Bool, repeatingTimestamps: Bool = false) -> Data {
    var out = Data()
    var counters: [Int: UInt8] = [:]
    func emit(pid: Int, payload: Data, unitStart: Bool) {
      var offset = 0
      var first = unitStart
      while offset < payload.count {
        let chunk = min(184, payload.count - offset)
        var packet = Data([0x47, UInt8((first ? 0x40 : 0) | (pid >> 8 & 0x1F)), UInt8(pid & 0xFF)])
        let counter = counters[pid, default: 0]
        counters[pid] = (counter + 1) & 0x0F
        if chunk < 184 {
          let stuffing = 184 - chunk
          packet.append(0x30 | counter)
          packet.append(UInt8(stuffing - 1))
          if stuffing > 1 { packet.append(0x00); packet.append(contentsOf: [UInt8](repeating: 0xFF, count: stuffing - 2)) }
        } else {
          packet.append(0x10 | counter)
        }
        packet.append(payload.subdata(in: offset..<(offset + chunk)))
        out.append(packet)
        offset += chunk
        first = false
      }
    }
    func section(_ body: [UInt8]) -> Data { Data([0x00] + body + [0, 0, 0, 0]) }
    emit(pid: 0, payload: section([0x00, 0xB0, 13, 0, 1, 0xC1, 0, 0, 0, 1, 0xF0, 0x00]), unitStart: true)
    let videoPID = packets.first { $0.codec != .aac }?.pid ?? 256
    let audioPID = packets.first { $0.codec == .aac }?.pid ?? 257
    let streams: [UInt8] = [0x1B, UInt8(0xE0 | videoPID >> 8), UInt8(videoPID & 0xFF), 0xF0, 0, 0x0F, UInt8(0xE0 | audioPID >> 8), UInt8(audioPID & 0xFF), 0xF0, 0]
    emit(pid: 0x1000, payload: section([0x02, 0xB0, UInt8(9 + streams.count + 4), 0, 1, 0xC1, 0, 0, 0xE0 | UInt8(videoPID >> 8), UInt8(videoPID & 0xFF), 0xF0, 0] + streams), unitStart: true)
    func timestamp(_ marker: UInt8, _ value: Int64) -> [UInt8] {
      [marker << 4 | UInt8((value >> 29) & 0x0E) | 1, UInt8((value >> 22) & 0xFF), UInt8((value >> 14) & 0xFE) | 1, UInt8((value >> 7) & 0xFF), UInt8((value << 1) & 0xFE) | 1]
    }
    func pes(_ stream: UInt8, pts: Int64?, dts: Int64?, body: Data) -> Data {
      var header: [UInt8] = []
      var flags: UInt8 = 0
      if let pts, let dts, dts != pts {
        flags = 0xC0
        header = timestamp(3, pts) + timestamp(1, dts)
      } else if let pts {
        flags = 0x80
        header = timestamp(2, pts)
      }
      return Data([0, 0, 1, stream, 0, 0, 0x80, flags, UInt8(header.count)] + header) + body
    }
    for packet in packets {
      let stream: UInt8 = packet.codec == .aac ? 0xC0 : 0xE0
      if splittingVideo, packet.codec != .aac, packet.payload.count > 400 {
        let half = packet.payload.count / 2
        emit(pid: packet.pid, payload: pes(stream, pts: packet.pts, dts: packet.dts, body: packet.payload.prefix(half)), unitStart: true)
        emit(pid: packet.pid, payload: pes(stream, pts: repeatingTimestamps ? packet.pts : nil, dts: repeatingTimestamps ? packet.dts : nil, body: packet.payload.suffix(from: packet.payload.startIndex + half)), unitStart: true)
      } else {
        emit(pid: packet.pid, payload: pes(stream, pts: packet.pts, dts: packet.dts, body: packet.payload), unitStart: true)
      }
    }
    return out
  }
}
