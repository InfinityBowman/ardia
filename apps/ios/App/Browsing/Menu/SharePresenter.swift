import LinkPresentation
import UIKit

@MainActor
final class SharePresenter {
  static let shared = SharePresenter()

  private var prepared: UIActivityViewController?
  private var isHeld = false
  private var wantsPresent = false

  func prepare(_ url: URL, title: String?, holdsUntilRelease: Bool) {
    let controller = UIActivityViewController(activityItems: [ShareLinkSource(url: url, title: title)], applicationActivities: nil)
    controller.loadViewIfNeeded()
    prepared = controller
    isHeld = holdsUntilRelease && !wantsPresent
    HarnessProbe.mark("share.prepared")
    presentPrepared()
  }

  func expect() {
    prepared = nil
    wantsPresent = false
    isHeld = true
  }

  func release() {
    isHeld = false
    wantsPresent = true
    presentPrepared()
  }

  private func presentPrepared() {
    guard !isHeld, let controller = prepared, let presenter = VideoSaving.topViewController() else { return }
    prepared = nil
    wantsPresent = false
    if let popover = controller.popoverPresentationController {
      popover.sourceView = presenter.view
      popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY, width: 1, height: 1)
      popover.permittedArrowDirections = []
    }
    HarnessProbe.mark("share.present")
    presenter.present(controller, animated: true)
  }
}

final class ShareLinkSource: NSObject, UIActivityItemSource {
  let url: URL
  let metadata: LPLinkMetadata

  init(url: URL, title: String?) {
    self.url = url
    let metadata = LPLinkMetadata()
    metadata.originalURL = url
    metadata.url = url
    if let title, !title.isEmpty { metadata.title = title }
    self.metadata = metadata
  }

  func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { url }

  func activityViewController(_ controller: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { url }

  func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? { metadata }
}
