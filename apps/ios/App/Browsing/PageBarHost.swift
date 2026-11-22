import ArdiaDesign
import SwiftUI
import UIKit

final class BarScrollLink {
  static let hideDistance: CGFloat = 45
  static let settleResponse: Double = 0.12
  static let swipeCommit: CGFloat = 28
  static let swipeFlick: CGFloat = -350
  static let swipeReach: CGFloat = 60

  weak var bar: UIView?
  var isEnabled = true {
    didSet { if !isEnabled { show(animated: false) } }
  }
  var travel: CGFloat = 112 {
    didSet { if travel != oldValue { apply() } }
  }
  var onSwipeUp: () -> Void = {}

  private(set) var hidden: CGFloat = 0
  private var lift: CGFloat = 0
  private var lastOffset: CGFloat?
  private var animator: UIViewPropertyAnimator?

  func attach(_ scrollView: UIScrollView) {
    lastOffset = Self.offset(of: scrollView)
  }

  func scrolled(_ scrollView: UIScrollView) {
    let offset = Self.offset(of: scrollView)
    defer { lastOffset = offset }
    guard isEnabled, let last = lastOffset, scrollView.isTracking || scrollView.isDecelerating else { return }
    let bottom = scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height + scrollView.adjustedContentInset.top
    if offset <= 0 {
      if hidden > 0 { settle(to: 0) }
      return
    }
    guard offset < bottom, last < bottom else { return }
    let delta = offset - last
    guard delta != 0 else { return }
    if let animator, animator.isRunning {
      let target: CGFloat = delta > 0 ? 1 : 0
      if target == settleTarget { return }
      freeze()
    }
    hidden = min(max(hidden + delta / Self.hideDistance, 0), 1)
    apply()
  }

  func released(velocity: CGFloat) {
    guard isEnabled, hidden > 0, hidden < 1 else { return }
    if velocity < -120 {
      settle(to: 1)
    } else if velocity > 120 {
      settle(to: 0)
    } else {
      settle(to: hidden < 0.5 ? 0 : 1)
    }
  }

  func show(animated: Bool) {
    lastOffset = nil
    guard hidden != 0 || animator != nil else { return }
    if animated {
      settle(to: 0)
    } else {
      stopAnimator()
      hidden = 0
      apply()
    }
  }

  func hide() {
    settle(to: 1)
  }

  func swipeChanged(_ dy: CGFloat) {
    guard hidden == 0 else { return }
    let up = min(dy, 0)
    lift = -Self.swipeReach * (1 - exp(up / Self.swipeReach))
    apply()
  }

  func swipeEnded(_ dy: CGFloat, velocity: CGFloat) {
    guard hidden == 0 else { return }
    let commits = dy <= -Self.swipeCommit || (dy < -8 && velocity <= Self.swipeFlick)
    if commits { onSwipeUp() }
    let animator = UIViewPropertyAnimator(duration: 0.3, timingParameters: Self.spring(response: Self.settleResponse * 1.5))
    animator.addAnimations {
      self.lift = 0
      self.apply()
    }
    animator.startAnimation()
  }

  private var settleTarget: CGFloat = 0

  private func settle(to target: CGFloat) {
    freeze()
    settleTarget = target
    guard hidden != target else { return }
    let animator = UIViewPropertyAnimator(duration: 0.3, timingParameters: Self.spring(response: Self.settleResponse))
    animator.isInterruptible = true
    hidden = target
    animator.addAnimations { self.apply() }
    animator.addCompletion { [weak self] _ in self?.animator = nil }
    self.animator = animator
    animator.startAnimation()
  }

  private func freeze() {
    guard let animator else { return }
    self.animator = nil
    if animator.state == .active {
      animator.stopAnimation(false)
      animator.finishAnimation(at: .current)
    }
    if let bar, travel > 0 {
      let presented = bar.layer.presentation()?.affineTransform().ty ?? bar.transform.ty
      hidden = min(max((presented - lift) / travel, 0), 1)
      apply()
    }
  }

  private func stopAnimator() {
    guard let animator else { return }
    self.animator = nil
    if animator.state == .active {
      animator.stopAnimation(false)
      animator.finishAnimation(at: .end)
    }
  }

  private func apply() {
    bar?.transform = CGAffineTransform(translationX: 0, y: hidden * travel + lift)
  }

  private static func offset(of scrollView: UIScrollView) -> CGFloat {
    scrollView.contentOffset.y + scrollView.adjustedContentInset.top
  }

  private static func spring(response: Double) -> UISpringTimingParameters {
    let stiffness = pow(2 * .pi / response, 2)
    return UISpringTimingParameters(mass: 1, stiffness: stiffness, damping: 2 * sqrt(stiffness), initialVelocity: .zero)
  }
}

struct PageBarHost<Content: View>: UIViewRepresentable {
  let link: BarScrollLink
  let pager: TabPager
  let fade: CGFloat
  var register: (UIView) -> Void = { _ in }
  let content: Content

  func makeUIView(context: Context) -> PageBarContainer {
    let container = PageBarContainer(rootView: AnyView(content), fade: fade)
    register(container)
    link.bar = container.hosted
    container.swipe.addTarget(container, action: #selector(PageBarContainer.swiped(_:)))
    container.link = link
    let pan = TabPagerPanRecognizer()
    pan.maximumNumberOfTouches = 1
    pan.addTarget(pager, action: #selector(TabPager.panned(_:)))
    pan.onTouchDown = { [weak pager] in pager?.touchDown() }
    pan.onTouchEnded = { [weak pager] in pager?.touchEnded() }
    pan.delegate = container
    container.addGestureRecognizer(pan)
    return container
  }

  func updateUIView(_ container: PageBarContainer, context: Context) {
    container.fade = fade
    container.host.rootView = AnyView(content)
    link.bar = container.hosted
  }
}

final class PageBarContainer: UIView, UIGestureRecognizerDelegate {
  let host: UIHostingController<AnyView>
  let swipe = BarSwipeUpRecognizer()
  weak var link: BarScrollLink?
  var fade: CGFloat {
    didSet { if fade != oldValue { setNeedsLayout() } }
  }

  var hosted: UIView { host.view }

  init(rootView: AnyView, fade: CGFloat) {
    host = UIHostingController(rootView: rootView)
    self.fade = fade
    super.init(frame: .zero)
    host.safeAreaRegions = []
    host.view.backgroundColor = .clear
    addSubview(host.view)
    swipe.maximumNumberOfTouches = 1
    swipe.delegate = self
    addGestureRecognizer(swipe)
  }

  required init?(coder: NSCoder) { nil }

  override func layoutSubviews() {
    super.layoutSubviews()
    host.view.bounds = CGRect(origin: .zero, size: bounds.size)
    host.view.center = CGPoint(x: bounds.midX, y: bounds.midY)
    link?.travel = bounds.height
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }
    let local = convert(point, to: host.view)
    guard local.y >= fade, host.view.bounds.contains(local) else { return nil }
    return super.hitTest(point, with: event)
  }

  @objc func swiped(_ recognizer: BarSwipeUpRecognizer) {
    let dy = recognizer.translation(in: self).y
    switch recognizer.state {
    case .changed: link?.swipeChanged(dy)
    case .ended: link?.swipeEnded(dy, velocity: recognizer.velocity(in: self).y)
    case .cancelled, .failed: link?.swipeEnded(0, velocity: 0)
    default: break
    }
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
    false
  }
}

final class BarSwipeUpRecognizer: UIPanGestureRecognizer {
  static let beginDistance: CGFloat = 8
  private var start: CGPoint?

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    if start == nil { start = touches.first?.location(in: nil) }
    super.touchesBegan(touches, with: event)
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
    guard state == .possible, let start, let point = touches.first?.location(in: nil) else {
      super.touchesMoved(touches, with: event)
      return
    }
    let dx = point.x - start.x
    let dy = point.y - start.y
    if hypot(dx, dy) > Self.beginDistance, abs(dx) >= abs(dy) || dy > 0 {
      state = .failed
      return
    }
    super.touchesMoved(touches, with: event)
    if state == .possible, -dy >= Self.beginDistance { state = .began }
  }

  override func reset() {
    super.reset()
    start = nil
  }
}
