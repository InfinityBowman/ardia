import Foundation
import Synchronization
import WebKit

public struct VideoProbeResult: Codable, Equatable, Sendable {
  public var report: VideoPageReport
  public var hit: Int?
  public var inLink: Bool
}

public enum VideoDetection {
  static let noPoint = -1.0

  struct RawResult: Codable {
    var pageURL: String
    var title: String
    var userAgent: String?
    var videos: [VideoElementReport]
    var streams: [String]
    var metaVideos: [String]
    var hit: Int
    var inLink: Bool
  }

  public static func decode(_ json: String) -> VideoProbeResult? {
    guard let data = json.data(using: .utf8), let raw = try? JSONDecoder().decode(RawResult.self, from: data) else { return nil }
    let report = VideoPageReport(pageURL: raw.pageURL, title: raw.title, userAgent: raw.userAgent, videos: raw.videos, streams: raw.streams, metaVideos: raw.metaVideos)
    return VideoProbeResult(report: report, hit: raw.hit >= 0 ? raw.hit : nil, inLink: raw.inLink)
  }

  @MainActor
  public static func probe(_ webView: WKWebView, frame: WKFrameInfo? = nil, documentPoint: CGPoint? = nil, timeout: Duration = .seconds(2)) async -> VideoProbeResult? {
    let arguments: [String: Any] = [
      "pointX": documentPoint.map { Double($0.x) } ?? noPoint,
      "pointY": documentPoint.map { Double($0.y) } ?? noPoint,
    ]
    let json: String? = await withCheckedContinuation { continuation in
      let gate = ResumeGate(continuation)
      Task { @MainActor in
        let value = try? await webView.callAsyncJavaScript(script, arguments: arguments, in: frame, contentWorld: ReadableContent.world)
        gate.resume(value as? String)
      }
      Task {
        try? await Task.sleep(for: timeout)
        gate.resume(nil)
      }
    }
    guard let json else { return nil }
    return decode(json)
  }

  public static func merge(_ main: VideoProbeResult, frames: [VideoProbeResult]) -> VideoPageReport {
    var report = main.report
    for frame in frames {
      for var video in frame.report.videos {
        video.index = report.videos.count
        video.rect = nil
        if video.frameURL == nil { video.frameURL = frame.report.pageURL }
        report.videos.append(video)
      }
      report.streams.append(contentsOf: frame.report.streams.filter { !report.streams.contains($0) })
      report.metaVideos.append(contentsOf: frame.report.metaVideos.filter { !report.metaVideos.contains($0) })
    }
    return report
  }

  static let script = #"""
  const hasPoint = pointX >= 0 && pointY >= 0;
  const px = hasPoint ? pointX - window.scrollX : -1;
  const py = hasPoint ? pointY - window.scrollY : -1;
  const absolute = (src) => { if (!src) return ""; try { return new URL(src, document.baseURI).href; } catch (e) { return ""; } };
  const viewWidth = window.innerWidth, viewHeight = window.innerHeight;
  const videos = [];
  let hit = -1;
  const visit = (doc, dx, dy, depth) => {
    let list = [];
    try { list = doc.querySelectorAll("video"); } catch (e) { return; }
    for (const video of list) {
      const box = video.getBoundingClientRect();
      const x = box.left + dx, y = box.top + dy;
      const seenWidth = Math.max(0, Math.min(x + box.width, viewWidth) - Math.max(x, 0));
      const seenHeight = Math.max(0, Math.min(y + box.height, viewHeight) - Math.max(y, 0));
      const index = videos.length;
      if (hasPoint && box.width > 0 && px >= x && px <= x + box.width && py >= y && py <= y + box.height) hit = index;
      let sources = [];
      try { sources = [...video.querySelectorAll("source")].map((s) => ({ src: absolute(s.getAttribute("src")), type: s.getAttribute("type") })).filter((s) => s.src); } catch (e) {}
      videos.push({
        index,
        src: absolute(video.currentSrc || video.getAttribute("src") || ""),
        sources,
        poster: video.poster ? absolute(video.poster) : null,
        duration: Number.isFinite(video.duration) && video.duration > 0 ? video.duration : null,
        width: video.videoWidth || null,
        height: video.videoHeight || null,
        visibleArea: seenWidth * seenHeight,
        rect: { x: x + window.scrollX, y: y + window.scrollY, width: box.width, height: box.height },
        isPlaying: !video.paused && !video.ended && video.readyState > 2,
        hasMediaKeys: !!(video.mediaKeys || video.webkitKeys),
        hasStream: !!video.srcObject,
        frameURL: doc === document ? null : String(doc.location.href),
      });
    }
    if (depth > 3) return;
    for (const frame of doc.querySelectorAll("iframe")) {
      let inner = null;
      try { inner = frame.contentDocument; } catch (e) {}
      if (!inner) continue;
      const box = frame.getBoundingClientRect();
      visit(inner, dx + box.left + frame.clientLeft, dy + box.top + frame.clientTop, depth + 1);
    }
  };
  visit(document, 0, 0, 0);
  let inLink = false;
  if (hasPoint) {
    const element = document.elementFromPoint(px, py);
    inLink = !!(element && element.closest && element.closest("a[href]"));
  }
  let streams = [];
  try {
    streams = performance.getEntriesByType("resource")
      .filter((entry) => entry.initiatorType === "fetch" || entry.initiatorType === "xmlhttprequest")
      .map((entry) => entry.name)
      .filter((name) => /\.m3u8(\?|#|$)|\.mpd(\?|#|$)|[?&]format=m3u8/i.test(name));
  } catch (e) {}
  streams = [...new Set(streams)].slice(0, 24);
  const metas = [];
  for (const selector of ['meta[property="og:video:secure_url"]', 'meta[property="og:video:url"]', 'meta[property="og:video"]', 'meta[name="twitter:player:stream"]']) {
    for (const meta of document.querySelectorAll(selector)) { const url = absolute(meta.getAttribute("content")); if (url) metas.push(url); }
  }
  for (const node of document.querySelectorAll('script[type="application/ld+json"]')) {
    try {
      const walk = (value, depth) => {
        if (!value || typeof value !== "object" || depth > 6) return;
        if (Array.isArray(value)) { value.forEach((item) => walk(item, depth + 1)); return; }
        const type = value["@type"];
        const isVideo = type === "VideoObject" || (Array.isArray(type) && type.includes("VideoObject"));
        if (isVideo && typeof value.contentUrl === "string") metas.push(absolute(value.contentUrl));
        for (const key in value) walk(value[key], depth + 1);
      };
      walk(JSON.parse(node.textContent || "null"), 0);
    } catch (e) {}
  }
  return JSON.stringify({
    pageURL: String(location.href),
    title: document.title || "",
    userAgent: navigator.userAgent,
    videos,
    streams,
    metaVideos: [...new Set(metas.filter(Boolean))].slice(0, 8),
    hit,
    inLink,
  });
  """#
}

final class ResumeGate: Sendable {
  private let continuation: Mutex<CheckedContinuation<String?, Never>?>

  init(_ continuation: CheckedContinuation<String?, Never>) {
    self.continuation = Mutex(continuation)
  }

  func resume(_ value: String?) {
    let pending = continuation.withLock { stored in
      defer { stored = nil }
      return stored
    }
    pending?.resume(returning: value)
  }
}

public enum VideoFileName {
  public static func make(title: String, url: URL?) -> String {
    let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
    let cleaned = title.components(separatedBy: forbidden).joined(separator: " ")
      .split(whereSeparator: \.isWhitespace).joined(separator: " ")
      .trimmingCharacters(in: CharacterSet(charactersIn: ". -"))
    if !cleaned.isEmpty { return String(cleaned.prefix(80)).trimmingCharacters(in: .whitespaces) }
    let stem = url.map { ($0.lastPathComponent as NSString).deletingPathExtension } ?? ""
    let generic = ["", "/", "master", "index", "playlist", "manifest", "video", "media"]
    if !generic.contains(stem.lowercased()), stem.count <= 80 { return stem }
    return String(localized: "Video")
  }
}
