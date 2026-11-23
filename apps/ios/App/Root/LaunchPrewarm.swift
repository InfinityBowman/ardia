import SwiftUI
import UIKit

@MainActor
enum LaunchPrewarm {
  static let delay: Duration = .milliseconds(100)
  private static var done = false

  static func run(app: AppModel, in window: UIWindow?) {
    guard !done, let window, app.sheet == nil else { return }
    done = true
    HarnessProbe.mark("launch.prewarm")
    let toasts = VStack {
      ToastView(toast: .copiedURL)
      ToastView(toast: .downloaded("Prewarm", actions: [ToastAction(title: "Open", symbol: "arrow.up.forward.app", perform: {})], onOpen: {}))
    }
    let host = UIHostingController(rootView: ZStack { ArchiveView(); toasts }.environment(app))
    host.view.frame = window.bounds
    host.view.alpha = 0
    host.view.isUserInteractionEnabled = false
    host.view.accessibilityElementsHidden = true
    window.insertSubview(host.view, at: 0)
    host.view.layoutIfNeeded()
    DispatchQueue.main.async {
      host.view.removeFromSuperview()
    }
  }
}
