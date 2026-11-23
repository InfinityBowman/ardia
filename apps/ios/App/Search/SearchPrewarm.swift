import ArdiaDesign
import SwiftUI
import UIKit

@MainActor
enum SearchPrewarm {
  static let delay: Duration = .milliseconds(400)
  private static var done = false

  static func run(app: AppModel, environment: DeckStageEnvironment, in window: UIWindow?) {
    guard !done, let window, app.sheet == nil, app.browse.search == nil else { return }
    done = true
    HarnessProbe.mark("search.prewarm")
    let safeBottom = window.safeAreaInsets.bottom
    let geometry = TabsDeckGeometry(container: window.bounds.size, safeTop: window.safeAreaInsets.top, safeBottom: safeBottom)
    let request = BrowseSession.SearchRequest(origin: .page, initialText: "", selectsAll: false, incognitoOnCancel: nil)
    let content = ZStack {
      ProfileBackdrop(themed: true)
      StartSpaces(geometry: geometry)
      StartPageBar(
        safeBottom: safeBottom,
        plus: PlusActions(isIncognito: false, canReopen: false, newTab: {}, newRegularTab: {}, newIncognitoTab: {}, reopen: {}),
        tabs: {},
        settings: {}
      )
      SearchTray(
        request: request,
        isFocused: .constant(false),
        maxHeight: BrowseLayout.sheetAboveKeyboard,
        dismissDrag: DragGesture(),
        pull: TrayPull(changed: { _ in }, ended: { _, _ in }),
        barLineAboveBottom: BrowseLayout.barLine(safeBottom: safeBottom) - safeBottom
      )
    }
    .deckStageEnvironment(app, environment)
    let host = UIHostingController(rootView: content)
    host.view.frame = window.bounds
    host.view.alpha = 0
    host.view.isUserInteractionEnabled = false
    host.view.accessibilityElementsHidden = true
    window.insertSubview(host.view, at: 0)
    host.view.layoutIfNeeded()
    DispatchQueue.main.async {
      host.view.removeFromSuperview()
      SearchMotion.rider?.warmPreview()
    }
  }
}
