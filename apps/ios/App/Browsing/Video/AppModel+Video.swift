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
  func connectVideoDownloads() {
    web.onVideoRequest = { [weak self] page, scan, video in
      self?.handleVideoRequest(page, scan: scan, chosen: video)
    }
    web.downloads.onActivityChange = { [weak self] in
      guard let self else { return }
      downloadKeeper.update(running: web.downloads.hasRunningTransfers, fraction: web.downloads.summary.fraction)
    }
  }

  func downloadVideo(from tabID: UUID) {
    guard let page = web.existingWebTab(tabID), page.isLive else {
      browse.videoNotice = VideoNotice(reason: .noVideo)
      return
    }
    Task { [weak self] in
      guard let scan = await page.scanVideos() else {
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
        browse.videoNotice = VideoNotice(reason: Self.reason(for: chosen.kind))
      }
      return
    }
    switch scan.savable.count {
    case 0: browse.videoNotice = VideoNotice(reason: scan.reason)
    case 1: startVideoDownload(scan.savable[0], from: page, scan: scan)
    default: browse.videoChoices = VideoChoices(tabID: page.id, scan: scan)
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
    let name = VideoFileName.make(title: page.title.isEmpty ? scan.title : page.title, url: video.kind.url)
    let kind = video.kind
    Task { [weak self] in
      let context = await page.videoRequestContext(userAgent: scan.userAgent)
      guard let self else { return }
      web.downloads.startVideo(kind, fileName: name, context: context)
      toasts.show(Toast(String(localized: "Downloading Video"), symbol: "arrow.down.circle.fill", duration: .seconds(2.4)) { [weak self] in
        self?.sheet = .downloads
      })
    }
  }
}
