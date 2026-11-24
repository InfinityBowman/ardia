import ArdiaBrowser
import ArdiaDesign
import SwiftUI
import UIKit
import WebKit

struct WebPageView: UIViewRepresentable {
  let page: WebTab?
  var tab: BrowserTab?
  var cover: UIImage?
  var swipeMode: SwipeNavigationMode
  var topInset: CGFloat = 0
  var bottomInset: CGFloat
  var barLink: BarScrollLink?
  var edgePager: TabPager?
  var onTone: (UUID, PageTone) -> Void = { _, _ in }

  func makeUIView(context: Context) -> PageContainerView {
    let view = PageContainerView()
    view.backdrop = context.environment.profileLook.surface
    return view
  }

  func updateUIView(_ view: PageContainerView, context: Context) {
    view.backdrop = context.environment.profileLook.surface
    view.swipeMode = swipeMode
    view.onTone = onTone
    view.topInset = topInset
    view.bottomInset = bottomInset
    view.barLink = barLink
    view.edgePager = edgePager
    guard let page else {
      view.show(nil, cover: nil, isLoading: false, progress: 0)
      return
    }
    view.placeholderTab = tab
    view.show(page, cover: cover, isLoading: page.isLoading, progress: page.progress, isLive: page.webView != nil)
    view.endRefreshingIfReloaded(isLoading: page.isLoading)
  }

  static func dismantleUIView(_ view: PageContainerView, coordinator: ()) {
    view.detach()
  }
}

final class PageContainerView: UIView, UIGestureRecognizerDelegate {
  enum Reveal {
    case none
    case afterReattach
    case whenPainted(sawLoading: Bool)
  }

  var swipeMode: SwipeNavigationMode = .anywhere
  var onTone: ((UUID, PageTone) -> Void)?
  var topInset: CGFloat = 0 {
    didSet { if topInset != oldValue { applyInsets() } }
  }
  var bottomInset: CGFloat = 0 {
    didSet { if bottomInset != oldValue { applyInsets() } }
  }

  var placeholderTab: BrowserTab?
  weak var barLink: BarScrollLink?
  weak var edgePager: TabPager? {
    didSet {
      guard edgePager !== oldValue else { return }
      for edge in edgePans {
        if let oldValue { edge.removeTarget(oldValue, action: #selector(TabPager.panned(_:))) }
        if let edgePager { edge.addTarget(edgePager, action: #selector(TabPager.panned(_:))) }
      }
    }
  }
  private let edgePans = [EdgeStartPanRecognizer(edge: .left), EdgeStartPanRecognizer(edge: .right)]
  private weak var linkedPan: UIPanGestureRecognizer?
  var backdrop: Color = ProfileLook.plum.surface {
    didSet { backgroundColor = UIColor(backdrop) }
  }
  private var placeholderHost: UIViewController?
  private weak var page: WebTab?
  private weak var webView: WKWebView?
  private let refreshControl = UIRefreshControl()
  private let coverView = UIImageView()
  private var reveal: Reveal = .none
  private var revealPending = false
  private var refreshCommitBaseline: Int?
  private var revealDeadline: Task<Void, Never>?
  private var layoutObservation: NSKeyValueObservation?
  private var scrollObservation: NSKeyValueObservation?
  private var toneTask: Task<Void, Never>?
  private var lastScroll: TimeInterval = 0
  private var wasLoading = false
  private lazy var swipePan = UIPanGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
  private var swipe: SwipeState?
  private var swipeAnimator: UIViewPropertyAnimator?
  private lazy var refreshFeedback = UIImpactFeedbackGenerator(style: .light, view: self)
  private lazy var swipeFeedback = UIImpactFeedbackGenerator(style: .medium, view: self)

  private struct SwipeState {
    var direction: SwipeNavigationDirection
    var target: UIView
    var shade: UIView
    var destination: URL?
  }

  static let commitVelocity: CGFloat = 40
  static let beginRatio: CGFloat = 1.4
  static let beginSpeed: CGFloat = 20
  static let commitResponse: Double = 0.15
  static let cancelResponse: Double = 0.18
  static let landingDeadline: Duration = .seconds(1.5)
  static let landingFade: TimeInterval = 0.12
  static let parallax = -Layout.swipeParallax
  static let reattachDeadline: Duration = .seconds(1.5)
  static let paintDeadline: Duration = .seconds(4)

  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = true
    swipePan.delegate = self
    swipePan.maximumNumberOfTouches = 1
    addGestureRecognizer(swipePan)
    for edge in edgePans {
      edge.delegate = self
      addGestureRecognizer(edge)
    }
    refreshControl.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
    refreshControl.tintColor = UIColor(BrowsePalette.loadingBorder)
    coverView.contentMode = .scaleAspectFill
    coverView.clipsToBounds = true
    coverView.isUserInteractionEnabled = false
    coverView.isHidden = true
    coverView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(coverView)
  }

  required init?(coder: NSCoder) { nil }

  private var hostedWebViews: [WKWebView] {
    subviews.compactMap { $0 as? WKWebView }
  }

  func show(_ next: WebTab?, cover: UIImage?, isLoading: Bool, progress: Double, isLive: Bool = true) {
    guard let next else {
      cancelSwipe()
      page = nil
      webView = nil
      scrollObservation = nil
      hostedWebViews.forEach { $0.isHidden = true }
      hideCover(animated: false)
      hidePlaceholder(animated: false)
      return
    }
    guard isLive else {
      showWaiting(for: next, cover: cover)
      return
    }
    if page !== next || webView == nil || webView !== next.webView || next.webView?.superview !== self {
      switchTo(next, cover: cover)
    }
    if wasLoading, !isLoading { scheduleToneSample(after: .milliseconds(250)) }
    wasLoading = isLoading
    if case .whenPainted = reveal, coverView.isHidden, let cover {
      coverView.image = cover
      coverView.alpha = 1
      coverView.isHidden = false
      coverView.frame = bounds
      bringSubviewToFront(coverView)
    }
    updateReveal(isLoading: isLoading, progress: progress)
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil { PageRecession.shared.adopt(self) }
    wakePageWhenInWindow()
  }

  private func wakePageWhenInWindow() {
    guard window != nil, let page, !page.isLive else { return }
    Task { @MainActor [weak self, weak page] in
      guard let self, let page, self.window != nil, self.page === page, !page.isLive else { return }
      page.makeLive()
    }
  }

  private func showWaiting(for next: WebTab, cover: UIImage?) {
    defer { wakePageWhenInWindow() }
    guard page !== next || webView != nil else { return }
    cancelSwipe()
    page = next
    webView = nil
    scrollObservation = nil
    hostedWebViews.forEach { $0.isHidden = true }
    revealDeadline?.cancel()
    if let cover {
      coverView.layer.removeAllAnimations()
      coverView.image = cover
      coverView.alpha = 1
      coverView.isHidden = false
      coverView.frame = bounds
      bringSubviewToFront(coverView)
    } else {
      showPlaceholder()
    }
  }

  private func switchTo(_ next: WebTab, cover: UIImage?) {
    cancelSwipe()
    page = next
    guard let webView = next.webView else { return }
    let wasPresented = webView.superview === self && webView.window != nil && !webView.isHidden
    if webView.superview !== self {
      webView.removeFromSuperview()
      webView.frame = bounds
      webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      insertSubview(webView, belowSubview: coverView)
    }
    for other in hostedWebViews where other !== webView {
      other.isHidden = true
      if other.scrollView.refreshControl === refreshControl { other.scrollView.refreshControl = nil }
    }
    webView.isHidden = false
    insertSubview(webView, belowSubview: coverView)
    self.webView = webView
    webView.scrollView.refreshControl = refreshControl
    wasLoading = next.isLoading
    observeScroll(of: webView)
    applyInsets()
    revealDeadline?.cancel()
    hideCover(animated: false)
    if let cover {
      coverView.layer.removeAllAnimations()
      coverView.image = cover
      coverView.alpha = 1
      coverView.isHidden = false
      coverView.frame = bounds
      bringSubviewToFront(coverView)
    } else {
      showPlaceholder()
    }
    let settled = !next.isLoading && webView.url != nil
    if settled, wasPresented, webView.scrollView.contentSize.height > 0 {
      hideCover(animated: false)
      scheduleToneSample(after: .milliseconds(120))
      return
    }
    if settled {
      reveal = .afterReattach
      waitForPresentation(of: webView)
    } else {
      reveal = .whenPainted(sawLoading: next.isLoading)
      watchFirstLayout(of: webView)
    }
    revealDeadline = Task { @MainActor [weak self] in
      try? await Task.sleep(for: settled ? Self.reattachDeadline : Self.paintDeadline)
      guard !Task.isCancelled else { return }
      self?.hideCover(animated: true)
    }
  }

  private func revealAfterPresentation() {
    guard let webView, !revealPending else { return }
    revealPending = true
    layoutObservation = nil
    let configuration = WKSnapshotConfiguration()
    configuration.afterScreenUpdates = true
    configuration.snapshotWidth = 8
    webView.takeSnapshot(with: configuration) { [weak self, weak webView] _, _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.revealPending = false
        guard self.webView === webView, case .whenPainted = self.reveal else { return }
        HarnessProbe.mark("page.revealed")
        self.hideCover(animated: true)
      }
    }
  }

  private var hasPaintedCommittedPage: Bool {
    guard let page, let webView, page.committedNavigations > 0, !page.isProvisional else { return false }
    return webView.scrollView.contentSize.height > 0
  }

  private func waitForPresentation(of webView: WKWebView) {
    let configuration = WKSnapshotConfiguration()
    configuration.afterScreenUpdates = true
    configuration.snapshotWidth = 8
    webView.takeSnapshot(with: configuration) { [weak self, weak webView] _, _ in
      MainActor.assumeIsolated {
        guard let self, case .afterReattach = self.reveal, self.webView === webView else { return }
        self.hideCover(animated: true)
      }
    }
  }

  private func updateReveal(isLoading: Bool, progress: Double) {
    guard case .whenPainted(let sawLoading) = reveal else { return }
    if isLoading, !sawLoading { reveal = .whenPainted(sawLoading: true) }
    if sawLoading || isLoading, !isLoading {
      hideCover(animated: true)
    } else if hasPaintedCommittedPage {
      revealAfterPresentation()
    }
  }

  private func watchFirstLayout(of webView: WKWebView) {
    layoutObservation = webView.scrollView.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
      MainActor.assumeIsolated {
        guard let self, case .whenPainted = self.reveal, self.hasPaintedCommittedPage else { return }
        self.revealAfterPresentation()
      }
    }
  }

  private func observeScroll(of webView: WKWebView) {
    let scrollView = webView.scrollView
    barLink?.attach(scrollView)
    linkedPan?.removeTarget(self, action: #selector(scrollPanChanged(_:)))
    scrollView.panGestureRecognizer.addTarget(self, action: #selector(scrollPanChanged(_:)))
    linkedPan = scrollView.panGestureRecognizer
    scrollObservation = scrollView.observe(\.contentOffset, options: []) { [weak self] scrollView, _ in
      MainActor.assumeIsolated { self?.scrollMoved(scrollView) }
    }
  }

  @objc private func scrollPanChanged(_ pan: UIPanGestureRecognizer) {
    guard pan.state == .ended || pan.state == .cancelled, let view = pan.view else { return }
    barLink?.released(velocity: pan.velocity(in: view).y)
  }

  private func scrollMoved(_ scrollView: UIScrollView) {
    barLink?.scrolled(scrollView)
    lastScroll = CACurrentMediaTime()
    guard toneTask == nil else { return }
    toneTask = Task { @MainActor [weak self] in
      while let self, !Task.isCancelled {
        let quiet = CACurrentMediaTime() - self.lastScroll
        if quiet >= 0.16 { break }
        try? await Task.sleep(for: .seconds(max(0.16 - quiet, 0.02)))
      }
      guard let self, !Task.isCancelled else { return }
      self.toneTask = nil
      self.sampleTone()
    }
  }

  private func scheduleToneSample(after delay: Duration) {
    toneTask?.cancel()
    toneTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: delay)
      guard let self, !Task.isCancelled else { return }
      self.toneTask = nil
      self.sampleTone()
    }
  }

  private func sampleTone() {
    guard let webView, let page, webView.window != nil, !webView.isHidden, webView.url != nil,
          webView.bounds.height > bottomInset * 3, swipe == nil else { return }
    let id = page.id
    let bounds = webView.bounds
    let top = webView.safeAreaInsets.top + 1
    let bottom = bounds.height - max(bottomInset, BrowseLayout.barHeight(safeBottom: 0)) - ToneSampler.bandHeight - 2
    Task { @MainActor [weak self, weak webView] in
      guard let webView else { return }
      async let topImage = Self.snapshot(of: webView, in: CGRect(x: 0, y: top, width: bounds.width, height: ToneSampler.bandHeight))
      async let bottomImage = Self.snapshot(of: webView, in: CGRect(x: 0, y: bottom, width: bounds.width, height: ToneSampler.bandHeight))
      let images = await (topImage, bottomImage)
      guard let self, self.page?.id == id else { return }
      let tone = PageTone(top: images.0.flatMap(ToneSampler.dominant), bottom: images.1.flatMap(ToneSampler.dominant))
      guard tone.top != nil || tone.bottom != nil else { return }
      self.onTone?(id, tone)
    }
  }

  private static func snapshot(of webView: WKWebView, in rect: CGRect) async -> UIImage? {
    let configuration = WKSnapshotConfiguration()
    configuration.rect = rect
    configuration.afterScreenUpdates = false
    configuration.snapshotWidth = NSNumber(value: ToneSampler.sampleWidth)
    return try? await webView.takeSnapshot(configuration: configuration)
  }

  private func showPlaceholder() {
    HarnessProbe.mark("page.placeholder")
    guard let tab = placeholderTab else { return }
    placeholderHost?.view.layer.removeAllAnimations()
    placeholderHost?.view.removeFromSuperview()
    let host: UIViewController = PagePlaceholderPool.shared.take(tab.id) ?? UIHostingController(rootView: PageLoadingPlaceholder(tab: tab, backdrop: backdrop, revealDelay: Motion.placeholderDelay))
    host.view.isUserInteractionEnabled = false
    host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    host.view.frame = bounds
    host.view.alpha = 1
    addSubview(host.view)
    placeholderHost = host
  }

  private func hidePlaceholder(animated: Bool) {
    guard let view = placeholderHost?.view, view.alpha > 0 else { return }
    guard animated else {
      view.layer.removeAllAnimations()
      view.alpha = 0
      return
    }
    UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
      view.alpha = 0
    }
  }

  private func hideCover(animated: Bool) {
    layoutObservation = nil
    revealDeadline?.cancel()
    revealDeadline = nil
    reveal = .none
    hidePlaceholder(animated: animated)
    guard !coverView.isHidden, coverView.image != nil else {
      coverView.isHidden = true
      return
    }
    guard animated else {
      coverView.isHidden = true
      coverView.image = nil
      return
    }
    scheduleToneSample(after: .milliseconds(200))
    UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
      self.coverView.alpha = 0
    } completion: { finished in
      guard finished, self.coverView.alpha == 0 else { return }
      self.coverView.isHidden = true
      self.coverView.image = nil
    }
  }

  func detach() {
    cancelSwipe()
    revealDeadline?.cancel()
    toneTask?.cancel()
    scrollObservation = nil
    for hosted in hostedWebViews {
      if hosted.scrollView.refreshControl === refreshControl { hosted.scrollView.refreshControl = nil }
      hosted.isHidden = false
      hosted.removeFromSuperview()
    }
    webView = nil
    page = nil
  }

  func endRefreshing() {
    refreshCommitBaseline = nil
    if refreshControl.isRefreshing { refreshControl.endRefreshing() }
  }

  func endRefreshingIfReloaded(isLoading: Bool) {
    guard refreshControl.isRefreshing else { return }
    if !isLoading {
      endRefreshing()
    } else if let refreshCommitBaseline, let page, page.committedNavigations > refreshCommitBaseline {
      HarnessProbe.mark("refresh.committed")
      endRefreshing()
    }
  }

  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    applyInsets()
  }

  private func applyInsets() {
    guard let webView else { return }
    let clearance = max(topInset, 0)
    let insets = UIEdgeInsets(top: safeAreaInsets.top + clearance, left: 0, bottom: max(bottomInset, 0), right: 0)
    if webView.obscuredContentInsets != insets {
      webView.obscuredContentInsets = insets
    }
    let scrollView = webView.scrollView
    if scrollView.contentInset.top != clearance {
      scrollView.contentInset.top = clearance
      scrollView.verticalScrollIndicatorInsets.top = clearance
    }
  }

  @objc private func refreshPulled() {
    guard let page else { return endRefreshing() }
    HarnessProbe.mark("refresh.pull")
    refreshFeedback.impactOccurred()
    refreshCommitBaseline = page.committedNavigations
    page.reload()
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(8))
      self?.endRefreshing()
    }
  }

  override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
    if let edge = recognizer as? EdgeStartPanRecognizer {
      guard edgePager != nil, swipe == nil else { return false }
      let velocity = edge.velocity(in: self)
      guard abs(velocity.x) > abs(velocity.y), edge.edge == .left ? velocity.x > 0 : velocity.x < 0 else { return false }
      guard let page else { return true }
      return edge.edge == .left ? !page.canGoBack : !page.canGoForward
    }
    guard recognizer === swipePan, swipeMode == .anywhere, let page, let webView else { return false }
    let measured = swipePan.velocity(in: self)
    let velocity = hypot(measured.x, measured.y) > 60 ? measured : swipePan.translation(in: self)
    guard abs(velocity.x) > abs(velocity.y) * Self.beginRatio, abs(measured.x) > Self.beginSpeed || abs(velocity.x) > 4 else { return false }
    let scrollView = webView.scrollView
    let canScrollHorizontally = scrollView.contentSize.width > scrollView.bounds.width + 1
    if velocity.x > 0 {
      guard page.canGoBack else { return false }
      if canScrollHorizontally, scrollView.contentOffset.x > -scrollView.adjustedContentInset.left + 1 { return false }
    } else {
      guard page.canGoForward else { return false }
      if canScrollHorizontally, scrollView.contentOffset.x + scrollView.bounds.width < scrollView.contentSize.width + scrollView.adjustedContentInset.right - 1 { return false }
    }
    return true
  }

  func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
    recognizer is EdgeStartPanRecognizer && other !== swipePan && !(other is EdgeStartPanRecognizer) && other.view?.isDescendant(of: self) == true
  }

  @objc private func handleSwipe(_ recognizer: UIPanGestureRecognizer) {
    guard let webView, let page else { return }
    let width = bounds.width
    switch recognizer.state {
    case .began:
      let measured = recognizer.velocity(in: self)
      let heading = abs(measured.x) > 60 ? measured.x : recognizer.translation(in: self).x
      let direction: SwipeNavigationDirection = heading > 0 ? .back : .forward
      let scrollPan = webView.scrollView.panGestureRecognizer
      scrollPan.isEnabled = false
      scrollPan.isEnabled = true
      let target: UIView
      if let image = page.snapshotForSwipe(direction) {
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        target = imageView
      } else {
        target = UIView()
      }
      target.backgroundColor = webView.underPageBackgroundColor ?? .systemBackground
      target.frame = bounds
      let shade = UIView(frame: bounds)
      shade.backgroundColor = UIColor.black.withAlphaComponent(0.12)
      shade.isUserInteractionEnabled = false
      if direction == .back {
        insertSubview(target, belowSubview: webView)
        insertSubview(shade, aboveSubview: target)
        target.transform = CGAffineTransform(translationX: -width * Self.parallax, y: 0)
      } else {
        insertSubview(target, aboveSubview: webView)
        target.transform = CGAffineTransform(translationX: width, y: 0)
        target.layer.shadowColor = UIColor.black.cgColor
        target.layer.shadowOpacity = 0.18
        target.layer.shadowRadius = 12
        target.layer.shadowPath = UIBezierPath(rect: target.bounds).cgPath
        insertSubview(shade, belowSubview: target)
      }
      webView.layer.shadowColor = UIColor.black.cgColor
      webView.layer.shadowOpacity = direction == .back ? 0.18 : 0
      webView.layer.shadowRadius = 12
      webView.layer.shadowPath = UIBezierPath(rect: webView.bounds).cgPath
      HarnessProbe.mark("swipe.begin", direction == .back ? "back" : "forward")
      let list = webView.backForwardList
      swipe = SwipeState(direction: direction, target: target, shade: shade, destination: (direction == .back ? list.backItem : list.forwardItem)?.url)
      swipeFeedback.prepare()
    case .changed:
      guard let swipe else { return }
      let raw = recognizer.translation(in: self).x
      layoutSwipe(swipe, progress: progress(for: raw, direction: swipe.direction))
    case .ended, .cancelled, .failed:
      guard let swipe else { return }
      let raw = recognizer.translation(in: self).x
      let velocity = recognizer.velocity(in: self).x
      let signedVelocity = swipe.direction == .back ? velocity : -velocity
      let commits = recognizer.state == .ended && signedVelocity > Self.commitVelocity
      finishSwipe(swipe, commit: commits, from: progress(for: raw, direction: swipe.direction), velocity: signedVelocity)
    default:
      break
    }
  }

  private func progress(for translation: CGFloat, direction: SwipeNavigationDirection) -> CGFloat {
    let signed = direction == .back ? translation : -translation
    return min(max(signed / max(bounds.width, 1), 0), 1)
  }

  private func layoutSwipe(_ swipe: SwipeState, progress: CGFloat) {
    guard let webView else { return }
    let width = bounds.width
    switch swipe.direction {
    case .back:
      webView.transform = CGAffineTransform(translationX: width * progress, y: 0)
      swipe.target.transform = CGAffineTransform(translationX: -width * Self.parallax * (1 - progress), y: 0)
      swipe.shade.alpha = 1 - progress
    case .forward:
      swipe.target.transform = CGAffineTransform(translationX: width * (1 - progress), y: 0)
      webView.transform = CGAffineTransform(translationX: -width * Self.parallax * progress, y: 0)
      swipe.shade.alpha = progress
    }
  }

  private func finishSwipe(_ swipe: SwipeState, commit: Bool, from progress: CGFloat, velocity: CGFloat) {
    HarnessProbe.mark(commit ? "swipe.commit" : "swipe.cancel")
    if commit { swipeFeedback.impactOccurred(intensity: 0.6) }
    let width = max(bounds.width, 1)
    let remaining = max((commit ? 1 - progress : progress) * width, 1)
    let towardTarget = commit ? velocity : -velocity
    let stiffness = pow(2 * .pi / (commit ? Self.commitResponse : Self.cancelResponse), 2)
    let timing = UISpringTimingParameters(mass: 1, stiffness: stiffness, damping: 2 * sqrt(stiffness), initialVelocity: CGVector(dx: min(max(towardTarget / remaining, 0), 30), dy: 0))
    let animator = UIViewPropertyAnimator(duration: 0.5, timingParameters: timing)
    animator.addAnimations { [self] in layoutSwipe(swipe, progress: commit ? 1 : 0) }
    let origin = page
    animator.addCompletion { [weak self] _ in
      guard let self else { return }
      self.swipeAnimator = nil
      self.webView?.transform = .identity
      self.webView?.layer.shadowOpacity = 0
      swipe.shade.removeFromSuperview()
      self.swipe = nil
      guard commit, let page = origin, page === self.page else {
        swipe.target.removeFromSuperview()
        return
      }
      self.bringSubviewToFront(swipe.target)
      swipe.target.transform = .identity
      swipe.target.layer.shadowOpacity = 0
      if swipe.direction == .back { page.goBack() } else { page.goForward() }
      self.revealAfterSwipe(swipe)
    }
    swipeAnimator = animator
    animator.startAnimation()
  }

  private func revealAfterSwipe(_ swipe: SwipeState) {
    let target = swipe.target
    let fade = { [weak target] in
      guard let target, target.superview != nil else { return }
      HarnessProbe.mark("swipe.landed")
      UIView.animate(withDuration: Self.landingFade, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
        target.alpha = 0
      } completion: { _ in
        target.removeFromSuperview()
      }
    }
    Task { @MainActor [weak self, weak target] in
      let deadline = ContinuousClock.now + Self.landingDeadline
      while ContinuousClock.now < deadline {
        guard let self, let target, target.superview === self, let webView = self.webView else { return }
        let arrived = swipe.destination == nil || webView.url == swipe.destination
        if arrived, !webView.isLoading || webView.estimatedProgress > 0.5 {
          let configuration = WKSnapshotConfiguration()
          configuration.afterScreenUpdates = true
          configuration.snapshotWidth = 8
          webView.takeSnapshot(with: configuration) { _, _ in
            MainActor.assumeIsolated { fade() }
          }
          return
        }
        try? await Task.sleep(for: .milliseconds(16))
      }
      fade()
    }
  }

  private func cancelSwipe() {
    swipeAnimator?.stopAnimation(true)
    swipeAnimator = nil
    guard let swipe else { return }
    swipe.target.removeFromSuperview()
    swipe.shade.removeFromSuperview()
    webView?.transform = .identity
    webView?.layer.shadowOpacity = 0
    self.swipe = nil
  }
}

final class EdgeStartPanRecognizer: UIPanGestureRecognizer {
  static let zone: CGFloat = 24

  let edge: UIRectEdge

  init(edge: UIRectEdge) {
    self.edge = edge
    super.init(target: nil, action: nil)
    maximumNumberOfTouches = 1
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesBegan(touches, with: event)
    guard let view, let point = touches.first?.location(in: view) else { return }
    let inZone = edge == .left ? point.x <= Self.zone : point.x >= view.bounds.width - Self.zone
    if !inZone { state = .failed }
  }
}

enum PageWindows {
  static var exist: Bool {
    UIApplication.shared.connectedScenes.contains { ($0 as? UIWindowScene)?.windows.isEmpty == false }
  }
}
