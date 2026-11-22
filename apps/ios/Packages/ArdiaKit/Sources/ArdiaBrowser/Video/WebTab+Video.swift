#if canImport(UIKit)
import Foundation
import UIKit
import WebKit

public struct PressedVideo: Sendable {
  public var scan: VideoScan
  public var video: DetectedVideo
}

extension WebTab {
  static let videoFrameLimit = 12

  func noteVideoFrame(_ frame: WKFrameInfo) {
    let url = frame.request.url?.absoluteString
    videoFrames.removeAll { $0.request.url?.absoluteString == url }
    videoFrames.append(frame)
    if videoFrames.count > Self.videoFrameLimit { videoFrames.removeFirst(videoFrames.count - Self.videoFrameLimit) }
  }

  public func scanVideos() async -> VideoScan? {
    guard let webView else { return nil }
    let mainProbe = Task { @MainActor in await VideoDetection.probe(webView) }
    let frameProbes = videoFrames.map { frame in
      Task { @MainActor in await VideoDetection.probe(webView, frame: frame, timeout: .milliseconds(1200)) }
    }
    let main = await mainProbe.value
    var framed: [VideoProbeResult] = []
    for probe in frameProbes {
      if let result = await probe.value { framed.append(result) }
    }
    guard self.webView === webView, let main else { return nil }
    return VideoClassifier.scan(VideoDetection.merge(main, frames: framed))
  }

  func probeVideo(at viewPoint: CGPoint) async -> (scan: VideoScan, video: DetectedVideo?, inLink: Bool)? {
    guard let webView, let point = documentPoint(for: viewPoint), let result = await VideoDetection.probe(webView, documentPoint: point, timeout: .milliseconds(600)) else { return nil }
    let scan = VideoClassifier.scan(result.report)
    guard let hit = result.hit else { return (scan, nil, result.inLink) }
    let id = "video-\(hit)"
    let video = (scan.savable + scan.unsavable).first { $0.id == id }
      ?? result.report.videos.first { $0.index == hit }.map { element in
        DetectedVideo(id: id, kind: VideoClassifier.classify(src: element.src, hasMediaKeys: element.hasMediaKeys), element: element, pageURL: url, title: title)
      }
    return (scan, video, result.inLink)
  }

  func documentPoint(for viewPoint: CGPoint) -> CGPoint? {
    guard let webView else { return nil }
    let scrollView = webView.scrollView
    let content = scrollView.convert(viewPoint, from: webView)
    let scale = scrollView.zoomScale * pageZoom
    guard scale > 0 else { return nil }
    return CGPoint(x: content.x / scale, y: content.y / scale)
  }

  public func viewRect(for video: DetectedVideo) -> CGRect? {
    guard let webView, let rect = video.element?.rect, video.element?.frameURL == nil, rect.width > 1, rect.height > 1 else { return nil }
    let scrollView = webView.scrollView
    let scale = scrollView.zoomScale * pageZoom
    let content = CGRect(x: rect.x * scale, y: rect.y * scale, width: rect.width * scale, height: rect.height * scale)
    let inView = webView.convert(content, from: scrollView).intersection(webView.bounds)
    return inView.isNull || inView.width < 8 || inView.height < 8 ? nil : inView
  }

  public func thumbnail(for video: DetectedVideo, width: CGFloat = 240) async -> UIImage? {
    guard let webView, let rect = viewRect(for: video) else { return nil }
    let configuration = WKSnapshotConfiguration()
    configuration.rect = rect
    configuration.snapshotWidth = NSNumber(value: Double(min(width, rect.width)))
    configuration.afterScreenUpdates = false
    return try? await webView.takeSnapshot(configuration: configuration)
  }

  public func videoRequestContext(userAgent: String?) async -> VideoRequestContext {
    guard let webView else { return VideoRequestContext(userAgent: userAgent, referer: url) }
    let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
    return VideoRequestContext(cookies: cookies, userAgent: userAgent ?? webView.customUserAgent, referer: webView.url ?? url)
  }
}

@MainActor
final class VideoPressHandler: NSObject, UIGestureRecognizerDelegate, @preconcurrency UIEditMenuInteractionDelegate {
  private weak var tab: WebTab?
  private weak var webView: WKWebView?
  private let recognizer = UILongPressGestureRecognizer()
  private var menu: UIEditMenuInteraction?
  private var press: Task<PressedVideo?, Never>?
  private var pressedAt = ContinuousClock.now
  private var shown: PressedVideo?

  init(tab: WebTab, webView: WKWebView) {
    self.tab = tab
    self.webView = webView
    super.init()
    let menu = UIEditMenuInteraction(delegate: self)
    self.menu = menu
    recognizer.minimumPressDuration = 0.45
    recognizer.cancelsTouchesInView = false
    recognizer.delaysTouchesBegan = false
    recognizer.delaysTouchesEnded = false
    recognizer.delegate = self
    recognizer.addTarget(self, action: #selector(pressed(_:)))
    webView.addGestureRecognizer(recognizer)
    webView.addInteraction(menu)
  }

  func detach() {
    press?.cancel()
    press = nil
    webView?.removeGestureRecognizer(recognizer)
    if let menu { webView?.removeInteraction(menu) }
  }

  func pressedVideo() async -> PressedVideo? {
    if let press, ContinuousClock.now - pressedAt < .seconds(2) { return await press.value }
    guard let webView, let tab, recognizer.numberOfTouches > 0 else { return nil }
    let point = recognizer.location(in: webView)
    guard let found = await tab.probeVideo(at: point), let video = found.video else { return nil }
    return PressedVideo(scan: found.scan, video: video)
  }

  @objc private func pressed(_ recognizer: UILongPressGestureRecognizer) {
    guard recognizer.state == .began, let webView, let tab else { return }
    let point = recognizer.location(in: webView)
    pressedAt = .now
    let lookup = Task { @MainActor [weak tab] () -> (PressedVideo?, Bool) in
      guard let tab, let found = await tab.probeVideo(at: point), let video = found.video else { return (nil, false) }
      return (PressedVideo(scan: found.scan, video: video), found.inLink)
    }
    press = Task { await lookup.value.0 }
    Task { @MainActor [weak self] in
      let (found, inLink) = await lookup.value
      guard let self, let found, !inLink, self.tab === tab, recognizer.state != .cancelled else { return }
      shown = found
      menu?.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: point))
    }
  }

  func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
    guard let shown else { return nil }
    let download = UIAction(title: String(localized: "Download Video"), image: UIImage(systemName: "arrow.down.to.line.circle")) { [weak self] _ in
      guard let self, let tab else { return }
      tab.engine?.onVideoRequest?(tab, shown.scan, shown.video)
    }
    return UIMenu(children: [download])
  }

  func editMenuInteraction(_ interaction: UIEditMenuInteraction, willDismissMenuFor configuration: UIEditMenuConfiguration, animator: any UIEditMenuInteractionAnimating) {
    shown = nil
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
    true
  }
}
#endif
