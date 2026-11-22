import ArdiaBrowser
import ArdiaDesign
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import WebKit

extension AppModel {
  var swipeOrder: [BrowserTab] {
    let current = deckOrder
    guard let frozen = browse.frozenOrder else { return current }
    let byID = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let frozenIDs = Set(frozen)
    return frozen.compactMap { byID[$0] } + current.filter { !frozenIDs.contains($0.id) }
  }
}

@MainActor
final class TabPager: NSObject {
  enum Phase: Equatable {
    case idle
    case caught
    case tracking
    case settling
  }

  private struct LiveSnapshot {
    let view: UIView
    let frame: CGRect
  }

  private weak var app: AppModel?
  let stage = TabPagerStageView()
  private(set) var phase: Phase = .idle

  private var order: [BrowserTab] = []
  private var index = 0
  private var offset: CGFloat = 0
  private var trackingBase: CGFloat = 0
  private var settleTarget = 0
  private var settleSide = 0
  private var generation = 0
  private var animator: UIViewPropertyAnimator?
  private var startID: UUID?
  private var expectedSelection: UUID?
  private var hasMoved = false

  private var left = TabPagerCardView()
  private var center = TabPagerCardView()
  private var right = TabPagerCardView()

  private var liveSnapshots: [UUID: LiveSnapshot] = [:]
  private var liveSnapshotOrder: [UUID] = []
  private var images: [UUID: UIImage] = [:]
  private var placeholders: [UUID: UIHostingController<AnyView>] = [:]
  private var warmTask: Task<Void, Never>?
  private let feedback = UIImpactFeedbackGenerator(style: .light)

  private static let liveSnapshotLimit = 4
  private static let catchSnapDistance: CGFloat = 6
  private static let settledDistance: CGFloat = 0.5

  override init() {
    super.init()
    stage.isHidden = true
    stage.backgroundColor = .black
    stage.accessibilityElementsHidden = true
    stage.claim = { [weak self] in self?.stageClaim() ?? .pass }
    for card in [center, left, right] { stage.addSubview(card) }
  }

  func attach(_ app: AppModel) {
    self.app = app
    scheduleWarm()
  }

  private var width: CGFloat { stage.bounds.width }
  private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }
  private var hasLeft: Bool { index > 0 }
  private var hasRight: Bool { index + 1 < order.count }

  private func tab(at position: Int) -> BrowserTab? {
    order.indices.contains(position) ? order[position] : nil
  }

  private func side(for offset: CGFloat) -> Int {
    offset > 0 && hasLeft ? -1 : offset < 0 && hasRight ? 1 : 0
  }

  private func beginSession() -> Bool {
    guard let app, let id = app.tabs.selectedTabID, width > 0 else { return false }
    let order = app.swipeOrder
    guard let position = order.firstIndex(where: { $0.id == id }) else { return false }
    warmTask?.cancel()
    self.order = order
    index = position
    startID = id
    expectedSelection = id
    offset = 0
    hasMoved = false
    if let live = snapshotCurrentPage(id) { remember(live, for: id) }
    configure(center, with: order[position])
    configure(left, with: tab(at: position - 1))
    configure(right, with: tab(at: position + 1))
    for card in [center, left, right] { card.bounds = stage.bounds }
    UIView.performWithoutAnimation { apply(offset: 0, side: 0) }
    stage.isHidden = false
    feedback.prepare()
    captureThumbnail(of: id)
    return true
  }

  private func configure(_ card: TabPagerCardView, with tab: BrowserTab?) {
    guard let tab, let app else {
      card.clear()
      return
    }
    if card.tabID == tab.id, card.hasContent { return }
    let tone = app.browse.tone(for: tab, page: app.web.existingWebTab(tab.id)).top.map { UIColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: 1) }
    let statusHeight = stage.window?.safeAreaInsets.top ?? stage.safeAreaInsets.top
    card.prepare(tabID: tab.id, surface: UIColor(app.look.surface), tone: tone, statusHeight: statusHeight)
    if let live = liveSnapshots[tab.id] {
      card.show(view: live.view, frame: live.frame)
    } else if let image = storedImage(for: tab) {
      card.show(image: image)
    } else {
      card.show(view: placeholder(for: tab).view, frame: stage.bounds)
      if let name = tab.snapshotFileName {
        let id = tab.id
        Task { [weak self, weak card] in
          guard let image = await self?.app?.web.snapshots.image(named: name) else { return }
          let decoded = UIImage(cgImage: image)
          self?.images[id] = decoded
          guard let card, card.tabID == id else { return }
          card.show(image: decoded)
        }
      }
    }
  }

  private func storedImage(for tab: BrowserTab) -> UIImage? {
    guard let app else { return nil }
    if let image = app.browse.covers.image(for: tab.id) ?? app.deck.memoryImage(for: tab.id) ?? images[tab.id] { return image }
    return tab.snapshotFileName.flatMap(app.web.snapshots.cachedImage(named:)).map { UIImage(cgImage: $0) }
  }

  private func placeholder(for tab: BrowserTab) -> UIHostingController<AnyView> {
    if let existing = placeholders[tab.id] { return existing }
    let host = UIHostingController(rootView: AnyView(EmptyView()))
    if let app {
      host.rootView = AnyView(PageLoadingPlaceholder(tab: tab, backdrop: app.look.surface).environment(app).environment(\.profileLook, app.look))
    }
    host.safeAreaRegions = []
    host.view.backgroundColor = .clear
    host.view.isUserInteractionEnabled = false
    host.view.frame = stage.bounds.isEmpty ? (stage.window?.bounds ?? UIScreen.main.bounds) : stage.bounds
    host.view.layoutIfNeeded()
    placeholders[tab.id] = host
    return host
  }

  private func snapshotCurrentPage(_ id: UUID) -> LiveSnapshot? {
    guard let app, let webView = app.web.existingWebTab(id)?.webView, webView.window != nil, !webView.isHidden,
          let container = webView.superview as? PageContainerView, container.window != nil else { return nil }
    guard let view = container.snapshotView(afterScreenUpdates: false) else { return nil }
    return LiveSnapshot(view: view, frame: container.convert(container.bounds, to: stage))
  }

  private func remember(_ snapshot: LiveSnapshot, for id: UUID) {
    liveSnapshots[id] = snapshot
    liveSnapshotOrder.removeAll { $0 == id }
    liveSnapshotOrder.append(id)
    while liveSnapshotOrder.count > Self.liveSnapshotLimit {
      liveSnapshots[liveSnapshotOrder.removeFirst()] = nil
    }
  }

  private func forgetLiveSnapshot(_ id: UUID) {
    liveSnapshots[id] = nil
    liveSnapshotOrder.removeAll { $0 == id }
  }

  private func captureThumbnail(of id: UUID) {
    guard let app, let webView = app.web.existingWebTab(id)?.webView, webView.window != nil, !webView.bounds.isEmpty else { return }
    let configuration = WKSnapshotConfiguration()
    configuration.afterScreenUpdates = true
    let scale = Double(webView.traitCollection.displayScale)
    configuration.snapshotWidth = NSNumber(value: Double(webView.bounds.width) * min(scale, 2) / max(scale, 1))
    webView.takeSnapshot(with: configuration) { [weak self] image, _ in
      MainActor.assumeIsolated {
        guard let self, let image, let app = self.app else { return }
        app.browse.covers.store(image, for: id)
        app.persistSnapshot(image, for: id)
      }
    }
  }

  private func apply(offset: CGFloat, side: Int) {
    let width = width
    let bounds = stage.bounds
    let incoming = side < 0 ? left : side > 0 ? right : nil
    for card in [left, right] where card !== incoming { card.isHidden = true }
    let poses = Self.poses(offset: offset, side: side, width: width, reduceMotion: reduceMotion)
    center.isHidden = false
    place(center, pose: poses.outgoing, in: bounds, shadowEdge: 0)
    center.layer.zPosition = 0
    if let incoming, let pose = poses.incoming {
      incoming.isHidden = false
      incoming.layer.zPosition = 1
      place(incoming, pose: pose, in: bounds, shadowEdge: -side)
    }
  }

  private func place(_ card: TabPagerCardView, pose: PagerCardPose, in bounds: CGRect, shadowEdge: Int) {
    card.center = CGPoint(x: bounds.midX + pose.x, y: bounds.midY)
    card.transform = CGAffineTransform(scaleX: pose.scale, y: pose.scale)
    card.alpha = pose.opacity
    card.dim = pose.dim
    card.shadowEdge = shadowEdge
    card.shadowAlpha = pose.shadow
  }

  static func poses(offset: CGFloat, side: Int, width: CGFloat, reduceMotion: Bool) -> (outgoing: PagerCardPose, incoming: PagerCardPose?) {
    guard width > 0 else { return (PagerCardPose(), nil) }
    guard side != 0 else {
      let pull = min(abs(offset) / PagerPhysics.rubberLimit, 1)
      return (PagerCardPose(x: reduceMotion ? 0 : offset, scale: reduceMotion ? 1 : 1 - PagerPhysics.edgeScale * pull), nil)
    }
    let toward = side < 0 ? max(offset, 0) : min(offset, 0)
    let progress = min(abs(toward) / width, 1)
    if reduceMotion {
      return (PagerCardPose(), PagerCardPose(x: 0, opacity: Double(progress)))
    }
    let outgoing = PagerCardPose(
      x: toward * PagerPhysics.parallax,
      scale: 1 - (1 - PagerPhysics.recededScale) * progress,
      dim: PagerPhysics.recededDim * Double(progress)
    )
    let incoming = PagerCardPose(x: CGFloat(side) * width + toward, shadow: Double(1 - progress))
    return (outgoing, incoming)
  }

  private func rawOffset(for offset: CGFloat) -> CGFloat {
    if offset > 0, !hasLeft { return offset / max(1 - offset / PagerPhysics.rubberLimit, 0.05) }
    if offset < 0, !hasRight { return offset / max(1 + offset / PagerPhysics.rubberLimit, 0.05) }
    return offset
  }

  private func track(raw: CGFloat) {
    var raw = raw
    let width = width
    while width > 0 {
      if raw >= width, hasLeft {
        rebase(toward: 1)
        raw -= width
        trackingBase -= width
      } else if raw <= -width, hasRight {
        rebase(toward: -1)
        raw += width
        trackingBase += width
      } else {
        break
      }
    }
    offset = PagerPhysics.resolvedOffset(raw, hasLeft: hasLeft, hasRight: hasRight, width: width)
    UIView.performWithoutAnimation { apply(offset: offset, side: side(for: offset)) }
    if !hasMoved, offset != 0 {
      hasMoved = true
      HarnessProbe.mark("pager.move")
    }
  }

  private func rebase(toward direction: Int) {
    index -= direction
    if direction > 0 {
      (left, center, right) = (right, left, center)
      configure(left, with: tab(at: index - 1))
    } else {
      (left, center, right) = (center, right, left)
      configure(right, with: tab(at: index + 1))
    }
  }

  @objc func panned(_ recognizer: UIPanGestureRecognizer) {
    let translation = (recognizer as? TabPagerPanRecognizer)?.fingerTranslation ?? recognizer.translation(in: stage).x
    switch recognizer.state {
    case .began:
      if phase == .settling { touchDown() }
      if phase == .idle {
        guard beginSession() else { return }
      }
      phase = .tracking
      trackingBase = rawOffset(for: offset)
      HarnessProbe.mark("pager.begin")
      track(raw: trackingBase + translation)
      commitNow()
    case .changed:
      guard phase == .tracking else { return }
      track(raw: trackingBase + translation)
    case .ended, .cancelled, .failed:
      guard phase == .tracking else { return }
      let velocity = recognizer.state == .ended ? recognizer.velocity(in: stage).x : 0
      let target = PagerPhysics.snapTarget(offset: offset, velocity: velocity, width: width, hasLeft: hasLeft, hasRight: hasRight)
      settle(to: target, velocity: velocity)
    default:
      break
    }
  }

  func touchDown() {
    guard phase == .settling else { return }
    HarnessProbe.mark("pager.catch")
    let caught = presentedOffset()
    stopAnimator()
    generation += 1
    let destination = CGFloat(settleTarget) * width
    if settleTarget != 0, abs(destination - caught) < Self.catchSnapDistance {
      rebase(toward: settleTarget)
      offset = caught - destination
    } else {
      offset = caught
    }
    phase = .caught
    UIView.performWithoutAnimation { apply(offset: offset, side: side(for: offset)) }
    commitNow()
  }

  func touchEnded() {
    guard phase == .caught else { return }
    settle(to: PagerPhysics.snapTarget(offset: offset, velocity: 0, width: width, hasLeft: hasLeft, hasRight: hasRight), velocity: 0)
  }

  private func presentedOffset() -> CGFloat {
    let side = settleSide
    let width = width
    if side != 0 {
      let incoming = side < 0 ? left : right
      if reduceMotion {
        let progress = CGFloat(incoming.layer.presentation()?.opacity ?? incoming.layer.opacity)
        return -CGFloat(side) * progress * width
      }
      let x = incoming.layer.presentation()?.position.x ?? incoming.center.x
      return x - stage.bounds.midX - CGFloat(side) * width
    }
    if reduceMotion { return 0 }
    let x = center.layer.presentation()?.position.x ?? center.center.x
    return x - stage.bounds.midX
  }

  private func settle(to target: Int, velocity: CGFloat) {
    stopAnimator()
    generation += 1
    let generation = generation
    let width = width
    let destination = CGFloat(target) * width
    let animationSide = target != 0 ? -target : side(for: offset)
    let from = offset
    settleTarget = target
    settleSide = animationSide
    phase = .settling
    HarnessProbe.mark("pager.settle", "\(target)")
    if target != 0 { feedback.impactOccurred(intensity: 0.7) }
    let releaseVelocity = min(max(velocity, -4000), 4000)
    let distance = destination - from
    let animator: UIViewPropertyAnimator
    var visualEnd: TimeInterval?
    if reduceMotion {
      animator = UIViewPropertyAnimator(duration: 0.2, curve: .easeOut)
    } else {
      let response = Motion.pagerSettle.response
      let relative = abs(distance) > 0.5 ? releaseVelocity / distance : 0
      animator = UIViewPropertyAnimator(duration: 0.5, timingParameters: Self.spring(response: response, velocity: relative))
      visualEnd = Self.settleTime(distance: distance, velocity: releaseVelocity, response: response)
    }
    animator.isInterruptible = true
    animator.isUserInteractionEnabled = true
    animator.addAnimations { [weak self] in self?.apply(offset: destination, side: animationSide) }
    animator.addCompletion { [weak self] position in
      guard let self, self.generation == generation, position == .end else { return }
      self.finish()
    }
    offset = destination
    self.animator = animator
    animator.startAnimation()
    commitNow()
    if let visualEnd {
      DispatchQueue.main.asyncAfter(deadline: .now() + visualEnd) { [weak self] in
        guard let self, self.generation == generation, self.phase == .settling, let animator = self.animator else { return }
        animator.stopAnimation(false)
        animator.finishAnimation(at: .end)
      }
    }
    if let wanted = tab(at: index - target), wanted.id != app?.tabs.selectedTabID {
      select(wanted.id, generation: generation)
    }
  }

  private func select(_ id: UUID, generation: Int) {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.generation == generation, let app = self.app else { return }
      app.prepareToOpen(id)
      DispatchQueue.main.async { [weak self] in
        guard let self, self.generation == generation else { return }
        self.commitSelection(id)
      }
    }
  }

  private func commitSelection(_ id: UUID) {
    guard let app, app.tabs.selectedTabID != id else { return }
    expectedSelection = id
    app.browse.freezeOrder(order.map(\.id))
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) { app.openTab(id) }
  }

  private func finish() {
    let landed = tab(at: index - settleTarget)
    if let landed { commitSelection(landed.id) }
    HarnessProbe.mark("pager.settled")
    end()
  }

  private func end() {
    stopAnimator()
    generation += 1
    phase = .idle
    stage.isHidden = true
    for card in [left, center, right] { card.clear() }
    order = []
    startID = nil
    if let selected = app?.tabs.selectedTabID { forgetLiveSnapshot(selected) }
    scheduleWarm()
  }

  func landNow() {
    switch phase {
    case .idle:
      return
    case .settling:
      HarnessProbe.mark("pager.landNow")
      stopAnimator()
      finish()
    case .caught, .tracking:
      settleTarget = PagerPhysics.snapTarget(offset: offset, velocity: 0, width: width, hasLeft: hasLeft, hasRight: hasRight)
      finish()
    }
  }

  private func stageClaim() -> TouchClaim {
    switch phase {
    case .idle: return .pass
    case .caught, .tracking: return .own
    case .settling:
      landNow()
      return .pass
    }
  }

  func selectionChanged() {
    guard let selected = app?.tabs.selectedTabID else { return }
    if phase != .idle {
      guard selected != expectedSelection else { return }
      end()
      return
    }
    forgetLiveSnapshot(selected)
    scheduleWarm()
  }

  private func stopAnimator() {
    guard let animator else { return }
    self.animator = nil
    if animator.state == .active {
      animator.stopAnimation(false)
      animator.finishAnimation(at: .current)
    }
  }

  private func commitNow() {
    CATransaction.flush()
    HarnessProbe.mark("anim.committed")
  }

  private func scheduleWarm() {
    warmTask?.cancel()
    warmTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      self?.warm()
    }
  }

  private func warm() {
    guard phase == .idle, let app, let id = app.tabs.selectedTabID else { return }
    HarnessProbe.mark("pager.warm")
    let order = app.swipeOrder
    guard let position = order.firstIndex(where: { $0.id == id }) else { return }
    let neighbors = [position - 1, position + 1].filter(order.indices.contains).map { order[$0] }
    let keep = Set(neighbors.map(\.id))
    images = images.filter { keep.contains($0.key) }
    placeholders = placeholders.filter { keep.contains($0.key) }
    wakeNeighbors(neighbors.map(\.id), keeping: id)
    for tab in neighbors where liveSnapshots[tab.id] == nil && storedImage(for: tab) == nil {
      if let name = tab.snapshotFileName {
        let tabID = tab.id
        Task { [weak self] in
          guard let image = await self?.app?.web.snapshots.image(named: name) else { return }
          self?.images[tabID] = UIImage(cgImage: image)
        }
      } else {
        _ = placeholder(for: tab)
        DispatchQueue.main.async { [weak app] in
          guard let app else { return }
          PagePlaceholderPool.shared.prepare(tab, app: app)
        }
      }
    }
    PagePlaceholderPool.shared.keep(keep)
  }

  private func wakeNeighbors(_ ids: [UUID], keeping selected: UUID) {
    guard let app, let next = ids.first(where: { app.web.existingWebTab($0)?.isLive != true }) else { return }
    let rest = ids.filter { $0 != next }
    warmTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(120))
      guard !Task.isCancelled, let self, self.phase == .idle, let app = self.app, app.tabs.selectedTabID == selected else { return }
      HarnessProbe.mark("pager.wake")
      app.prepareToOpen(next)
      app.prepareToOpen(selected)
      self.wakeNeighbors(rest, keeping: selected)
    }
  }

  private static func spring(response: Double, velocity: CGFloat) -> UISpringTimingParameters {
    let stiffness = pow(2 * .pi / response, 2)
    return UISpringTimingParameters(mass: 1, stiffness: stiffness, damping: 2 * sqrt(stiffness), initialVelocity: CGVector(dx: velocity, dy: velocity))
  }

  static func settleTime(distance: CGFloat, velocity: CGFloat, response: Double) -> TimeInterval {
    let omega = 2 * Double.pi / response
    let start = -Double(distance)
    let speed = Double(velocity)
    var time = 0.0
    while time < 1.5 {
      time += 1.0 / 240
      let remaining = (start + (speed + omega * start) * time) * exp(-omega * time)
      let rate = (speed - (speed + omega * start) * omega * time) * exp(-omega * time)
      if abs(remaining) < Double(settledDistance), abs(rate) < 30 { return time }
    }
    return time
  }

  func runDemoFreeze() async {
    guard let fraction = MotionDemo.pagerFreeze else { return }
    try? await Task.sleep(for: .seconds(MotionDemo.delay))
    guard beginSession() else { return }
    phase = .tracking
    track(raw: -fraction * width)
  }

  func runDemoScript() async {
    guard MotionDemo.pagerScript else { return }
    try? await Task.sleep(for: .seconds(MotionDemo.delay))
    func drag(to fraction: CGFloat, over seconds: Double) async {
      let start = rawOffset(for: offset)
      let steps = max(Int(seconds * 120), 1)
      for step in 1...steps {
        let progress = CGFloat(step) / CGFloat(steps)
        track(raw: start + (fraction * width - start) * progress)
        try? await Task.sleep(for: .milliseconds(8))
      }
    }
    func grab() -> Bool {
      if phase == .settling { touchDown() }
      if phase == .idle, !beginSession() { return false }
      phase = .tracking
      return true
    }
    guard grab() else { return }
    await drag(to: 0.25, over: 0.3)
    settle(to: 0, velocity: 0)
    try? await Task.sleep(for: .seconds(1.2))
    guard grab() else { return }
    await drag(to: -0.3, over: 0.25)
    settle(to: PagerPhysics.snapTarget(offset: offset, velocity: -1400, width: width, hasLeft: hasLeft, hasRight: hasRight), velocity: -1400)
    try? await Task.sleep(for: .seconds(1.5))
    guard grab() else { return }
    await drag(to: 0.3, over: 0.25)
    settle(to: hasLeft ? 1 : 0, velocity: 1400)
    try? await Task.sleep(for: .milliseconds(120))
    guard grab() else { return }
    await drag(to: 0.1, over: 0.2)
    settle(to: 0, velocity: -300)
  }
}

@MainActor
final class PagePlaceholderPool {
  static let shared = PagePlaceholderPool()

  private var hosts: [UUID: UIHostingController<AnyView>] = [:]

  func prepare(_ tab: BrowserTab, app: AppModel) {
    guard hosts[tab.id] == nil else { return }
    let host = UIHostingController(rootView: AnyView(PageLoadingPlaceholder(tab: tab, backdrop: app.look.surface).environment(app).environment(\.profileLook, app.look)))
    host.safeAreaRegions = []
    host.view.isUserInteractionEnabled = false
    host.view.frame = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen.bounds }.first ?? .zero
    host.view.layoutIfNeeded()
    hosts[tab.id] = host
  }

  func take(_ id: UUID) -> UIHostingController<AnyView>? {
    hosts.removeValue(forKey: id)
  }

  func keep(_ ids: Set<UUID>) {
    hosts = hosts.filter { ids.contains($0.key) }
  }
}

final class TabPagerStageView: UIView {
  var claim: () -> TouchClaim = { .pass }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard !isHidden, let event, event.type == .touches, self.point(inside: point, with: event) else { return nil }
    switch claim() {
    case .normal, .own: return self
    case .pass: return nil
    }
  }
}

final class TabPagerCardView: UIView {
  private(set) var tabID: UUID?
  private let clip = UIView()
  private let imageView = UIImageView()
  private let tone = UIView()
  private let shade = UIView()
  private let edgeShadow = TabPagerEdgeShadow()
  private var content: UIView?
  private var contentFrame: CGRect?
  private var statusHeight: CGFloat = 0

  static let shadowWidth: CGFloat = 36

  var hasContent: Bool { content != nil || imageView.image != nil }

  var dim: Double = 0 {
    didSet { if dim != oldValue { shade.alpha = CGFloat(dim) } }
  }

  var shadowAlpha: Double = 0 {
    didSet { if shadowAlpha != oldValue { edgeShadow.alpha = CGFloat(shadowAlpha) } }
  }

  var shadowEdge = 0 {
    didSet {
      guard shadowEdge != oldValue else { return }
      edgeShadow.isHidden = shadowEdge == 0
      edgeShadow.point(toward: shadowEdge)
      setNeedsLayout()
    }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    isHidden = true
    clip.layer.cornerRadius = TabsLayout.displayCornerRadius
    clip.layer.cornerCurve = .continuous
    clip.layer.masksToBounds = true
    imageView.contentMode = .scaleToFill
    imageView.clipsToBounds = false
    shade.backgroundColor = .black
    shade.alpha = 0
    edgeShadow.isHidden = true
    edgeShadow.alpha = 0
    addSubview(clip)
    clip.addSubview(imageView)
    clip.addSubview(tone)
    clip.addSubview(shade)
    addSubview(edgeShadow)
  }

  required init?(coder: NSCoder) { nil }

  func prepare(tabID: UUID, surface: UIColor, tone color: UIColor?, statusHeight: CGFloat) {
    clear()
    self.tabID = tabID
    self.statusHeight = statusHeight
    clip.backgroundColor = surface
    tone.backgroundColor = color
    tone.isHidden = color == nil
    setNeedsLayout()
  }

  func show(image: UIImage) {
    content?.removeFromSuperview()
    content = nil
    contentFrame = nil
    imageView.image = image
    imageView.isHidden = false
    setNeedsLayout()
  }

  func show(view: UIView, frame: CGRect) {
    imageView.image = nil
    imageView.isHidden = true
    if content !== view { content?.removeFromSuperview() }
    content = view
    contentFrame = frame
    clip.insertSubview(view, belowSubview: tone)
    setNeedsLayout()
  }

  func clear() {
    if let content, content.superview === clip { content.removeFromSuperview() }
    content = nil
    contentFrame = nil
    imageView.image = nil
    tabID = nil
    isHidden = true
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let bounds = bounds
    clip.frame = bounds
    shade.frame = bounds
    tone.frame = CGRect(x: 0, y: 0, width: bounds.width, height: statusHeight)
    if let content {
      content.frame = contentFrame ?? bounds
    }
    if let image = imageView.image, image.size.width > 0, image.size.height > 0 {
      let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
      let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
      imageView.frame = CGRect(x: (bounds.width - size.width) / 2, y: 0, width: size.width, height: size.height)
    }
    let inset = TabsLayout.displayCornerRadius * 0.6
    let x = shadowEdge < 0 ? -Self.shadowWidth : bounds.width
    edgeShadow.frame = CGRect(x: x, y: inset, width: Self.shadowWidth, height: max(bounds.height - inset * 2, 0))
  }
}

final class TabPagerEdgeShadow: UIView {
  override class var layerClass: AnyClass { CAGradientLayer.self }

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    let gradient = layer as! CAGradientLayer
    gradient.colors = [UIColor.black.withAlphaComponent(0).cgColor, UIColor.black.withAlphaComponent(0.08).cgColor, UIColor.black.withAlphaComponent(0.26).cgColor]
    point(toward: 1)
  }

  required init?(coder: NSCoder) { nil }

  func point(toward edge: Int) {
    let gradient = layer as! CAGradientLayer
    gradient.startPoint = CGPoint(x: edge < 0 ? 0 : 1, y: 0.5)
    gradient.endPoint = CGPoint(x: edge < 0 ? 1 : 0, y: 0.5)
  }
}

final class TabPagerPanRecognizer: UIPanGestureRecognizer {
  var onTouchDown: () -> Void = {}
  var onTouchEnded: () -> Void = {}
  private var start: CGPoint?
  private(set) var fingerTranslation: CGFloat = 0

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    if start == nil, let touch = touches.first {
      start = touch.location(in: nil)
      fingerTranslation = 0
      onTouchDown()
    }
    super.touchesBegan(touches, with: event)
  }

  static let beginDistance: CGFloat = 6

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
    if let start, let touch = touches.first { fingerTranslation = touch.location(in: nil).x - start.x }
    guard state == .possible, let start, let touch = touches.first else {
      super.touchesMoved(touches, with: event)
      return
    }
    let point = touch.location(in: nil)
    let dx = point.x - start.x
    let dy = point.y - start.y
    if abs(dy) > abs(dx), hypot(dx, dy) > Self.beginDistance {
      state = .failed
      return
    }
    super.touchesMoved(touches, with: event)
    if state == .possible, abs(dx) >= Self.beginDistance { state = .began }
  }

  override func reset() {
    super.reset()
    start = nil
    fingerTranslation = 0
    onTouchEnded()
  }
}

struct TabPagerPan: UIGestureRecognizerRepresentable {
  let pager: TabPager

  func makeUIGestureRecognizer(context: Context) -> TabPagerPanRecognizer {
    let recognizer = TabPagerPanRecognizer()
    recognizer.maximumNumberOfTouches = 1
    recognizer.addTarget(pager, action: #selector(TabPager.panned(_:)))
    recognizer.onTouchDown = { [weak pager] in pager?.touchDown() }
    recognizer.onTouchEnded = { [weak pager] in pager?.touchEnded() }
    return recognizer
  }

  func handleUIGestureRecognizerAction(_ recognizer: TabPagerPanRecognizer, context: Context) {}
}

struct TabPagerStageHost: UIViewRepresentable {
  let pager: TabPager
  let app: AppModel

  func makeUIView(context: Context) -> TabPagerStageView {
    pager.attach(app)
    return pager.stage
  }

  func updateUIView(_ view: TabPagerStageView, context: Context) {}
}
