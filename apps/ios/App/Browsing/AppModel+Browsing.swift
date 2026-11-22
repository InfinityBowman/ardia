import ArdiaBrowser
import ArdiaSync
import Foundation
import UIKit
import WebKit

extension AppModel {
  var currentPage: WebTab? {
    guard let id = tabs.selectedTabID, tabs.tab(id) != nil else { return nil }
    return web.existingWebTab(id)
  }

  @discardableResult
  func copyLink(of tabID: UUID) -> Bool {
    guard let tab = tabs.tab(tabID), let url = URL(string: tab.url), BrowserURL.isSyncable(tab.url) else { return false }
    web.copyLink(url)
    browse.showTitleFeedback(String(localized: "Copied URL"))
    return true
  }

  func announceDownload(_ outcome: DownloadOutcome) {
    switch outcome {
    case .finished(let file, let transfer):
      HarnessProbe.mark("download.finished")
      downloadActivity.finished(file, art: downloadActivity.art[transfer])
      downloadActivity.forget(transfer)
      if !web.downloads.hasRunningTransfers { downloadRing.finishedLast() }
      announce(downloadedToast(file))
    case .failed(let fileName):
      HarnessProbe.mark("download.failed")
      downloadKeeper.noteFailure()
      announce(.downloadFailed(fileName))
    case .videoFailed(let fileName, let message):
      HarnessProbe.mark("download.failed")
      downloadKeeper.noteFailure()
      announce(Toast(String(localized: "Couldn’t Download Video"), detail: fileName, symbol: "exclamationmark.triangle.fill", duration: .seconds(4), actions: [
        ToastAction(title: String(localized: "Details"), symbol: "list.bullet", isProminent: true) { [weak self] in self?.showDownloads() },
      ]) { [weak self] in
        self?.showDownloads()
      })
      AccessibilityNotification.Announcement(message).post()
    }
  }

  private func announce(_ toast: Toast) {
    if UIApplication.shared.applicationState == .active {
      toasts.show(toast)
    } else {
      downloadActivity.deferToast(toast)
    }
  }

  func downloadedToast(_ file: URL) -> Toast {
    let share = ToastAction(title: String(localized: "Share"), symbol: "square.and.arrow.up") { VideoSaving.share(file) }
    if VideoSaving.canSaveToPhotos(file) {
      let save = ToastAction(title: String(localized: "Save to Photos"), symbol: "photo.badge.plus", isProminent: true) { [weak self] in
        self?.saveVideoToPhotos(file)
      }
      return .downloaded(file.lastPathComponent, actions: [save, share]) { [weak self] in self?.showDownloads() }
    }
    let open = ToastAction(title: String(localized: "Open"), symbol: "doc.text.magnifyingglass", isProminent: true) { [weak self] in
      self?.openDownloadedFile(file)
    }
    return .downloaded(file.lastPathComponent, actions: [open, share]) { [weak self] in self?.openDownloadedFile(file) }
  }

  func openDownloadedFile(_ file: URL) {
    downloadActivity.dismiss(file)
    VideoSaving.open(file)
  }

  func showDownloads() {
    browse.isToolbarPresented = false
    downloadActivity.clearRecent()
    sheet = .downloads
  }

  func shareCurrentPage() {
    guard let tab = tabs.selectedTab else { return }
    sharePage(tab.id)
  }

  func sharePage(_ tabID: UUID) {
    guard let tab = tabs.tab(tabID), let url = URL(string: tab.url), BrowserURL.isSyncable(tab.url) else { return }
    web.share(url)
  }

  func pinToMac(_ tabID: UUID) {
    guard let tab = tabs.tab(tabID) else { return }
    guard sync.isEnabled else {
      toasts.show(Toast(String(localized: "Sync With Your Mac to Pin Tabs"), symbol: "laptopcomputer") { [weak self] in
        self?.sheet = .syncSetup
      })
      return
    }
    pinToMac(tab, inPageMenu: true)
  }

  func setNightShade(_ on: Bool, for page: WebTab) {
    guard let host = page.host else { return }
    preferences.update(host, isPrivate: page.isPrivate) { $0.nightShade = on ? .always : .disabled }
  }

  func toggleDesktopSite(for page: WebTab) {
    guard let webView = page.webView else { return }
    let wantsDesktop = !browse.desktopTabs.contains(page.id)
    if wantsDesktop {
      browse.desktopTabs.insert(page.id)
      webView.customUserAgent = Self.desktopUserAgent
    } else {
      browse.desktopTabs.remove(page.id)
      webView.customUserAgent = nil
    }
    page.reload()
  }

  static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Safari/605.1.15"

  func translate(_ page: WebTab) {
    guard let url = page.url, var components = URLComponents(string: "https://translate.google.com/translate") else { return }
    let language = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en"
    components.queryItems = [
      URLQueryItem(name: "sl", value: "auto"),
      URLQueryItem(name: "tl", value: language),
      URLQueryItem(name: "u", value: url.absoluteString),
    ]
    if let target = components.url { page.load(target) }
  }

  func toggleBlockers(for page: WebTab) {
    if let message = page.setBlockersEnabled(!page.blockersEnabled) {
      toasts.show(Toast(message, symbol: page.blockersEnabled ? "hand.raised.fill" : "hand.raised.slash"))
    }
  }

  func openInDefaultBrowser(_ page: WebTab) {
    guard let url = page.url else { return }
    UIApplication.shared.open(url)
  }

  func goBackToSearchIfEmpty() {
    if tabs.selectedTab == nil, surface == .browsing { surface = .search }
  }
}
