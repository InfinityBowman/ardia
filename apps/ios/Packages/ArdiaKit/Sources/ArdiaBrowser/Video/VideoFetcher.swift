import CommonCrypto
import Foundation

public enum VideoDownloadError: Error, Equatable, Sendable {
  case protected
  case live
  case mediaSource
  case unsupportedFormat
  case refused(Int)
  case network
  case insecure
  case emptyStream
  case assemblyFailed
  case storage

  public var message: String {
    switch self {
    case .protected: String(localized: "This video is copy-protected, so it can’t be saved.")
    case .live: String(localized: "Live video can’t be saved. Try again after the broadcast ends.")
    case .mediaSource: String(localized: "This site streams its video in a way that can’t be saved.")
    case .unsupportedFormat: String(localized: "This video uses a format Ardia can’t save.")
    case .refused(let status): status == 403 || status == 401
      ? String(localized: "The site refused the download. Reload the page and try again.")
      : String(localized: "The site couldn’t send the video (error \(status)).")
    case .network: String(localized: "The connection was lost. Try again.")
    case .insecure: String(localized: "This video isn’t sent over a secure connection.")
    case .emptyStream: String(localized: "The site sent an empty video.")
    case .assemblyFailed: String(localized: "The video’s pieces couldn’t be put together.")
    case .storage: String(localized: "There isn’t enough space to save the video.")
    }
  }
}

public struct VideoRequestContext: Sendable {
  public var cookies: [HTTPCookie]
  public var userAgent: String?
  public var referer: URL?

  public init(cookies: [HTTPCookie] = [], userAgent: String? = nil, referer: URL? = nil) {
    self.cookies = cookies
    self.userAgent = userAgent
    self.referer = referer
  }
}

public final class VideoFetcher: Sendable {
  let session: URLSession
  let cookies: HTTPCookieStorage?
  let userAgent: String?
  let referer: URL?
  let attempts: Int

  public init(context: VideoRequestContext, protocolClasses: [AnyClass]? = nil, attempts: Int = 4) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpMaximumConnectionsPerHost = 6
    configuration.timeoutIntervalForRequest = 30
    configuration.waitsForConnectivity = false
    configuration.httpCookieAcceptPolicy = .always
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.httpShouldSetCookies = false
    if let storage = configuration.httpCookieStorage {
      for cookie in context.cookies { storage.setCookie(cookie) }
    }
    cookies = configuration.httpCookieStorage
    if let protocolClasses { configuration.protocolClasses = protocolClasses + (configuration.protocolClasses ?? []) }
    session = URLSession(configuration: configuration)
    userAgent = context.userAgent
    referer = context.referer
    self.attempts = attempts
  }

  deinit {
    session.invalidateAndCancel()
  }

  public func request(_ url: URL, range: HLSByteRange? = nil) -> URLRequest {
    var request = URLRequest(url: url)
    if let userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
    if let referer, referer.scheme?.hasPrefix("http") == true { request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer") }
    if let range { request.setValue(range.httpHeader, forHTTPHeaderField: "Range") }
    request.httpShouldHandleCookies = false
    if let matching = cookies?.cookies(for: url), !matching.isEmpty {
      for (field, value) in HTTPCookie.requestHeaderFields(with: matching) { request.setValue(value, forHTTPHeaderField: field) }
    }
    request.setValue("*/*", forHTTPHeaderField: "Accept")
    return request
  }

  public func data(_ url: URL, range: HLSByteRange? = nil) async throws -> Data {
    try await retrying {
      let (data, response) = try await self.session.data(for: self.request(url, range: range))
      let status = (response as? HTTPURLResponse)?.statusCode ?? 200
      self.remember(response)
      guard (200..<300).contains(status) else { throw VideoDownloadError.refused(status) }
      if let range, status == 200, data.count > range.length {
        guard range.offset + range.length <= data.count else { throw VideoDownloadError.emptyStream }
        return data.subdata(in: range.offset..<(range.offset + range.length))
      }
      return data
    }
  }

  func remember(_ response: URLResponse) {
    guard let http = response as? HTTPURLResponse, let url = http.url, let fields = http.allHeaderFields as? [String: String] else { return }
    let received = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
    guard !received.isEmpty else { return }
    cookies?.setCookies(received, for: url, mainDocumentURL: nil)
  }

  public func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws -> URLResponse {
    var resumeData: Data?
    var lastError: Error = VideoDownloadError.network
    for attempt in 0..<attempts {
      if attempt > 0 { try await Task.sleep(for: .seconds(pow(2, Double(attempt - 1)) * 0.5)) }
      do {
        let (response, nextResume) = try await downloadOnce(url, resumeData: resumeData, to: destination, progress: progress)
        if let response { return response }
        resumeData = nextResume
      } catch let error as VideoDownloadError {
        if case .refused(let status) = error, status < 500 { throw error }
        lastError = error
      } catch is CancellationError {
        throw CancellationError()
      } catch let error as URLError {
        if error.code == .cancelled { throw CancellationError() }
        if error.code == .appTransportSecurityRequiresSecureConnection { throw VideoDownloadError.insecure }
        resumeData = error.downloadTaskResumeData
        lastError = VideoDownloadError.network
      }
    }
    throw lastError
  }

  private func downloadOnce(_ url: URL, resumeData: Data?, to destination: URL, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws -> (URLResponse?, Data?) {
    let box = DownloadTaskBox()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(URLResponse?, Data?), Error>) in
        let handler: @Sendable (URL?, URLResponse?, Error?) -> Void = { location, response, error in
          box.stopObserving()
          if let error {
            continuation.resume(throwing: error)
            return
          }
          guard let location, let response else {
            continuation.resume(throwing: VideoDownloadError.network)
            return
          }
          let status = (response as? HTTPURLResponse)?.statusCode ?? 200
          guard (200..<300).contains(status) else {
            continuation.resume(throwing: VideoDownloadError.refused(status))
            return
          }
          do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            continuation.resume(returning: (response, nil))
          } catch {
            continuation.resume(throwing: VideoDownloadError.storage)
          }
        }
        let task = resumeData.map { session.downloadTask(withResumeData: $0, completionHandler: handler) }
          ?? session.downloadTask(with: request(url), completionHandler: handler)
        box.start(task, progress: progress)
      }
    } onCancel: {
      box.cancel()
    }
  }

  private func retrying<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
    var lastError: Error = VideoDownloadError.network
    for attempt in 0..<attempts {
      if attempt > 0 { try await Task.sleep(for: .seconds(pow(2, Double(attempt - 1)) * 0.5)) }
      do {
        return try await operation()
      } catch let error as VideoDownloadError {
        if case .refused(let status) = error, status < 500, status != 429 { throw error }
        lastError = error
      } catch let error as URLError {
        if error.code == .cancelled { throw CancellationError() }
        if error.code == .appTransportSecurityRequiresSecureConnection { throw VideoDownloadError.insecure }
        lastError = VideoDownloadError.network
      }
      try Task.checkCancellation()
    }
    throw lastError
  }
}

final class DownloadTaskBox: @unchecked Sendable {
  private let lock = NSLock()
  private var task: URLSessionDownloadTask?
  private var observation: NSKeyValueObservation?
  private var cancelled = false

  func start(_ task: URLSessionDownloadTask, progress: @escaping @Sendable (Int64, Int64?) -> Void) {
    lock.lock()
    self.task = task
    observation = task.observe(\.countOfBytesReceived, options: [.new]) { task, _ in
      let expected = task.countOfBytesExpectedToReceive
      progress(task.countOfBytesReceived, expected > 0 ? expected : nil)
    }
    let shouldCancel = cancelled
    lock.unlock()
    if shouldCancel { task.cancel() } else { task.resume() }
  }

  func stopObserving() {
    lock.lock()
    observation?.invalidate()
    observation = nil
    lock.unlock()
  }

  func cancel() {
    lock.lock()
    cancelled = true
    let task = task
    lock.unlock()
    task?.cancel()
  }
}

public enum SegmentCipher {
  public static func decrypt(_ data: Data, key: Data, iv: Data) throws -> Data {
    guard key.count == kCCKeySizeAES128, iv.count == kCCBlockSizeAES128 else { throw VideoDownloadError.unsupportedFormat }
    var output = Data(count: data.count + kCCBlockSizeAES128)
    var moved = 0
    let capacity = output.count
    let status = output.withUnsafeMutableBytes { out in
      data.withUnsafeBytes { input in
        key.withUnsafeBytes { keyBytes in
          iv.withUnsafeBytes { ivBytes in
            CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                    keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                    input.baseAddress, data.count, out.baseAddress, capacity, &moved)
          }
        }
      }
    }
    guard status == kCCSuccess else { throw VideoDownloadError.assemblyFailed }
    output.removeSubrange(moved...)
    return output
  }

  public static func encrypt(_ data: Data, key: Data, iv: Data) -> Data {
    var output = Data(count: data.count + kCCBlockSizeAES128)
    var moved = 0
    let capacity = output.count
    _ = output.withUnsafeMutableBytes { out in
      data.withUnsafeBytes { input in
        key.withUnsafeBytes { keyBytes in
          iv.withUnsafeBytes { ivBytes in
            CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                    keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                    input.baseAddress, data.count, out.baseAddress, capacity, &moved)
          }
        }
      }
    }
    output.removeSubrange(moved...)
    return output
  }
}
