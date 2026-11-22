import Foundation
import Observation
import Synchronization
import WebKit

public enum DownloadOutcome: Equatable, Sendable {
  case finished(URL, transfer: UUID)
  case failed(fileName: String)
  case videoFailed(fileName: String, message: String)
}

@MainActor
@Observable
public final class DownloadTransfer: Identifiable {
  public enum State: Equatable, Sendable {
    case running
    case finished(URL)
    case failed(String)
  }

  public let id = UUID()
  public let isVideo: Bool
  public internal(set) var fileName: String
  public internal(set) var stage: VideoDownloadStage
  public internal(set) var fraction: Double?
  public internal(set) var receivedBytes: Int64 = 0
  public internal(set) var expectedBytes: Int64?
  public internal(set) var state: State = .running
  public internal(set) var bytesPerSecond: Double?
  public internal(set) var secondsRemaining: Double?

  @ObservationIgnored var cancelHandler: (@MainActor () -> Void)?
  @ObservationIgnored var retryHandler: (@MainActor () -> Void)?
  @ObservationIgnored private var rate = TransferRate()

  init(fileName: String, isVideo: Bool, stage: VideoDownloadStage) {
    self.fileName = fileName
    self.isVideo = isVideo
    self.stage = stage
  }

  public var isRunning: Bool { state == .running }
  public var canRetry: Bool { retryHandler != nil }

  func apply(_ progress: VideoDownloadProgress) {
    guard state == .running else { return }
    if stage != progress.stage { stage = progress.stage }
    if let value = progress.fraction { fraction = max(fraction ?? 0, min(value, 1)) }
    receivedBytes = progress.receivedBytes
    if let expected = progress.expectedBytes { expectedBytes = expected }
    guard progress.stage == .downloading else {
      if bytesPerSecond != nil { bytesPerSecond = nil }
      if secondsRemaining != nil { secondsRemaining = nil }
      return
    }
    rate.add(bytes: progress.receivedBytes, fraction: fraction, at: ContinuousClock.now)
    bytesPerSecond = rate.bytesPerSecond
    secondsRemaining = rate.secondsRemaining(received: receivedBytes, expected: expectedBytes, fraction: fraction)
  }
}

public struct DownloadSummary: Equatable, Sendable {
  public var count: Int
  public var fraction: Double?
  public var receivedBytes: Int64
  public var expectedBytes: Int64?

  public static let idle = DownloadSummary(count: 0, fraction: nil, receivedBytes: 0, expectedBytes: nil)

  public var isIndeterminate: Bool { count > 0 && fraction == nil }

  @MainActor
  public init(_ running: [DownloadTransfer]) {
    count = running.count
    receivedBytes = running.reduce(0) { $0 + $1.receivedBytes }
    let sizes = running.compactMap(\.expectedBytes)
    if !running.isEmpty, sizes.count == running.count, running.allSatisfy({ $0.stage == .downloading }) {
      let total = sizes.reduce(0, +)
      expectedBytes = total
      fraction = total > 0 ? min(Double(receivedBytes) / Double(total), 1) : nil
    } else {
      expectedBytes = nil
      let fractions = running.compactMap { $0.stage == .preparing ? nil : $0.fraction }
      fraction = !running.isEmpty && fractions.count == running.count ? fractions.reduce(0, +) / Double(running.count) : nil
    }
  }

  public init(count: Int, fraction: Double?, receivedBytes: Int64, expectedBytes: Int64?) {
    self.count = count
    self.fraction = fraction
    self.receivedBytes = receivedBytes
    self.expectedBytes = expectedBytes
  }
}

struct TransferRate: Sendable {
  static let window: Duration = .seconds(4)
  static let minimumSpan: Duration = .milliseconds(800)

  private struct Sample: Sendable {
    var time: ContinuousClock.Instant
    var bytes: Int64
    var fraction: Double?
  }

  private var samples: [Sample] = []

  mutating func add(bytes: Int64, fraction: Double?, at time: ContinuousClock.Instant) {
    if let last = samples.last, bytes < last.bytes { samples.removeAll() }
    samples.append(Sample(time: time, bytes: bytes, fraction: fraction))
    while let first = samples.first, samples.count > 2, time - first.time > Self.window { samples.removeFirst() }
  }

  private var seconds: Double? {
    guard let first = samples.first, let last = samples.last, last.time - first.time >= Self.minimumSpan else { return nil }
    let elapsed = (last.time - first.time).components
    return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
  }

  var bytesPerSecond: Double? {
    guard let seconds, let first = samples.first, let last = samples.last, last.bytes > first.bytes else { return nil }
    return Double(last.bytes - first.bytes) / seconds
  }

  func secondsRemaining(received: Int64, expected: Int64?, fraction: Double?) -> Double? {
    if let expected, expected > received, let speed = bytesPerSecond, speed > 0 {
      return Double(expected - received) / speed
    }
    guard let seconds, let start = samples.first?.fraction, let end = samples.last?.fraction, end > start,
          let fraction, fraction < 1 else { return nil }
    return (1 - fraction) / ((end - start) / seconds)
  }
}

@MainActor
@Observable
public final class DownloadManager {
  public let directory: URL
  @ObservationIgnored public var onOutcome: (@MainActor (DownloadOutcome) -> Void)?
  @ObservationIgnored public var onActivityChange: (@MainActor () -> Void)?
  public private(set) var transfers: [DownloadTransfer] = []
  public private(set) var finishedCount = 0

  private struct Active {
    let download: WKDownload
    var fileName: String
    var destination: URL?
    let transfer: DownloadTransfer
    var observation: NSKeyValueObservation?
  }

  @ObservationIgnored private var active: [ObjectIdentifier: Active] = [:]
  @ObservationIgnored private var delegate: DownloadDelegate?
  @ObservationIgnored private let workRoot: URL

  public init(directory: URL = URL.documentsDirectory.appending(path: "Downloads", directoryHint: .isDirectory),
              workRoot: URL = URL.cachesDirectory.appending(path: "VideoDownloads", directoryHint: .isDirectory)) {
    self.directory = directory
    self.workRoot = workRoot
    Task.detached(priority: .background) { try? FileManager.default.removeItem(at: workRoot) }
  }

  public var hasRunningTransfers: Bool { transfers.contains { $0.isRunning } }

  public var running: [DownloadTransfer] { transfers.filter(\.isRunning) }

  public var summary: DownloadSummary { DownloadSummary(running) }

  public func cancel(_ transfer: DownloadTransfer) {
    transfer.cancelHandler?()
  }

  public func dismiss(_ transfer: DownloadTransfer) {
    guard !transfer.isRunning else { return }
    remove(transfer)
  }

  public func retry(_ transfer: DownloadTransfer) {
    guard let retry = transfer.retryHandler else { return }
    remove(transfer)
    retry()
  }

  private func insert(_ transfer: DownloadTransfer) {
    transfers.insert(transfer, at: 0)
    onActivityChange?()
  }

  private func remove(_ transfer: DownloadTransfer) {
    transfers.removeAll { $0.id == transfer.id }
    onActivityChange?()
  }

  @discardableResult
  public func startVideo(_ kind: VideoSourceKind, fileName: String, context: VideoRequestContext) -> DownloadTransfer {
    let transfer = DownloadTransfer(fileName: fileName, isVideo: true, stage: .preparing)
    let work = workRoot.appending(path: transfer.id.uuidString, directoryHint: .isDirectory)
    let relay = ProgressRelay { [weak transfer] progress in transfer?.apply(progress) }
    let task = Task { [weak self] in
      let fetcher = VideoFetcher(context: context)
      let outcome: Result<VideoDownloadResult, Error>
      do {
        outcome = .success(try await VideoDownloader.run(kind, fetcher: fetcher, workDirectory: work) { relay.offer($0) })
      } catch {
        outcome = .failure(error)
      }
      relay.flush()
      self?.complete(transfer, outcome: outcome, work: work)
    }
    transfer.cancelHandler = { [weak self, weak transfer] in
      task.cancel()
      guard let self, let transfer else { return }
      transfer.state = .failed(String(localized: "Canceled"))
      remove(transfer)
      try? FileManager.default.removeItem(at: work)
    }
    transfer.retryHandler = { [weak self] in
      self?.startVideo(kind, fileName: fileName, context: context)
    }
    insert(transfer)
    return transfer
  }

  private func complete(_ transfer: DownloadTransfer, outcome: Result<VideoDownloadResult, Error>, work: URL) {
    defer { try? FileManager.default.removeItem(at: work) }
    guard transfers.contains(where: { $0.id == transfer.id }), transfer.isRunning else { return }
    switch outcome {
    case .success(let result):
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = Self.uniqueURL(in: directory, for: "\(transfer.fileName).\(result.fileExtension)")
        try FileManager.default.moveItem(at: result.file, to: destination)
        transfer.fraction = 1
        transfer.state = .finished(destination)
        finishedCount += 1
        transfers.removeAll { $0.id == transfer.id }
        onOutcome?(.finished(destination, transfer: transfer.id))
        onActivityChange?()
      } catch {
        fail(transfer, message: VideoDownloadError.storage.message)
      }
    case .failure(let error):
      if error is CancellationError { return }
      fail(transfer, message: (error as? VideoDownloadError)?.message ?? VideoDownloadError.network.message)
    }
  }

  private func fail(_ transfer: DownloadTransfer, message: String) {
    transfer.state = .failed(message)
    onOutcome?(.videoFailed(fileName: transfer.fileName, message: message))
    onActivityChange?()
  }

  func track(_ download: WKDownload) {
    if delegate == nil { delegate = DownloadDelegate(manager: self) }
    download.delegate = delegate
    let name = download.originalRequest?.url?.lastPathComponent ?? ""
    let transfer = DownloadTransfer(fileName: name.isEmpty ? String(localized: "Download") : name, isVideo: false, stage: .downloading)
    transfer.cancelHandler = { [weak self, weak download] in
      guard let download else { return }
      download.cancel { _ in }
      self?.failed(download, silently: true)
    }
    let key = ObjectIdentifier(download)
    let relay = ProgressRelay { [weak transfer] progress in transfer?.apply(progress) }
    let observation = download.progress.observe(\.fractionCompleted, options: [.new]) { progress, _ in
      let expected = progress.totalUnitCount
      relay.offer(VideoDownloadProgress(stage: .downloading, fraction: expected > 0 ? progress.fractionCompleted : nil, receivedBytes: progress.completedUnitCount, expectedBytes: expected > 0 ? expected : nil))
    }
    active[key] = Active(download: download, fileName: name, transfer: transfer, observation: observation)
    insert(transfer)
  }

  func destination(for download: WKDownload, suggestedFilename: String) -> URL? {
    let key = ObjectIdentifier(download)
    guard active[key] != nil else { return nil }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      failed(download)
      return nil
    }
    let url = Self.uniqueURL(in: directory, for: suggestedFilename)
    active[key]?.fileName = url.lastPathComponent
    active[key]?.destination = url
    active[key]?.transfer.fileName = url.lastPathComponent
    return url
  }

  func finished(_ download: WKDownload) {
    guard let entry = active.removeValue(forKey: ObjectIdentifier(download)) else { return }
    entry.observation?.invalidate()
    if let destination = entry.destination {
      entry.transfer.state = .finished(destination)
      finishedCount += 1
      transfers.removeAll { $0.id == entry.transfer.id }
      onOutcome?(.finished(destination, transfer: entry.transfer.id))
      onActivityChange?()
    } else {
      entry.transfer.state = .failed(String(localized: "The download didn’t finish."))
      onOutcome?(.failed(fileName: entry.fileName))
      onActivityChange?()
    }
  }

  func failed(_ download: WKDownload, silently: Bool = false) {
    guard let entry = active.removeValue(forKey: ObjectIdentifier(download)) else { return }
    entry.observation?.invalidate()
    if silently {
      entry.transfer.state = .failed(String(localized: "Canceled"))
      remove(entry.transfer)
      return
    }
    entry.transfer.state = .failed(String(localized: "The download didn’t finish."))
    onOutcome?(.failed(fileName: entry.fileName))
    onActivityChange?()
  }

  nonisolated static func uniqueURL(in directory: URL, for suggested: String) -> URL {
    let cleaned = suggested
      .replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: ":", with: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
    let name = cleaned.isEmpty ? String(localized: "Download") : cleaned
    let base = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    var candidate = directory.appending(path: name)
    var counter = 2
    while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
      let numbered = "\(base) \(counter)"
      candidate = directory.appending(path: ext.isEmpty ? numbered : "\(numbered).\(ext)")
      counter += 1
    }
    return candidate
  }
}

final class ProgressRelay: Sendable {
  private struct State {
    var pending: VideoDownloadProgress?
    var scheduled = false
    var last: ContinuousClock.Instant?
  }

  private let state = Mutex(State())
  private let deliver: @MainActor (VideoDownloadProgress) -> Void
  private let interval: Duration

  init(interval: Duration = .milliseconds(150), deliver: @escaping @MainActor (VideoDownloadProgress) -> Void) {
    self.interval = interval
    self.deliver = deliver
  }

  func offer(_ progress: VideoDownloadProgress) {
    let schedule = state.withLock { state -> Bool in
      state.pending = progress
      guard !state.scheduled else { return false }
      state.scheduled = true
      return true
    }
    guard schedule else { return }
    let interval = interval
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: interval)
      self?.flush()
    }
  }

  @MainActor
  func flush() {
    let pending = state.withLock { state -> VideoDownloadProgress? in
      state.scheduled = false
      defer { state.pending = nil }
      return state.pending
    }
    if let pending { deliver(pending) }
  }
}

@MainActor
final class DownloadDelegate: NSObject, WKDownloadDelegate {
  weak var manager: DownloadManager?

  init(manager: DownloadManager) {
    self.manager = manager
  }

  func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
    manager?.destination(for: download, suggestedFilename: suggestedFilename)
  }

  func downloadDidFinish(_ download: WKDownload) {
    manager?.finished(download)
  }

  func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
    manager?.failed(download)
  }
}
