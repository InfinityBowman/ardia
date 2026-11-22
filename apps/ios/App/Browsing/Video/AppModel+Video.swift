import ArdiaBrowser
import Foundation
import UIKit

struct VideoChoices: Identifiable {
  let id = UUID()
  let tabID: UUID
  let scan: VideoScan
}

struct VideoNotice: Identifiable, Equatable {
  let id = UUID()
  let reason: VideoUnsavableReason

  var title: String {
    switch reason {
    case .noVideo: String(localized: "No Video Found")
    case .mediaSource, .protected, .live: String(localized: "This Page’s Video Can’t Be Saved")
    }
  }

  var message: String {
    switch reason {
    case .noVideo: String(localized: "Ardia didn’t find a video on this page. If one is still loading, start playing it and try again.")
    case .mediaSource: String(localized: "This site streams its video in pieces only its own player can put together, so there’s no file Ardia can save.")
    case .protected: String(localized: "This video is copy-protected by the site, so it can’t be saved.")
    case .live: String(localized: "Live video can’t be saved. Try again after the broadcast ends.")
    }
  }
}

extension AppModel {
  var isDownloading: Bool {
    downloadActivity.isPending || web.downloads.hasRunningTransfers
  }

  func connectVideoDownloads() {
    web.onVideoRequest = { [weak self] page, scan, video in
      self?.handleVideoRequest(page, scan: scan, chosen: video)
    }
    downloadRing.manager = web.downloads
    downloadRing.activity = downloadActivity
    downloadActivity.onPendingChange = { [weak self] in
      guard let self else { return }
      if downloadActivity.isPending { downloadRing.refresh() } else { downloadRing.expectationSettled() }
    }
    web.downloads.onActivityChange = { [weak self] in
      guard let self else { return }
      downloadKeeper.update(running: web.downloads.hasRunningTransfers, fraction: web.downloads.summary.fraction)
      downloadRing.refresh()
      downloadActivity.keepArt(for: web.downloads.transfers)
    }
    NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.showDeferredDownloadToast() }
    }
  }

  func showDeferredDownloadToast() {
    guard let toast = downloadActivity.takeDeferredToast() else { return }
    toasts.show(toast)
  }

  func downloadVideo(from tabID: UUID) {
    downloadActivity.beginPending()
    guard let page = web.existingWebTab(tabID), page.isLive else {
      downloadActivity.endPending()
      browse.videoNotice = VideoNotice(reason: .noVideo)
      return
    }
    Task { [weak self] in
      guard let scan = await page.scanVideos() else {
        self?.downloadActivity.endPending()
        self?.browse.videoNotice = VideoNotice(reason: .noVideo)
        return
      }
      self?.handleVideoRequest(page, scan: scan, chosen: nil)
    }
  }

  func handleVideoRequest(_ page: WebTab, scan: VideoScan, chosen: DetectedVideo?) {
    if let chosen {
      if chosen.kind.isSavable {
        startVideoDownload(chosen, from: page, scan: scan)
      } else {
        downloadActivity.endPending()
        browse.videoNotice = VideoNotice(reason: Self.reason(for: chosen.kind))
      }
      return
    }
    switch scan.savable.count {
    case 0:
      downloadActivity.endPending()
      browse.videoNotice = VideoNotice(reason: scan.reason)
    case 1:
      startVideoDownload(scan.savable[0], from: page, scan: scan)
    default:
      downloadActivity.endPending()
      browse.videoChoices = VideoChoices(tabID: page.id, scan: scan)
    }
  }

  static func reason(for kind: VideoSourceKind) -> VideoUnsavableReason {
    switch kind {
    case .protected: .protected
    case .mediaSource, .dash: .mediaSource
    default: .noVideo
    }
  }

  func startVideoDownload(_ video: DetectedVideo, from page: WebTab, scan: VideoScan) {
    browse.videoChoices = nil
    downloadActivity.beginPending()
    HarnessProbe.mark("download.start")
    let name = VideoFileName.make(title: page.title.isEmpty ? scan.title : page.title, url: video.kind.url)
    let kind = video.kind
    Task { [weak self] in
      let context = await page.videoRequestContext(userAgent: scan.userAgent)
      guard let self else { return }
      let transfer = web.downloads.startVideo(kind, fileName: name, context: context)
      downloadActivity.endPending()
      toasts.show(Toast(String(localized: "Downloading Video"), detail: name, symbol: "arrow.down.circle.fill", duration: .seconds(2.4)) { [weak self] in
        self?.sheet = .downloads
      })
      if let image = await page.thumbnail(for: video) {
        downloadActivity.setArt(image, for: transfer)
      } else if let poster = video.element?.poster.flatMap(URL.init(string:)), let image = await Self.loadPoster(poster) {
        downloadActivity.setArt(image, for: transfer)
      }
    }
  }

  nonisolated static func loadPoster(_ url: URL) async -> UIImage? {
    guard url.scheme == "https" || url.scheme == "http",
          let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
    return UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 160, height: 160))
  }
}
