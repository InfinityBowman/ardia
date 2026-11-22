import AVFoundation
import CoreMedia
import Foundation

public enum VideoAssemblyError: Error, Equatable {
  case unsupportedFormat
  case noTracks
  case writerFailed(String)
  case exportFailed(String)
}

public enum SegmentFormat: Equatable, Sendable {
  case fragmentedMP4
  case transportStream
  case packedAudio

  public static func sniff(_ data: Data) -> SegmentFormat? {
    if TransportStreamDemuxer.looksLikeTransportStream(data) { return .transportStream }
    if data.count >= 8 {
      let type = String(decoding: data[(data.startIndex + 4)..<(data.startIndex + 8)], as: UTF8.self)
      if ["ftyp", "styp", "moof", "moov", "sidx", "emsg", "prft", "free"].contains(type) { return .fragmentedMP4 }
    }
    if data.starts(with: [0x49, 0x44, 0x33]) { return .packedAudio }
    if data.count >= 2, data[data.startIndex] == 0xFF, data[data.startIndex + 1] & 0xF6 == 0xF0 { return .packedAudio }
    return nil
  }
}

public enum MP4Boxes {
  public static func topLevel(_ data: Data) -> [(type: String, range: Range<Int>)] {
    var boxes: [(String, Range<Int>)] = []
    var offset = data.startIndex
    while offset + 8 <= data.endIndex {
      var size = Int(data[offset]) << 24 | Int(data[offset + 1]) << 16 | Int(data[offset + 2]) << 8 | Int(data[offset + 3])
      let type = String(decoding: data[(offset + 4)..<(offset + 8)], as: UTF8.self)
      if size == 1, offset + 16 <= data.endIndex {
        size = data[(offset + 8)..<(offset + 16)].reduce(0) { $0 << 8 | Int($1) }
      } else if size == 0 {
        size = data.endIndex - offset
      }
      guard size >= 8, offset + size <= data.endIndex else { break }
      boxes.append((type, offset..<(offset + size)))
      offset += size
    }
    return boxes
  }

  public static func mediaFragments(_ data: Data) -> Data {
    let boxes = topLevel(data)
    guard boxes.contains(where: { $0.type == "moof" }) else { return data }
    var out = Data()
    for box in boxes where box.type == "moof" || box.type == "mdat" {
      out.append(data[box.range])
    }
    return out
  }
}

public enum VideoAssembler {
  public static func concatenateFragments(initialization: Data?, segments: [URL], to output: URL) throws {
    FileManager.default.createFile(atPath: output.path(percentEncoded: false), contents: nil)
    let handle = try FileHandle(forWritingTo: output)
    defer { try? handle.close() }
    if let initialization { try handle.write(contentsOf: initialization) }
    for segment in segments {
      let data = try Data(contentsOf: segment)
      try handle.write(contentsOf: initialization == nil ? data : MP4Boxes.mediaFragments(data))
    }
  }

  public static func export(_ inputs: [URL], to output: URL) async throws {
    let composition = AVMutableComposition()
    var entries: [(AVAssetTrack, CMTimeRange, CGAffineTransform)] = []
    var earliest: CMTime?
    let assets = inputs.map { AVURLAsset(url: $0) }
    for asset in assets {
      for track in try await asset.load(.tracks) where track.mediaType == .video || track.mediaType == .audio {
        let (range, transform) = try await track.load(.timeRange, .preferredTransform)
        guard CMTimeGetSeconds(range.duration) > 0 else { continue }
        entries.append((track, range, transform))
        earliest = earliest.map { CMTimeMinimum($0, range.start) } ?? range.start
      }
    }
    guard !entries.isEmpty, let start = earliest else { throw VideoAssemblyError.noTracks }
    var hasVideo = false
    var hasAudio = false
    for (track, range, transform) in entries {
      if track.mediaType == .video ? hasVideo : hasAudio { continue }
      guard let target = composition.addMutableTrack(withMediaType: track.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
      try target.insertTimeRange(range, of: track, at: CMTimeSubtract(range.start, start))
      target.preferredTransform = transform
      if track.mediaType == .video { hasVideo = true } else { hasAudio = true }
    }
    guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
      throw VideoAssemblyError.exportFailed("passthrough unavailable")
    }
    session.shouldOptimizeForNetworkUse = true
    try? FileManager.default.removeItem(at: output)
    do {
      try await session.export(to: output, as: .mp4)
      withExtendedLifetime(assets) {}
    } catch {
      throw VideoAssemblyError.exportFailed(String(describing: error))
    }
  }

  public static func remuxTransportStreams(video: [URL], audio: [URL]?, to output: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
    try? FileManager.default.removeItem(at: output)
    let remuxer = try TransportStreamRemuxer(video: video, audio: audio, output: output, progress: progress)
    try await remuxer.run()
  }
}

final class TransportStreamRemuxer: @unchecked Sendable {
  private final class Source {
    let files: [URL]
    var next = 0
    var extractor = ElementaryExtractor()
    let feedsVideo: Bool
    let feedsAudio: Bool

    init(files: [URL], feedsVideo: Bool, feedsAudio: Bool) {
      self.files = files
      self.feedsVideo = feedsVideo
      self.feedsAudio = feedsAudio
    }

    var isExhausted: Bool { next >= files.count }
  }

  private final class Track {
    let source: Source
    let isVideo: Bool
    var queue: [ElementarySample] = []
    var head = 0
    var input: AVAssetWriterInput?
    var format: CMFormatDescription?
    var lastDTS: Int64?
    var lastDuration: Int64 = 3000
    var shift: Int64 = 0
    var discards = false
    var finished = false

    init(source: Source, isVideo: Bool) {
      self.source = source
      self.isVideo = isVideo
    }

    var pending: Int { queue.count - head }

    func push(_ samples: [ElementarySample]) {
      guard !discards else { return }
      if head > 256 {
        queue.removeFirst(head)
        head = 0
      }
      queue.append(contentsOf: samples)
    }
  }

  private let output: URL
  private let progress: @Sendable (Double) -> Void
  private let sources: [Source]
  private let video: Track
  private let audio: Track
  private let totalFiles: Int

  init(video videoFiles: [URL], audio audioFiles: [URL]?, output: URL, progress: @escaping @Sendable (Double) -> Void) throws {
    self.output = output
    self.progress = progress
    let main = Source(files: videoFiles, feedsVideo: true, feedsAudio: audioFiles == nil)
    let separate = audioFiles.map { Source(files: $0, feedsVideo: false, feedsAudio: true) }
    sources = [main] + (separate.map { [$0] } ?? [])
    video = Track(source: main, isVideo: true)
    audio = Track(source: separate ?? main, isVideo: false)
    totalFiles = videoFiles.count + (audioFiles?.count ?? 0)
  }

  private func refill(_ source: Source) throws {
    guard !source.isExhausted else { return }
    let data = try Data(contentsOf: source.files[source.next])
    source.next += 1
    let samples = try source.extractor.extract(data, includeAudio: source.feedsAudio)
    if source.feedsVideo { video.push(samples.video) }
    if source.feedsAudio { audio.push(samples.audio) }
    progress(Double(sources.reduce(0) { $0 + $1.next }) / Double(max(totalFiles, 1)))
  }

  private func fill(_ track: Track, atLeast count: Int) throws {
    while track.pending < count, !track.source.isExhausted { try refill(track.source) }
  }

  func run() async throws {
    for source in sources {
      var reads = 0
      while !source.isExhausted, reads < 3, (source.feedsVideo && video.pending == 0) || (source.feedsAudio && audio.pending == 0) {
        try refill(source)
        reads += 1
      }
    }
    let videoFormat = try videoFormat()
    let audioFormat = try audioFormat()
    guard videoFormat != nil || audioFormat != nil else { throw VideoAssemblyError.noTracks }
    if audioFormat == nil, audio.source.extractor.sawUnsupportedAudio || audio.source !== video.source { throw VideoAssemblyError.unsupportedFormat }
    let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
    writer.shouldOptimizeForNetworkUse = true
    let writing: any SampleWriting = writer
    for (track, format, type) in [(video, videoFormat, AVMediaType.video), (audio, audioFormat, AVMediaType.audio)] {
      guard let format else { continue }
      let input = AVAssetWriterInput(mediaType: type, outputSettings: nil, sourceFormatHint: format)
      guard writing.accepts(input) else { throw VideoAssemblyError.writerFailed("cannot add \(type.rawValue)") }
      writing.attach(input)
      track.input = input
      track.format = format
    }
    let active = [video, audio].filter { $0.input != nil }
    for track in [video, audio] where track.input == nil { track.discards = true }
    base = active.compactMap { $0.pending > 0 ? $0.queue[$0.head].dts : nil }.min() ?? 0
    let startPTS = active.compactMap { track in track.pending > 0 ? track.queue[track.head].pts : nil }.min().map { $0 - base } ?? 0
    guard writing.begin() else { throw VideoAssemblyError.writerFailed(writer.error.map(String.init(describing:)) ?? "start") }
    writer.startSession(atSourceTime: CMTimeMake(value: max(startPTS, 0), timescale: Int32(ElementaryExtractor.clock)))
    self.writer = writer
    self.active = active
    let outcome: Error? = await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Error?, Never>) in
        queue.async { self.begin(continuation) }
      }
    } onCancel: {
      queue.async { self.stop(error: CancellationError()) }
    }
    if let outcome {
      if outcome is CancellationError { throw outcome }
      throw VideoAssemblyError.writerFailed(String(describing: writer.error ?? outcome))
    }
    await writer.finishWriting()
    guard writer.status == .completed else { throw VideoAssemblyError.writerFailed(writer.error.map(String.init(describing:)) ?? "finish") }
  }

  private var base: Int64 = 0
  private let queue = DispatchQueue(label: "ardia.remux")
  private var writer: AVAssetWriter?
  private var active: [Track] = []
  private var continuation: CheckedContinuation<Error?, Never>?

  private func begin(_ continuation: CheckedContinuation<Error?, Never>) {
    self.continuation = continuation
    for index in active.indices {
      let appending: (any SampleAppending)? = active[index].input
      appending?.whenReady(on: queue) { [self] in feed(active[index]) }
    }
  }

  private func stop(error: Error?) {
    guard let continuation else { return }
    self.continuation = nil
    if error != nil { writer?.cancelWriting() }
    continuation.resume(returning: error)
  }

  private func feed(_ track: Track) {
    guard continuation != nil, let writer, let input = track.input, let format = track.format, !track.finished else { return }
    let appending: any SampleAppending = input
    do {
      while appending.isReady {
        try fill(track, atLeast: 2)
        guard track.pending > 0 else {
          input.markAsFinished()
          track.finished = true
          if active.allSatisfy(\.finished) { stop(error: nil) }
          return
        }
        let sample = track.queue[track.head]
        let dts = adjust(track, sample.dts)
        let nextDTS: Int64? = track.pending > 1 ? adjusted(track, track.queue[track.head + 1].dts) : nil
        let duration = nextDTS.map { max($0 - dts, 1) } ?? track.lastDuration
        track.lastDuration = duration
        track.head += 1
        let buffer = try Self.sampleBuffer(sample, dts: dts - base, pts: dts - base + max(sample.pts - sample.dts, 0), duration: duration, format: format, isVideo: track.isVideo)
        guard appending.appendSample(buffer) else {
          stop(error: writer.error ?? VideoAssemblyError.writerFailed("append"))
          return
        }
      }
    } catch {
      stop(error: error)
    }
  }

  private func adjusted(_ track: Track, _ dts: Int64) -> Int64 {
    let shifted = dts + track.shift
    guard let last = track.lastDTS else { return shifted }
    let jump = shifted - last
    if jump <= 0 || jump > 10 * ElementaryExtractor.clock { return last + track.lastDuration }
    return shifted
  }

  private func adjust(_ track: Track, _ dts: Int64) -> Int64 {
    var shifted = dts + track.shift
    if let last = track.lastDTS {
      let jump = shifted - last
      if jump <= 0 || jump > 10 * ElementaryExtractor.clock {
        track.shift += last + track.lastDuration - shifted
        shifted = last + track.lastDuration
      }
    }
    track.lastDTS = shifted
    return shifted
  }

  private func videoFormat() throws -> CMFormatDescription? {
    guard video.pending > 0, let codec = video.source.extractor.videoCodec else { return nil }
    let sets = video.source.extractor.orderedParameterSets
    guard sets.count >= (codec == .hevc ? 3 : 2) else { throw TransportStreamError.missingParameterSets }
    var joined = Data()
    var offsets: [Int] = []
    for set in sets {
      offsets.append(joined.count)
      joined.append(set)
    }
    let sizes = sets.map(\.count)
    var format: CMFormatDescription?
    let status: OSStatus = joined.withUnsafeBytes { raw in
      let base = raw.bindMemory(to: UInt8.self).baseAddress!
      let pointers = offsets.map { UnsafePointer(base + $0) }
      return pointers.withUnsafeBufferPointer { pointerBuffer in
        sizes.withUnsafeBufferPointer { sizeBuffer in
          if codec == .hevc {
            return CMVideoFormatDescriptionCreateFromHEVCParameterSets(allocator: kCFAllocatorDefault, parameterSetCount: sets.count, parameterSetPointers: pointerBuffer.baseAddress!, parameterSetSizes: sizeBuffer.baseAddress!, nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &format)
          }
          return CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault, parameterSetCount: sets.count, parameterSetPointers: pointerBuffer.baseAddress!, parameterSetSizes: sizeBuffer.baseAddress!, nalUnitHeaderLength: 4, formatDescriptionOut: &format)
        }
      }
    }
    guard status == noErr, let format else { throw TransportStreamError.missingParameterSets }
    return format
  }

  private func audioFormat() throws -> CMFormatDescription? {
    guard audio.pending > 0, let config = audio.source.extractor.audioConfig else { return nil }
    var description = AudioStreamBasicDescription(
      mSampleRate: Float64(config.sampleRate),
      mFormatID: kAudioFormatMPEG4AAC,
      mFormatFlags: AudioFormatFlags(config.objectType),
      mBytesPerPacket: 0,
      mFramesPerPacket: 1024,
      mBytesPerFrame: 0,
      mChannelsPerFrame: UInt32(max(config.channelConfiguration, 1)),
      mBitsPerChannel: 0,
      mReserved: 0
    )
    let cookie = config.elementaryStreamDescriptor
    var format: CMAudioFormatDescription?
    let status = cookie.withUnsafeBytes { raw in
      CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: cookie.count, magicCookie: raw.baseAddress, extensions: nil, formatDescriptionOut: &format)
    }
    guard status == noErr, let format else { throw VideoAssemblyError.unsupportedFormat }
    return format
  }

  static func sampleBuffer(_ sample: ElementarySample, dts: Int64, pts: Int64, duration: Int64, format: CMFormatDescription, isVideo: Bool) throws -> CMSampleBuffer {
    var block: CMBlockBuffer?
    let length = sample.data.count
    var status = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length, blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: length, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
    guard status == noErr, let block else { throw VideoAssemblyError.writerFailed("block \(status)") }
    status = sample.data.withUnsafeBytes { raw in
      CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: length)
    }
    guard status == noErr else { throw VideoAssemblyError.writerFailed("copy \(status)") }
    let clock = Int32(ElementaryExtractor.clock)
    var buffer: CMSampleBuffer?
    if isVideo {
      var timing = CMSampleTimingInfo(duration: CMTimeMake(value: duration, timescale: clock), presentationTimeStamp: CMTimeMake(value: pts, timescale: clock), decodeTimeStamp: CMTimeMake(value: dts, timescale: clock))
      var size = length
      status = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &buffer)
    } else {
      var packet = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(length))
      status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: 1, presentationTimeStamp: CMTimeMake(value: pts, timescale: clock), packetDescriptions: &packet, sampleBufferOut: &buffer)
    }
    guard status == noErr, let buffer else { throw VideoAssemblyError.writerFailed("sample \(status)") }
    if isVideo, !sample.isSync, let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
      let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
      CFDictionarySetValue(dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
    }
    return buffer
  }
}

protocol SampleWriting {
  func canAdd(_ input: AVAssetWriterInput) -> Bool
  func add(_ input: AVAssetWriterInput)
  func startWriting() -> Bool
}

extension SampleWriting {
  func accepts(_ input: AVAssetWriterInput) -> Bool { canAdd(input) }
  func attach(_ input: AVAssetWriterInput) { add(input) }
  func begin() -> Bool { startWriting() }
}

extension AVAssetWriter: SampleWriting {}

protocol SampleAppending {
  var isReadyForMoreMediaData: Bool { get }
  func append(_ sampleBuffer: CMSampleBuffer) -> Bool
  func requestMediaDataWhenReady(on queue: DispatchQueue, using block: @escaping @Sendable () -> Void)
}

extension SampleAppending {
  func whenReady(on queue: DispatchQueue, _ block: @escaping @Sendable () -> Void) { requestMediaDataWhenReady(on: queue, using: block) }
  var isReady: Bool { isReadyForMoreMediaData }
  func appendSample(_ buffer: CMSampleBuffer) -> Bool { append(buffer) }
}

extension AVAssetWriterInput: SampleAppending {}
