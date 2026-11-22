import ArdiaDesign
import SwiftUI
import UIKit

/// Hosts SwiftUI content whose bottom edge is glued to the top of the keyboard by Core Animation.
///
/// UIKit moves `keyboardLayoutGuide` inside the keyboard's own animation, so content pinned to it
/// travels in the same transaction as the keyboard: never a frame behind, and unaffected by a busy
/// main thread. Following the keyboard from SwiftUI (reading the safe area once it has changed, then
/// starting a main-thread animation) always trails it.
///
/// The hosted view is twice the container's height, its bottom half below the keyboard's top, so a
/// full-screen dim drawn in it covers the screen wherever the keyboard is. Content meant to ride the
/// keyboard is laid out to end at the hosted view's midline (see `KeyboardRiderLayout`).
struct KeyboardRider<Content: View>: UIViewControllerRepresentable {
  /// Stop following the keyboard and stay this far above the bottom (a drag that let the keyboard go).
  var heldLift: CGFloat?
  /// Fades the whole layer on the render server.
  var isVisible: Bool
  var isInteractive: Bool
  let content: Content

  func makeUIViewController(context: Context) -> KeyboardRiderController {
    KeyboardRiderController()
  }

  func updateUIViewController(_ controller: KeyboardRiderController, context: Context) {
    controller.update(content: AnyView(content), heldLift: heldLift, isVisible: isVisible, isInteractive: isInteractive)
  }
}

/// Lays out the hosted content: the dim fills everything, the riding content ends at the midline.
struct KeyboardRiderLayout<Dim: View, Rider: View>: View {
  let dim: Dim
  let rider: Rider

  var body: some View {
    GeometryReader { proxy in
      let half = proxy.size.height / 2
      ZStack(alignment: .top) {
        dim.frame(width: proxy.size.width, height: proxy.size.height)
        rider
          .frame(width: proxy.size.width, height: half, alignment: .bottom)
      }
    }
    .ignoresSafeArea()
  }
}

/// Takes no touches itself; only the hosted content does.
private final class RiderContainer: UIView {
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let hit = super.hitTest(point, with: event)
    return hit === self ? nil : hit
  }
}

final class KeyboardRiderController: UIViewController {
  private let host = UIHostingController(rootView: AnyView(EmptyView()))
  private var follow: NSLayoutConstraint?
  private var hold: NSLayoutConstraint?
  private var isVisible = false
  private var pendingReveal: DispatchWorkItem?
  // Block-based observers are removed when the token is released; `nonisolated(unsafe)` lets the
  // nonisolated deinit drop it.
  nonisolated(unsafe) private var keyboardObserver: NSObjectProtocol?

  override func loadView() {
    view = RiderContainer()
    view.backgroundColor = .clear
    view.isHidden = true
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    addChild(host)
    host.view.backgroundColor = .clear
    // The hosted SwiftUI must not move itself for the keyboard; the constraint does that.
    if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
    host.view.translatesAutoresizingMaskIntoConstraints = false
    host.view.alpha = 0
    view.addSubview(host.view)
    host.didMove(toParent: self)
    // Without a keyboard (a hardware one, or while it is still coming) the guide rests on the
    // safe area, so the tray sits above the home indicator.
    view.keyboardLayoutGuide.usesBottomSafeArea = true
    let follow = host.view.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: 0)
    let hold = host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    NSLayoutConstraint.activate([
      host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      host.view.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 2),
      follow,
    ])
    self.follow = follow
    self.hold = hold
    keyboardObserver = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.revealNow() }
    }
  }

  /// The tray appears the moment the keyboard starts up, so it never floats alone above where the
  /// keyboard is about to be. Without a keyboard coming (hardware keyboard, voice) it shows shortly after.
  private func revealNow() {
    guard isVisible, let pending = pendingReveal else { return }
    pending.cancel()
    pendingReveal = nil
    UIView.performWithoutAnimation { host.view.layoutIfNeeded() }
    UIView.animate(withDuration: 0.05, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
      self.host.view.alpha = 1
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    // The hosted view's lower half hangs below the keyboard's top.
    let half = view.bounds.height
    if follow?.constant != half { follow?.constant = half }
  }

  func update(content: AnyView, heldLift: CGFloat?, isVisible visible: Bool, isInteractive: Bool) {
    host.rootView = content
    host.view.isUserInteractionEnabled = isInteractive

    if let heldLift {
      hold?.constant = view.bounds.height - heldLift
      if follow?.isActive == true {
        follow?.isActive = false
        hold?.isActive = true
      }
    } else if hold?.isActive == true {
      hold?.isActive = false
      follow?.isActive = true
    }

    guard visible != isVisible else { return }
    isVisible = visible
    if visible {
      view.isHidden = false
      // Lay the new content out now, outside any animation, so the keyboard's animation block
      // (which starts in this same pass) moves it as a whole instead of growing it from nothing.
      UIView.performWithoutAnimation {
        view.layoutIfNeeded()
        host.view.layoutIfNeeded()
      }
      let reveal = DispatchWorkItem { [weak self] in self?.revealNow() }
      pendingReveal = reveal
      // Already up (moving between fields, a hardware keyboard): nothing to wait for.
      let keyboardUp = view.keyboardLayoutGuide.layoutFrame.height > view.safeAreaInsets.bottom + 40
      DispatchQueue.main.asyncAfter(deadline: .now() + (keyboardUp ? 0 : 0.3), execute: reveal)
    } else {
      pendingReveal?.cancel()
      pendingReveal = nil
      UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
        self.host.view.alpha = 0
      } completion: { [weak self] _ in
        guard let self, !self.isVisible else { return }
        self.view.isHidden = true
      }
    }
  }
}
