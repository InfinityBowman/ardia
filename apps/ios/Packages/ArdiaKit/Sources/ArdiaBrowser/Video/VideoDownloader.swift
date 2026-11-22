import Foundation
import Synchronization

public enum VideoDownloadStage: Equatable, Sendable {
  case preparing
  case downloading
  case assembling
}

public struct VideoDownloadProgress: Equatable, Sendable {
  public var stage: VideoDownloadStage
  public var fraction: Double?
  public var receivedBytes: Int64
  public var expectedBytes: Int64?

  public init(stage: VideoDownloadStage, fraction: Double? = nil, receivedBytes: Int64 = 0, expectedBytes: Int64? = nil) {
    self.stage = stage
    self.fraction = fraction
    self.receivedBytes = receivedBytes
    self.expectedBytes = expectedBytes
  }
}

public struct VideoDownloadResult: Sendable {
  public var file: URL
  public var fileExtension: String
}

public struct HLSPlan: Equatable, Sendable {
  public var video: HLSMediaPlaylist
  public var audio: HLSMediaPlaylist?
  public var resolution: HLSResolution?

  public var duration: Double { video.duration }
}

public enum VideoDownloader {
  public typealias ProgressHandler = @Sendable (VideoDownloadProgress) -> Void

  public static func run(_ kind: VideoSourceKind, fetcher: VideoFetcher, workDirectory: URL, concurrency: Int = 6, progress: @escaping ProgressHandler) async throws -> VideoDownloadResult {
    try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    switch kind {
    case .file(let url):
      return try await downloadFile(url, fetcher: fetcher, workDirectory: workDirectory, concurrency: concurrency, progress: progress)
    case .hls(let url):
      progress(VideoDownloadProgress(stage: .preparing))
      let plan = try await HLSDownloader.plan(url, fetcher: fetcher)
      let output = workDirectory.appending(path: "video.mp4")
      try await HLSDownloader.download(plan, fetcher: fetcher, workDirectory: workDirectory, output: output, concurrency: concurrency, progress: progress)
      return VideoDownloadResult(file: output, fileExtension: "mp4")
    case .mediaSource, .dash:
      throw VideoDownloadError.mediaSource
    case .protected:
      throw VideoDownloadError.protected
    case .unavailable:
      throw VideoDownloadError.unsupportedFormat
    }
  }

  static func downloadFile(_ url: URL, fetcher: VideoFetcher, workDirectory: URL, concurrency: Int, progress: @escaping ProgressHandler) async throws -> VideoDownloadResult {
    let destination = workDirectory.appending(path: "download")
    progress(VideoDownloadProgress(stage: .downloading, fraction: 0))
    let response = try await fetcher.download(url, to: destination) { received, expected in
      progress(VideoDownloadProgress(stage: .downloading, fraction: expected.map { Double(received) / Double(max($0, 1)) }, receivedBytes: received, expectedBytes: expected))
    }
    let head = (try? FileHandle(forReadingFrom: destination)).flatMap { handle in
      defer { try? handle.close() }
      return try? handle.read(upToCount: 512)
    } ?? Data()
    let mime = response.mimeType?.lowercased() ?? ""
    if HLSPlaylist.looksLikePlaylist(head) || VideoClassifier.playlistTypes.contains(mime) {
      try? FileManager.default.removeItem(at: destination)
      return try await run(.hls(response.url ?? url), fetcher: fetcher, workDirectory: workDirectory, concurrency: concurrency, progress: progress)
    }
    let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    guard size > 0 else { throw VideoDownloadError.emptyStream }
    if mime.hasPrefix("text/") || mime.contains("html") || mime.contains("json") { throw VideoDownloadError.unsupportedFormat }
    let ext = fileExtension(mime: mime, url: response.url ?? url, head: head)
    let named = workDirectory.appending(path: "video.\(ext)")
    try? FileManager.default.removeItem(at: named)
    do {
      try FileManager.default.moveItem(at: destination, to: named)
    } catch {
      throw VideoDownloadError.storage
    }
    return VideoDownloadResult(file: named, fileExtension: ext)
  }

  static func fileExtension(mime: String, url: URL, head: Data) -> String {
    let known: [String: String] = [
      "video/mp4": "mp4", "video/quicktime": "mov", "video/webm": "webm", "video/x-m4v": "m4v",
      "video/3gpp": "3gp", "video/ogg": "ogv", "video/x-matroska": "mkv", "video/mp2t": "ts",
    ]
    if let ext = known[mime] { return ext }
    let ext = url.pathExtension.lowercased()
    if VideoClassifier.fileExtensions.contains(ext) { return ext }
    if head.count >= 4, head.prefix(4) == Data([0x1A, 0x45, 0xDF, 0xA3]) { return "webm" }
    if head.count >= 12 {
      let brand = String(decoding: head[(head.startIndex + 8)..<(head.startIndex + 12)], as: UTF8.self)
      if brand == "qt  " { return "mov" }
    }
    return "mp4"
  }
}

public enum HLSDownloader {
  public static func plan(_ url: URL, fetcher: VideoFetcher) async throws -> HLSPlan {
    let data = try await fetcher.data(url)
    guard HLSPlaylist.looksLikePlaylist(data) else { throw VideoDownloadError.unsupportedFormat }
    let playlist: HLSPlaylist
    do {
      playlist = try HLSPlaylist.parse(String(decoding: data, as: UTF8.self), baseURL: url)
    } catch {
      throw VideoDownloadError.unsupportedFormat
    }
    switch playlist {
    case .media(let media):
      try validate(media)
      return HLSPlan(video: media, audio: nil, resolution: nil)
    case .master(let master):
      if master.isProtected { throw VideoDownloadError.protected }
      guard let selection = master.bestSelection() else { throw VideoDownloadError.unsupportedFormat }
      async let video = media(selection.variant.uri, fetcher: fetcher)
      async let audio = optionalMedia(selection.audio?.uri, fetcher: fetcher)
      let (videoPlaylist, audioPlaylist) = try await (video, audio)
      return HLSPlan(video: videoPlaylist, audio: audioPlaylist, resolution: selection.variant.resolution)
    }
  }

  static func media(_ url: URL, fetcher: VideoFetcher) async throws -> HLSMediaPlaylist {
    let data = try await fetcher.data(url)
    guard case .media(let media) = try? HLSPlaylist.parse(String(decoding: data, as: UTF8.self), baseURL: url) else {
      throw VideoDownloadError.unsupportedFormat
    }
    try validate(media)
    return media
  }

  static func optionalMedia(_ url: URL?, fetcher: VideoFetcher) async throws -> HLSMediaPlaylist? {
    guard let url else { return nil }
    return try await media(url, fetcher: fetcher)
  }

  static func validate(_ media: HLSMediaPlaylist) throws {
    if media.isProtected { throw VideoDownloadError.protected }
    if media.isLive { throw VideoDownloadError.live }
    if media.isIFramesOnly { throw VideoDownloadError.unsupportedFormat }
    guard !media.segments.isEmpty else { throw VideoDownloadError.emptyStream }
    let maps = Set(media.segments.compactMap { $0.map.map { "\($0.uri.absoluteString)#\($0.byteRange?.offset ?? -1)" } })
    if maps.count > 1 { throw VideoDownloadError.unsupportedFormat }
  }

  struct Piece: Sendable {
    var track: Int
    var index: Int
    var segment: HLSSegment
  }

  public static func download(_ plan: HLSPlan, fetcher: VideoFetcher, workDirectory: URL, output: URL, concurrency: Int = 6, progress: @escaping VideoDownloader.ProgressHandler) async throws {
    let tracks = [plan.video] + (plan.audio.map { [$0] } ?? [])
    var pieces: [Piece] = []
    for (track, playlist) in tracks.enumerated() {
      for (index, segment) in playlist.segments.enumerated() { pieces.append(Piece(track: track, index: index, segment: segment)) }
    }
    let weights = pieces.map { max($0.segment.duration, 0.001) }
    let total = weights.reduce(0, +)
    let tally = Mutex<(done: Double, bytes: Int64)>((0, 0))
    let keys = KeyCache(fetcher: fetcher)
    progress(VideoDownloadProgress(stage: .downloading, fraction: 0))
    try await withThrowingTaskGroup(of: (Int, Int64).self) { group in
      var next = 0
      func enqueue() {
        guard next < pieces.count else { return }
        let position = next
        let piece = pieces[position]
        next += 1
        group.addTask {
          let bytes = try await fetchPiece(piece, fetcher: fetcher, keys: keys, workDirectory: workDirectory)
          return (position, bytes)
        }
      }
      for _ in 0..<max(1, concurrency) { enqueue() }
      while let (position, bytes) = try await group.next() {
        let state = tally.withLock { state in
          state.done += weights[position]
          state.bytes += bytes
          return state
        }
        progress(VideoDownloadProgress(stage: .downloading, fraction: min(state.done / total, 1) * 0.95, receivedBytes: state.bytes))
        enqueue()
      }
    }
    try Task.checkCancellation()
    let received = tally.withLock { $0.bytes }
    progress(VideoDownloadProgress(stage: .assembling, fraction: 0.95, receivedBytes: received))
    var initializations: [Int: Data] = [:]
    for (track, playlist) in tracks.enumerated() {
      guard let map = playlist.segments.first?.map else { continue }
      var data = try await fetcher.data(map.uri, range: map.byteRange)
      if let key = map.key, key.method == .aes128 {
        data = try SegmentCipher.decrypt(data, key: try await keys.key(for: key), iv: key.initializationVector(sequence: playlist.segments.first?.sequence ?? 0))
      }
      initializations[track] = data
    }
    let files = tracks.indices.map { track in tracks[track].segments.indices.map { pieceURL(workDirectory, track: track, index: $0) } }
    try await assemble(files: files, initializations: initializations, workDirectory: workDirectory, output: output) { fraction in
      progress(VideoDownloadProgress(stage: .assembling, fraction: 0.95 + fraction * 0.05, receivedBytes: received))
    }
  }

  static func pieceURL(_ directory: URL, track: Int, index: Int) -> URL {
    directory.appending(path: "t\(track)-\(index).seg")
  }

  static func fetchPiece(_ piece: Piece, fetcher: VideoFetcher, keys: KeyCache, workDirectory: URL) async throws -> Int64 {
    var data = try await fetcher.data(piece.segment.uri, range: piece.segment.byteRange)
    if let key = piece.segment.key, key.method == .aes128 {
      data = try SegmentCipher.decrypt(data, key: try await keys.key(for: key), iv: key.initializationVector(sequence: piece.segment.sequence))
    }
    guard !data.isEmpty else { throw VideoDownloadError.emptyStream }
    do {
      try data.write(to: pieceURL(workDirectory, track: piece.track, index: piece.index))
    } catch {
      throw VideoDownloadError.storage
    }
    return Int64(data.count)
  }

  static func format(of file: URL, hasInitialization: Bool) -> SegmentFormat? {
    if hasInitialization { return .fragmentedMP4 }
    guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
    defer { try? handle.close() }
    return (try? handle.read(upToCount: 1024)).flatMap(SegmentFormat.sniff)
  }

  static func assemble(files: [[URL]], initializations: [Int: Data], workDirectory: URL, output: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
    guard let videoFiles = files.first, let first = videoFiles.first else { throw VideoDownloadError.emptyStream }
    let audioFiles = files.count > 1 ? files[1] : nil
    let videoFormat = format(of: first, hasInitialization: initializations[0] != nil)
    let audioFormat = audioFiles?.first.flatMap { format(of: $0, hasInitialization: initializations[1] != nil) }
    let streamFormats: Set<SegmentFormat> = [.transportStream, .packedAudio]
    do {
      switch videoFormat {
      case .transportStream?, .packedAudio?:
        if let audioFormat, !streamFormats.contains(audioFormat) { throw VideoDownloadError.unsupportedFormat }
        try await VideoAssembler.remuxTransportStreams(video: videoFiles, audio: audioFiles, to: output, progress: progress)
      case .fragmentedMP4?:
        let video = workDirectory.appending(path: "video-track.mp4")
        try VideoAssembler.concatenateFragments(initialization: initializations[0], segments: videoFiles, to: video)
        var inputs = [video]
        if let audioFiles, let audioFormat {
          let audio = workDirectory.appending(path: "audio-track.mp4")
          if audioFormat == .fragmentedMP4 {
            try VideoAssembler.concatenateFragments(initialization: initializations[1], segments: audioFiles, to: audio)
          } else {
            try await VideoAssembler.remuxTransportStreams(video: audioFiles, audio: nil, to: audio)
          }
          inputs.append(audio)
        }
        progress(0.3)
        try await VideoAssembler.export(inputs, to: output)
      case nil:
        throw VideoDownloadError.unsupportedFormat
      }
    } catch let error as VideoDownloadError {
      throw error
    } catch VideoAssemblyError.unsupportedFormat {
      throw VideoDownloadError.unsupportedFormat
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw VideoDownloadError.assemblyFailed
    }
    progress(1)
  }
}

actor KeyCache {
  private let fetcher: VideoFetcher
  private var keys: [URL: Task<Data, Error>] = [:]

  init(fetcher: VideoFetcher) {
    self.fetcher = fetcher
  }

  func key(for key: HLSKey) async throws -> Data {
    guard let uri = key.uri, uri.scheme?.hasPrefix("http") == true || uri.isFileURL else { throw VideoDownloadError.protected }
    let task = keys[uri] ?? Task { [fetcher] in try await fetcher.data(uri) }
    keys[uri] = task
    let data = try await task.value
    guard data.count == 16 else { throw VideoDownloadError.protected }
    return data
  }
}
