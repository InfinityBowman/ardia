import ArdiaBrowser
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class DownloadActivity {
  struct Finished: Identifiable, Equatable {
    let url: URL
    var savedToPhotos = false

    var id: URL { url }
    var isVideo: Bool { VideoSaving.isVideo(url) }
  }

  static let pendingTimeout: Duration = .seconds(15)
  static let recentLimit = 3

  private(set) var isPending = false
  private(set) var recent: [Finished] = []
  private(set) var art: [UUID: UIImage] = [:]
  @ObservationIgnored var onPendingChange: (() -> Void)?
  @ObservationIgnored private var pendingTimeout: Task<Void, Never>?
  @ObservationIgnored private var shownInMenu: Set<URL> = []
  @ObservationIgnored private var deferredToast: (toast: Toast, at: ContinuousClock.Instant)?
  static let deferredToastLifetime: Duration = .seconds(600)

  func deferToast(_ toast: Toast) {
    deferredToast = (toast, .now)
  }

  func takeDeferredToast() -> Toast? {
    defer { deferredToast = nil }
    guard let deferredToast, ContinuousClock.now - deferredToast.at < Self.deferredToastLifetime else { return nil }
    return deferredToast.toast
  }

  func beginPending() {
    pendingTimeout?.cancel()
    pendingTimeout = Task { [weak self] in
      try? await Task.sleep(for: Self.pendingTimeout)
      guard !Task.isCancelled else { return }
      self?.endPending()
    }
    guard !isPending else { return }
    isPending = true
    onPendingChange?()
  }

  func endPending() {
    pendingTimeout?.cancel()
    pendingTimeout = nil
    guard isPending else { return }
    isPending = false
    onPendingChange?()
  }

  func setArt(_ image: UIImage, for transfer: DownloadTransfer) {
    art[transfer.id] = image
  }

  func finished(_ url: URL, art image: UIImage?) {
    recent.removeAll { $0.url == url }
    recent.insert(Finished(url: url), at: 0)
    if recent.count > Self.recentLimit { recent.removeLast(recent.count - Self.recentLimit) }
    if let image { DownloadThumbnails.shared.store(image, for: url) }
  }

  func forget(_ transfer: UUID) {
    art[transfer] = nil
  }

  func keepArt(for transfers: [DownloadTransfer]) {
    let live = Set(transfers.map(\.id))
    guard art.keys.contains(where: { !live.contains($0) }) else { return }
    art = art.filter { live.contains($0.key) }
  }

  func markSaved(_ url: URL) {
    guard let index = recent.firstIndex(where: { $0.url == url }) else { return }
    recent[index].savedToPhotos = true
  }

  func menuShowed(_ urls: [URL]) {
    shownInMenu.formUnion(urls)
  }

  func menuClosed() {
    guard !shownInMenu.isEmpty else { return }
    recent.removeAll { shownInMenu.contains($0.url) }
    shownInMenu.removeAll()
  }

  func dismiss(_ url: URL) {
    recent.removeAll { $0.url == url }
    shownInMenu.remove(url)
  }

  func clearRecent() {
    recent.removeAll()
    shownInMenu.removeAll()
  }
}
