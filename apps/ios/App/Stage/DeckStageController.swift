import ArdiaBrowser
import ArdiaDesign
import SwiftUI
import UIKit
import WebKit

final class DeckStageController: UIViewController, UIGestureRecognizerDelegate, UIContextMenuInteractionDelegate {
  enum Phase: Equatable {
    case hidden
    case opening(UUID?)
    case settled
    case closing(UUID)
    case returning(UUID)
  }

  let app: AppModel
  let stage = DeckStageModel()
  var environment = DeckStageEnvironment(look: .plum, usesGlass: true, screenLayout: .phone) {
    didSet { if environment != oldValue { rebuildHosts() } }
  }

  private let backdrop = UIHostingController(rootView: AnyView(EmptyView()))
  private let topChrome = UIHostingController(rootView: AnyView(EmptyView()))
  private let grid = UIHostingController(rootView: AnyView(EmptyView()))
  private let gridShell = AccessibilityGate()
  private let bar = UIHostingController(rootView: AnyView(EmptyView()))
  private let pageBar = UIHostingController(rootView: AnyView(EmptyView()))
  private let pageBarShell = AccessibilityGate()
  private let topChromeShell = PassthroughView()
  private let barShell = PassthroughView()
  private let cardsView = UIView()
  private let risingThumbnails = [BarThumbnailView(), BarThumbnailView()]
  private var riseAnimator: UIViewPropertyAnimator?

  private var phase: Phase = .hidden
  private var order: [UUID] = []
  private var scroll: Double = 0
  private var cards: [UUID: DeckCardView] = [:]
  private var headers: [UUID: DeckCardHeaderView] = [:]
  private var lifts: [UUID: CGFloat] = [:]
  private var transitions: [UIViewPropertyAnimator] = []
  private var transitionGeneration = 0
  private var headerTucks: [UUID: CGFloat] = [:]
  private var geometry: TabsDeckGeometry { stage.geometry }
  private var shownSpace: String?
  private var observing = false

  private var settle: ScrollSpring?
  private var settleLink: CADisplayLink?
  private enum Drag { case horizontal(start: Double), lift(UUID, start: CGFloat) }
  private var drag: Drag?
  private var panStart: CGPoint = .zero
  private var tickedCard: Int?
  private var ownedTouchEvent: TimeInterval?
  private let selection = UISelectionFeedbackGenerator()
  private let impact = UIImpactFeedbackGenerator(style: .light)

  init(app: AppModel) {
    self.app = app
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { nil }

  override func loadView() {
    let root = AccessibilityGate()
    root.claim = { [weak self] point, event in self?.rootClaim(point, event: event) ?? .normal }
    root.isHidden = true
    root.backgroundColor = .clear
    for host in [backdrop, topChrome, bar, grid] { host.overrideUserInterfaceStyle = .dark }
    for host in [backdrop, topChrome, bar, pageBar, grid] {
      host.view.backgroundColor = .clear
      if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
      addChild(host)
    }
    backdrop.view.isUserInteractionEnabled = false
    root.addSubview(backdrop.view)
    root.addSubview(cardsView)
    gridShell.addSubview(grid.view)
    root.addSubview(gridShell)
    topChromeShell.accepts = { [weak self] point in self?.topChromeTakes(point) ?? false }
    topChromeShell.addSubview(topChrome.view)
    root.addSubview(topChromeShell)
    barShell.accepts = { [weak self] point in self?.barTakes(point) ?? false }
    barShell.addSubview(bar.view)
    root.addSubview(barShell)
    pageBarShell.isUserInteractionEnabled = false
    pageBarShell.alpha = 0
    pageBarShell.addSubview(pageBar.view)
    for thumbnail in risingThumbnails { pageBarShell.addSubview(thumbnail) }
    pageBarShell.layer.zPosition = Self.pageBarDepth
    cardsView.addSubview(pageBarShell)
    for host in [backdrop, topChrome, bar, pageBar, grid] { host.didMove(toParent: self) }
    applyGrid(animated: false)
    view = root

    let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
    tap.delegate = self
    cardsView.addGestureRecognizer(tap)
    let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
    pan.delegate = self
    cardsView.addGestureRecognizer(pan)

    stage.toggleGrid = { [weak self] in self?.toggleGrid() }
    stage.openFromGrid = { [weak self] id in self?.openFromGrid(id) }
    stage.closeFromGrid = { [weak self] id in self?.app.closeTab(id) }
    stage.dismissArchiveCard = { [weak self] in self?.dismissArchiveCard() }
    stage.closeAll = { [weak self] in self?.app.closeAllTabs() }
    rebuildHosts()
  }

  private func rebuildHosts() {
    let app = app
    let environment = environment
    backdrop.rootView = AnyView(TabsBackdrop(look: environment.look).deckStageEnvironment(app, environment))
    topChrome.rootView = AnyView(DeckStageTopChrome(stage: stage).deckStageEnvironment(app, environment))
    grid.rootView = AnyView(DeckStageGrid(stage: stage).deckStageEnvironment(app, environment))
    bar.rootView = AnyView(DeckStageBar(stage: stage).deckStageEnvironment(app, environment))
    pageBar.rootView = AnyView(PageBarStandIn(stage: stage).deckStageEnvironment(app, environment))
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let bounds = view.bounds
    for subview in [backdrop.view!, cardsView, gridShell, topChromeShell, barShell, pageBarShell] { subview.frame = bounds }
    topChrome.view.frame = bounds
    grid.view.frame = bounds
    bar.view.frame = bounds
    pageBar.view.frame = bounds
    updateGeometry()
  }

  private func updateGeometry() {
    let insets = view.window?.safeAreaInsets ?? view.safeAreaInsets
    let reserve = stage.isShowingArchiveCard && !app.deck.isGrid ? TabsLayout.archiveCardHeight + DeckStageModel.archiveCardGap : 0
    let next = TabsDeckGeometry(
      container: view.bounds.size,
      safeTop: insets.top,
      safeBottom: insets.bottom,
      safeSide: max(insets.left, insets.right),
      reserveAboveBar: reserve
    )
    guard next != stage.geometry, next.container.width > 0 else { return }
    stage.geometry = next
    for card in cards.values { card.resize(to: next.cardSize) }
    if phase == .settled { layoutCards() }
  }

  private var awaitingSurface = false

  func prewarm() {
    guard phase == .hidden, isViewLoaded else { return }
    updateGeometry()
    order = sourceOrder
    syncCards()
    UIView.performWithoutAnimation { layoutCards() }
  }

  func presentFromTap() {
    guard phase == .hidden else { return }
    awaitingSurface = true
    present()
  }

  func surfaceChanged(_ surface: AppModel.Surface) {
    if awaitingSurface {
      guard surface == .tabSwitcher else { return }
      awaitingSurface = false
      return
    }
    switch (surface, phase) {
    case (.tabSwitcher, .hidden):
      present()
    case (.tabSwitcher, _), (_, .hidden), (_, .closing), (_, .returning):
      break
    default:
      hide()
    }
  }

  private func present() {
    HarnessProbe.mark("deck.present")
    updateGeometry()
    setPageBar(false)
    stage.set(\.query, "")
    stage.set(\.isSearching, false)
    shownSpace = app.currentSpace?.syncId
    stage.set(\.isShowingArchiveCard, app.deck.shouldOfferArchiveCard(openTabs: app.deckTabs.count))
    updateGeometry()
    order = sourceOrder
    checkOrder()
    stage.set(\.isEmpty, order.isEmpty)
    lifts = [:]
    let entrance = app.deck.entrance
    if entrance != .plain { app.deck.entrance = .plain }
    observeModel()

    var from: UUID?
    if case .fromPage(let id) = entrance { from = id }
    let live = from.flatMap { app.web.existingWebTab($0)?.webView }.flatMap { $0.window != nil ? $0 : nil }
    if let from, let index = order.firstIndex(of: from) {
      scroll = Double(max(0, min(index - 1, order.count - 1)))
      if index < order.count - 1 { scroll = Double(index) }
    } else {
      scroll = Double(max(0, order.count - 2))
    }
    syncCards()
    if let from, let live, let snapshot = liveSnapshot(of: live) {
      cards[from]?.setLive(snapshot)
      pendingThumbnail = (live, from)
    }
    defer { capturePendingThumbnail() }

    setVisible(true)
    let reduceMotion = UIAccessibility.isReduceMotionEnabled
    guard let from, order.contains(from), !reduceMotion, !app.deck.isGrid else {
      phase = .settled
      if app.deck.isGrid { stage.gridScroll += 1 }
      applyGrid(animated: false)
      UIView.performWithoutAnimation { layoutCards() }
      setChrome(alpha: 0, backdrop: 0)
      UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
        self.setChrome(alpha: 1, backdrop: 1)
      }
      commitNow()
      return
    }
    applyGrid(animated: false)
    phase = .opening(from)
    UIView.performWithoutAnimation {
      layoutCards(progress: 0)
      setChrome(alpha: 0, backdrop: 0)
    }
    runOpen(headersDelayed: true)
    commitNow()
  }

  private func runOpen(headersDelayed: Bool) {
    let generation = beginTransitions()
    let main = UIViewPropertyAnimator(duration: 0.5, timingParameters: Self.spring(response: Self.openResponse))
    main.isUserInteractionEnabled = true
    main.isInterruptible = true
    main.addAnimations {
      self.layoutCards(progress: 1) { $0 != .launcher }
      self.backdrop.view.alpha = 1
    }
    let chrome = { self.topChromeShell.alpha = 1; self.layoutHeaders(alpha: 1) }
    if headersDelayed {
      main.addAnimations(chrome, delayFactor: 0.45)
    } else {
      main.addAnimations(chrome)
    }
    let fly = UIViewPropertyAnimator(duration: 0.5, timingParameters: Self.spring(response: Self.flyResponse))
    fly.isUserInteractionEnabled = true
    fly.isInterruptible = true
    fly.addAnimations { self.layoutCards(progress: 1) { $0 == .launcher } }
    var pending = 2
    for animator in [main, fly] {
      animator.addCompletion { [weak self] position in
        guard let self, generation == self.transitionGeneration, position == .end else { return }
        pending -= 1
        guard pending == 0, case .opening = self.phase else { return }
        self.transitions = []
        self.settled()
      }
      transitions.append(animator)
      animator.startAnimation()
    }
  }

  private func beginTransitions() -> Int {
    transitionGeneration += 1
    return transitionGeneration
  }

  private var pendingThumbnail: (webView: WKWebView, id: UUID)?

  private func capturePendingThumbnail() {
    DispatchQueue.main.async { [weak self] in
      guard let self, let pending = self.pendingThumbnail else { return }
      self.pendingThumbnail = nil
      self.captureThumbnail(of: pending.webView, tabID: pending.id)
    }
  }

  private func settled() {
    phase = .settled
  }

  private func open(_ id: UUID) {
    HarnessProbe.mark("deck.cardTap")
    stage.blurSearch += 1
    if case .opening(id) = phase {
      HarnessProbe.mark("deck.return")
      stopTransition()
      phase = .returning(id)
      setPageBar(true)
      runHome(to: id, duration: Self.returnDuration, timing: Self.returnCurve)
      commitNow()
      return
    }
    stopTransition()
    stopSettling()
    guard phase == .settled || phase.isOpening, order.contains(id) else { return }
    phase = .closing(id)
    setPageBar(true)
    if UIAccessibility.isReduceMotionEnabled {
      app.beginOpening(id)
      finishClosing(on: id)
      return
    }
    if let card = cards[id], !card.isShowingLive, !card.hasImage {
      card.setImage(coverImage(for: id))
    }
    runHome(to: id, duration: Self.landingDuration, timing: Self.landingCurve)
    commitNow()
    if order.last != id {
      let generation = transitionGeneration
      DispatchQueue.main.async { [weak self] in
        guard let self, case .closing(id) = self.phase, generation == self.transitionGeneration else { return }
        self.riseThumbnails(opening: id)
      }
    }
    app.beginOpening(id)
  }

  private func reopen(from id: UUID) {
    guard order.contains(id) else { return }
    stopTransition()
    phase = .opening(id)
    setPageBar(false)
    let next = sourceOrder
    if next != order, next.last == id {
      order = next
      syncCards()
      scroll = Double(max(0, order.count - 2))
      UIView.performWithoutAnimation { layoutCards(progress: 0) { $0 != .expanded } }
    }
    checkOrder()
    runOpen(headersDelayed: false)
    commitNow()
  }

  private func checkOrder() {
    guard stage.query.isEmpty, let selected = app.tabs.selectedTabID, order.contains(selected), order.last != selected else { return }
    HarnessProbe.mark("deck.misordered")
  }

  private func runHome(to id: UUID, duration: TimeInterval, timing: UICubicTimingParameters) {
    let generation = beginTransitions()
    for (index, other) in order.enumerated() where role(for: other, at: index) == .launcher {
      headers[other]?.alpha = 0
    }
    let animator = UIViewPropertyAnimator(duration: duration, timingParameters: timing)
    animator.isInterruptible = true
    animator.addAnimations {
      self.layoutCards(progress: 0) { $0 != .launcher }
      self.backdrop.view.alpha = 0
      self.topChromeShell.alpha = 0
      self.layoutHeaders(alpha: 0)
    }
    animator.addCompletion { [weak self] position in
      guard let self, generation == self.transitionGeneration, position == .end else { return }
      self.transitions = []
      switch self.phase {
      case .closing(id), .returning(id): self.finishClosing(on: id)
      default: break
      }
    }
    let tuck = UIViewPropertyAnimator(duration: duration, timingParameters: Self.spring(response: Self.tuckResponse))
    tuck.isInterruptible = true
    tuck.addAnimations { self.layoutCards(progress: 0) { $0 == .launcher } }
    transitions = [animator, tuck]
    animator.startAnimation()
    tuck.startAnimation()
  }

  private static let expandedDepth: Double = 100_000
  private static let pageBarDepth: CGFloat = 150_000
  private static let landingLauncherDepth: Double = 200_000
  private static let openResponse: Double = 0.19
  private static let flyResponse: Double = 0.28
  private static let tuckResponse: Double = 0.15
  private static let landingDuration: TimeInterval = 0.34
  private static let landingCurve = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.325, y: 0.525), controlPoint2: CGPoint(x: 0.1, y: 1))
  private static let returnDuration: TimeInterval = 0.3
  private static let returnCurve = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.3, y: 0.4), controlPoint2: CGPoint(x: 0.175, y: 1))

  private func finishClosing(on id: UUID) {
    HarnessProbe.mark("deck.closed")
    hide()
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) { app.openTab(id) }
  }

  private func hide() {
    pendingThumbnail = nil
    stopTransition()
    stopSettling()
    phase = .hidden
    setVisible(false)
    setPageBar(false)
    stage.blurSearch += 1
    for card in cards.values { card.setLive(nil) }
  }

  private func openFromGrid(_ id: UUID) {
    stage.blurSearch += 1
    phase = .closing(id)
    finishClosing(on: id)
  }

  private func stopTransition() {
    guard !transitions.isEmpty else { return }
    let running = transitions
    transitions = []
    transitionGeneration += 1
    for animator in running where animator.state == .active {
      animator.stopAnimation(false)
      animator.finishAnimation(at: .current)
    }
  }

  private static func spring(response: Double, velocity: CGVector = .zero) -> UISpringTimingParameters {
    let stiffness = pow(2 * .pi / response, 2)
    return UISpringTimingParameters(mass: 1, stiffness: stiffness, damping: 2 * sqrt(stiffness), initialVelocity: velocity)
  }

  private var sourceOrder: [UUID] {
    let needle = stage.query.trimmingCharacters(in: .whitespacesAndNewlines)
    let ordered = app.deckOrder
    guard !needle.isEmpty else { return ordered.map(\.id) }
    return ordered.filter { TabText.matches($0, needle) }.map(\.id)
  }

  private func syncCards() {
    let byID = Dictionary(app.deckTabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let wanted = Set(order)
    for (id, card) in cards where !wanted.contains(id) {
      card.removeFromSuperview()
      headers[id]?.removeFromSuperview()
      cards[id] = nil
      headers[id] = nil
    }
    for id in order {
      guard let tab = byID[id] else { continue }
      let card: DeckCardView
      if let existing = cards[id] {
        card = existing
      } else {
        card = DeckCardView(tabID: id, size: geometry.cardSize)
        card.addInteraction(UIContextMenuInteraction(delegate: self))
        cardsView.addSubview(card)
        cards[id] = card
        let header = DeckCardHeaderView(frame: .zero)
        cardsView.addSubview(header)
        headers[id] = header
      }
      card.configure(tab: tab, image: card.isShowingLive ? nil : thumbnail(for: tab))
      card.accessibilityCustomActions = [UIAccessibilityCustomAction(name: String(localized: "Close Tab")) { [weak self] _ in
        self?.close(id, animated: false)
        return true
      }]
      headers[id]?.configure(tab: tab)
    }
    stage.set(\.isEmpty, order.isEmpty)
  }

  private func thumbnail(for tab: BrowserTab) -> UIImage? {
    if let cover = app.browse.covers.image(for: tab.id) { return cover }
    if let name = tab.snapshotFileName, let cached = app.web.snapshots.cachedImage(named: name) { return UIImage(cgImage: cached) }
    if let name = tab.snapshotFileName {
      let id = tab.id
      Task { [weak self] in
        guard let image = await self?.app.web.snapshots.image(named: name), let card = self?.cards[id], !card.isShowingLive else { return }
        card.setImage(UIImage(cgImage: image))
      }
    }
    return nil
  }

  private func coverImage(for id: UUID) -> UIImage? {
    guard let tab = app.tabs.tab(id) else { return nil }
    return thumbnail(for: tab)
  }

  private func role(for id: UUID, at index: Int) -> DeckRole {
    switch phase {
    case .hidden, .settled:
      return .stay
    case .opening(let expanded):
      return launchRole(for: id, at: index, expanded: expanded)
    case .returning(let expanded):
      return launchRole(for: id, at: index, expanded: expanded)
    case .closing(let expanded):
      guard let expandedIndex = order.firstIndex(of: expanded) else { return .stay }
      if id == expanded { return .expanded }
      if expandedIndex == order.count - 1 { return .launcher }
      return index < expandedIndex ? .slideLeft : .slideRight
    }
  }

  private var launchAnchor: Int? {
    switch phase {
    case .opening(let expanded?), .returning(let expanded), .closing(let expanded):
      return order.firstIndex(of: expanded)
    default:
      return nil
    }
  }

  private func launchDepth(at index: Int, anchor: Int?) -> Int {
    guard let anchor else { return 1 }
    return max(anchor - 1 - index, 0)
  }

  private func launchRole(for id: UUID, at index: Int, expanded: UUID?) -> DeckRole {
    guard let expanded, let expandedIndex = order.firstIndex(of: expanded) else { return .stay }
    if id == expanded { return .expanded }
    return index < expandedIndex ? .launcher : .slideRight
  }

  private func layoutCards(progress: Double = 1, only include: ((DeckRole) -> Bool)? = nil) {
    let range = TabsDeckGeometry.renderedRange(around: scroll, count: order.count)
    let end = TabsDeckGeometry.endBlend(scroll: scroll, count: order.count)
    let screenWidth = geometry.container.width
    let anchor = launchAnchor
    for (index, id) in order.enumerated() {
      guard let card = cards[id], let header = headers[id] else { continue }
      let role = role(for: id, at: index)
      if let include, !include(role) { continue }
      let visible = range.contains(index) || role == .expanded
      card.isHidden = !visible
      header.isHidden = !visible
      guard visible else { continue }
      let relative = Double(index) - scroll
      let motion = DeckMotion(relative: relative, scaleProgress: progress, positionProgress: progress, lift: Double(lifts[id] ?? 0), vanish: 0)
      let depth = role == .launcher ? launchDepth(at: index, anchor: anchor) : 0
      let pose = DeckPose.resolve(motion, role: role, geometry: geometry, isLast: index == order.count - 1, end: end, launchDepth: depth)
      let visibleHeight = pose.visibleHeight ?? geometry.cardSize.height
      let cropShift = (geometry.cardSize.height - visibleHeight) / 2 * pose.scale
      card.center = CGPoint(x: pose.center.x - sin(pose.rotation) * cropShift, y: pose.center.y + cos(pose.rotation) * cropShift)
      card.transform = CGAffineTransform(rotationAngle: pose.rotation).scaledBy(x: pose.scale, y: pose.scale)
      card.setCorner(pose.corner / max(pose.scale, 0.01), edge: 0.5 / max(pose.scale, 0.01))
      card.setDim(pose.dim)
      card.setClip(topExtension: geometry.cardTopExtension, reveal: pose.reveal, visibleHeight: visibleHeight)
      card.alpha = pose.opacity
      let expanded = role == .expanded ? Self.expandedDepth : (role == .launcher && isLanding && depth <= 1 ? Self.landingLauncherDepth : 0)
      card.layer.zPosition = CGFloat(Double(index) * 2 + expanded)
      header.layer.zPosition = CGFloat(Double(index) * 2 + 1 + expanded)
      let cardHeight = geometry.cardSize.height * pose.scale
      let cardWidth = geometry.cardSize.width * pose.scale
      let left = pose.center.x - cardWidth / 2
      let width = max(min(pose.visibleWidth, screenWidth - left) - 8, 0)
      header.frame = CGRect(
        x: left,
        y: pose.center.y - cardHeight / 2 - TabsDeckGeometry.headerAboveCard * pose.scale,
        width: width,
        height: TabsDeckGeometry.headerHeight
      )
      header.layout(width: width, scale: pose.scale)
      headerTucks[id] = 1 - (1 - TabsPalette.tuckedHeaderOpacity) * min(max(-relative, 0), 1)
      if phase == .settled { header.alpha = headerAlpha(for: id) }
    }
  }

  private func headerAlpha(for id: UUID) -> CGFloat {
    max(0, 1 + (lifts[id] ?? 0) / 120) * (headerTucks[id] ?? 1)
  }

  private var isLanding: Bool {
    switch phase {
    case .closing, .returning: true
    default: false
    }
  }

  private func layoutHeaders(alpha: CGFloat) {
    for (id, header) in headers { header.alpha = alpha * headerAlpha(for: id) }
  }

  private func rootClaim(_ point: CGPoint, event: UIEvent?) -> TouchClaim {
    guard let event, event.type == .touches else { return .normal }
    if ownedTouchEvent == event.timestamp { return .own }
    guard isLanding else { return .normal }
    if isOnPageTabsButton(point) {
      if case .closing(let id) = phase { turnBack(to: id) }
      if case .returning(let id) = phase { turnBack(to: id) }
      ownedTouchEvent = event.timestamp
      return .own
    }
    landNow()
    return .pass
  }

  private func turnBack(to id: UUID) {
    HarnessProbe.mark("tabs.tap", "midLanding")
    reopen(from: id)
  }

  private func landNow() {
    switch phase {
    case .closing(let id), .returning(let id):
      HarnessProbe.mark("deck.landNow")
      stopTransition()
      finishClosing(on: id)
    default:
      break
    }
  }

  func turnBackIfLanding() -> Bool {
    switch phase {
    case .closing(let id), .returning(let id):
      turnBack(to: id)
      return true
    default:
      return false
    }
  }

  private func topChromeTakes(_ point: CGPoint) -> Bool {
    if stage.isEmpty { return true }
    guard stage.isShowingArchiveCard, !app.deck.isGrid else { return false }
    let center = DeckStageModel.archiveCardCenterY(geometry)
    return abs(point.y - center) <= TabsLayout.archiveCardHeight / 2 + 4
  }

  private func barTakes(_ point: CGPoint) -> Bool {
    point.y >= barTop
  }

  private var barTop: CGFloat {
    DeckStageModel.barCenterY(geometry, keyboardOverlap: stage.keyboardOverlap) - TabsLayout.barHitTarget / 2 - 4
  }

  private func setVisible(_ visible: Bool) {
    view.isHidden = !visible
    (view as? AccessibilityGate)?.isOpen = visible
    view.accessibilityViewIsModal = visible
    stage.set(\.isPresented, visible)
    app.pageBar?.alpha = visible ? 0 : 1
  }

  private func setPageBar(_ page: Bool) {
    barShell.alpha = page ? 0 : 1
    barShell.isUserInteractionEnabled = !page
    pageBarShell.alpha = page ? 1 : 0
    stopRise()
  }

  private static let riseDistance: CGFloat = 72
  private static let riseDelay: TimeInterval = 0.05
  private static let riseResponse: Double = 0.19

  private func riseThumbnails(opening id: UUID) {
    stopRise()
    let others = order.filter { $0 != id }
    let picks = [others.count > 1 ? others[others.count - 2] : nil, others.last]
    let places = [(geometry.tabButtonBackCenter, DeckPose.backTilt), (geometry.tabButtonCenter, DeckPose.frontTilt)]
    for ((view, pick), place) in zip(zip(risingThumbnails, picks), places) {
      guard let pick, let tab = app.tabs.tab(pick), !UIAccessibility.isReduceMotionEnabled else { continue }
      view.configure(image: thumbnail(for: tab), fill: UIColor(BarPalette.tileFill), pageTopShare: geometry.pageTopShare)
      view.transform = .identity
      view.center = place.0
      view.transform = CGAffineTransform(rotationAngle: place.1).concatenating(CGAffineTransform(translationX: 0, y: Self.riseDistance))
      view.isHidden = false
    }
    let animator = UIViewPropertyAnimator(duration: 0.5, timingParameters: Self.spring(response: Self.riseResponse))
    animator.isInterruptible = true
    animator.addAnimations {
      for (view, place) in zip(self.risingThumbnails, places) where !view.isHidden {
        view.transform = CGAffineTransform(rotationAngle: place.1)
      }
    }
    riseAnimator = animator
    animator.startAnimation(afterDelay: Self.riseDelay)
  }

  private func stopRise() {
    if let animator = riseAnimator, animator.state == .active { animator.stopAnimation(true) }
    riseAnimator = nil
    for view in risingThumbnails { view.isHidden = true }
  }

  private func commitNow() {
    CATransaction.flush()
    HarnessProbe.mark("anim.committed")
  }

  private func setChrome(alpha: CGFloat, backdrop backdropAlpha: CGFloat) {
    topChromeShell.alpha = alpha
    backdrop.view.alpha = backdropAlpha
    layoutHeaders(alpha: alpha)
  }

  private func focusedIndex(at scroll: Double) -> Int {
    min(max(Int(scroll.rounded()), 0), max(order.count - 1, 0))
  }

  private func liveSnapshot(of webView: WKWebView) -> UIView? {
    webView.snapshotView(afterScreenUpdates: false)
  }

  private func captureThumbnail(of webView: WKWebView, tabID: UUID) {
    let configuration = WKSnapshotConfiguration()
    configuration.afterScreenUpdates = true
    configuration.snapshotWidth = NSNumber(value: Double(webView.bounds.width) * min(Double(webView.traitCollection.displayScale), 2) / max(Double(webView.traitCollection.displayScale), 1))
    webView.takeSnapshot(with: configuration) { [weak self] image, _ in
      MainActor.assumeIsolated {
        guard let self, let image else { return }
        HarnessProbe.mark("thumb")
        self.app.browse.covers.store(image, for: tabID)
        self.app.persistSnapshot(image, for: tabID)
      }
    }
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    let landing: Bool
    switch phase {
    case .hidden: return false
    case .opening, .settled: landing = false
    case .closing, .returning: landing = true
    }
    return !landing
  }

  private func isOnPageTabsButton(_ point: CGPoint) -> Bool {
    let leading = view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? view.bounds.width - point.x : point.x
    return point.y >= barTop - 12 && leading <= geometry.safeSide + 80
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
    false
  }

  private func card(at point: CGPoint) -> UUID? {
    var best: (UUID, CGFloat)?
    for (id, card) in cards where !card.isHidden && card.alpha > 0.05 {
      let frame = card.layer.presentation()?.frame ?? card.frame
      guard frame.contains(point) else { continue }
      let z = card.layer.zPosition
      if best == nil || z > best!.1 { best = (id, z) }
    }
    return best?.0
  }

  @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
    let point = recognizer.location(in: cardsView)
    guard phase == .settled || phase.isOpening else { return }
    guard let id = card(at: point) else {
      stage.blurSearch += 1
      return
    }
    open(id)
  }

  @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
    let translation = recognizer.translation(in: cardsView)
    switch recognizer.state {
    case .began:
      if phase.isOpening { landOpening() }
      guard phase == .settled else { return }
      stopSettling()
      drag = nil
      panStart = CGPoint(x: recognizer.location(in: cardsView).x - translation.x, y: recognizer.location(in: cardsView).y - translation.y)
    case .changed:
      if drag == nil, phase == .settled, hypot(translation.x, translation.y) > 4 {
        if abs(translation.y) > abs(translation.x), translation.y < 0, let id = card(at: panStart) {
          drag = .lift(id, start: lifts[id] ?? 0)
        } else {
          drag = .horizontal(start: scroll)
          tickedCard = focusedIndex(at: scroll)
          selection.prepare()
        }
      }
      switch drag {
      case .horizontal(let start):
        scroll = TabsDeckGeometry.rubberBand(start + geometry.scrollDelta(forDrag: translation.x), count: order.count)
        UIView.performWithoutAnimation { layoutCards() }
        let focused = focusedIndex(at: scroll)
        if let ticked = tickedCard, ticked != focused {
          tickedCard = focused
          selection.selectionChanged()
        }
      case .lift(let id, let start):
        let dy = translation.y
        lifts[id] = start + (dy < 0 ? dy : dy * 0.12)
        UIView.performWithoutAnimation { layoutCards() }
      case nil:
        break
      }
    case .ended, .cancelled, .failed:
      let velocity = recognizer.velocity(in: cardsView)
      switch drag {
      case .horizontal:
        let target = geometry.settleTarget(from: scroll, velocity: velocity.x, count: order.count)
        settle(to: target, velocity: geometry.scrollDelta(forDrag: velocity.x))
      case .lift(let id, _):
        if TabsDeckGeometry.shouldClose(translation: translation.y, velocity: velocity.y, cardHeight: geometry.cardSize.height) {
          impact.impactOccurred()
          close(id, animated: true, velocity: velocity.y)
        } else {
          lifts[id] = nil
          UIViewPropertyAnimator(duration: 0.5, timingParameters: Self.spring(response: Self.liftReturnResponse)).run { self.layoutCards() }
        }
      case nil:
        break
      }
      drag = nil
      tickedCard = nil
    default:
      break
    }
  }

  private func landOpening() {
    stopTransition()
    settled()
    UIView.performWithoutAnimation {
      layoutCards()
      setChrome(alpha: 1, backdrop: 1)
    }
  }

  private func settle(to target: Int, velocity: Double = 0) {
    stopSettling()
    let clamped = Double(min(max(target, 0), max(order.count - 1, 0)))
    settle = ScrollSpring(from: scroll, to: clamped, velocity: velocity, response: 0.4, start: CACurrentMediaTime())
    let link = CADisplayLink(target: DisplayLinkProxy { [weak self] in self?.stepSettle() }, selector: #selector(DisplayLinkProxy.fire))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
    link.add(to: .main, forMode: .common)
    settleLink = link
  }

  private func stepSettle() {
    guard let spring = settle else { return stopSettling() }
    let (value, done) = spring.value(at: CACurrentMediaTime())
    scroll = value
    UIView.performWithoutAnimation { layoutCards() }
    if done { stopSettling() }
  }

  private func stopSettling() {
    settleLink?.invalidate()
    settleLink = nil
    settle = nil
  }

  private func close(_ id: UUID, animated: Bool, velocity: CGFloat = 0) {
    guard let index = order.firstIndex(of: id) else { return }
    HarnessProbe.mark("deck.closeCard")
    let card = cards[id]
    let header = headers[id]
    let focus = TabsDeckGeometry.scrollAfterRemoving(index: index, scroll: Int(scroll.rounded()), remaining: order.count - 1)
    order.remove(at: index)
    scroll = Double(focus)
    cards[id] = nil
    headers[id] = nil
    lifts[id] = nil
    headerTucks[id] = nil
    stage.isEmpty = order.isEmpty
    app.closeTab(id)
    guard animated, !UIAccessibility.isReduceMotionEnabled, let card else {
      card?.removeFromSuperview()
      header?.removeFromSuperview()
      UIViewPropertyAnimator(duration: 0.5, timingParameters: Self.spring(response: Self.gapResponse)).run { self.layoutCards() }
      return
    }
    let travel = card.frame.maxY + 20
    let speed = max(-velocity, travel / Self.throwDuration)
    let throwDuration = TimeInterval(min(travel / speed, Self.throwDuration))
    UIView.animate(withDuration: throwDuration, delay: 0, options: [.curveLinear, .allowUserInteraction, .beginFromCurrentState]) {
      card.center.y -= travel
      header?.center.y -= travel
      header?.alpha = 0
    } completion: { _ in
      card.removeFromSuperview()
      header?.removeFromSuperview()
    }
    let gap = UIViewPropertyAnimator(duration: 0.5, timingParameters: Self.spring(response: Self.gapResponse))
    gap.isInterruptible = true
    gap.addAnimations { self.layoutCards() }
    gap.startAnimation(afterDelay: Self.gapDelay)
  }

  private static let gapResponse: Double = 0.205
  private static let liftReturnResponse: Double = 0.2
  private static let gapDelay: TimeInterval = 0.03
  private static let throwDuration: CGFloat = 0.2

  private func observeModel() {
    guard !observing else { return }
    observing = true
    withObservationTracking {
      _ = app.deckTabs.map(\.id)
      _ = app.currentSpace?.syncId
      _ = stage.query
      _ = app.deck.isGrid
      _ = app.deck.command
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        self.observing = false
        guard self.phase != .hidden else { return }
        self.modelChanged()
        self.observeModel()
      }
    }
  }

  private func modelChanged() {
    if let command = app.deck.command {
      app.deck.command = nil
      perform(command.kind)
    }
    if gridShown != app.deck.isGrid { applyGrid(animated: false) }
    let space = app.currentSpace?.syncId
    let next = sourceOrder
    if space != shownSpace {
      shownSpace = space
      order = next
      scroll = Double(max(0, order.count - 2))
      lifts = [:]
      syncCards()
      cardsView.alpha = 0
      UIView.performWithoutAnimation { layoutCards() }
      UIView.animate(withDuration: 0.2) { self.cardsView.alpha = self.gridShown ? 0 : 1 }
      return
    }
    let live = Set(next)
    let focused = order.isEmpty ? nil : order[focusedIndex(at: scroll)]
    var merged = stage.query.isEmpty ? order.filter { live.contains($0) } : next
    let known = Set(merged)
    merged.append(contentsOf: next.filter { !known.contains($0) })
    guard merged != order else {
      syncCards()
      return
    }
    order = merged
    if let focused, let index = order.firstIndex(of: focused) {
      scroll = Double(index)
    } else {
      scroll = min(scroll, Double(max(order.count - 1, 0)))
    }
    syncCards()
    guard phase == .settled else { return }
    UIViewPropertyAnimator(duration: 0.5, timingParameters: Self.spring(response: 0.36)).run { self.layoutCards() }
  }

  private func perform(_ command: TabDeckModel.Command.Kind) {
    let focused = order.isEmpty ? nil : order[focusedIndex(at: scroll)]
    switch command {
    case .scroll(let target): settle(to: target)
    case .closeFocused: if let focused { close(focused, animated: true) }
    case .openFocused: if let focused { open(focused) }
    case .showArchiveCard:
      stage.isShowingArchiveCard = true
      updateGeometry()
    case .lift(let amount):
      if let focused { lifts[focused] = amount; UIView.performWithoutAnimation { layoutCards() } }
    }
  }

  private func toggleGrid() {
    HarnessProbe.mark("grid.toggle")
    stage.blurSearch += 1
    stopSettling()
    app.deck.isGrid.toggle()
    if app.deck.isGrid { stage.gridScroll += 1 }
    updateGeometry()
    UIView.performWithoutAnimation { layoutCards() }
    applyGrid(animated: !UIAccessibility.isReduceMotionEnabled)
    commitNow()
  }

  private var gridShown = false

  private func applyGrid(animated: Bool) {
    let showGrid = app.deck.isGrid
    gridShown = showGrid
    gridShell.isOpen = showGrid
    gridShell.isUserInteractionEnabled = showGrid
    cardsView.isUserInteractionEnabled = !showGrid
    let apply = {
      self.gridShell.alpha = showGrid ? 1 : 0
      self.cardsView.alpha = showGrid ? 0 : 1
    }
    guard animated else { return UIView.performWithoutAnimation(apply) }
    UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction], animations: apply)
  }

  private func dismissArchiveCard() {
    app.deck.hasShownArchiveCard = true
    stage.isShowingArchiveCard = false
    updateGeometry()
    UIViewPropertyAnimator(duration: 0.5, timingParameters: Self.spring(response: 0.3)).run { self.layoutCards() }
  }

  func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
    guard phase == .settled, let card = interaction.view as? DeckCardView, let tab = app.tabs.tab(card.tabID) else { return nil }
    return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
      self?.menu(for: tab)
    }
  }

  private func menu(for tab: BrowserTab) -> UIMenu {
    var sections: [UIMenuElement] = []
    if let url = app.shareURL(of: tab) {
      var items: [UIMenuElement] = [
        UIAction(title: String(localized: "Copy Link"), image: UIImage(systemName: "link")) { [weak self] _ in self?.app.copyLink(of: tab) },
        UIAction(title: String(localized: "Share"), image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in self?.share(url) },
      ]
      let devices = app.sendTargets(for: tab)
      if !devices.isEmpty {
        let actions = devices.map { device in
          UIAction(title: devices.count == 1 ? String(localized: "Send to \(device.name)") : device.name, image: UIImage(systemName: DeviceSymbol.name(for: device))) { [weak self] _ in
            self?.app.send(tab, to: device)
          }
        }
        items.append(devices.count == 1 ? actions[0] : UIMenu(title: String(localized: "Send to Device"), children: actions))
      }
      if !tab.isPrivate, app.sync.isEnabled {
        if app.isPinnedToMac(tab) {
          items.append(UIAction(title: String(localized: "Pinned to Mac"), attributes: .disabled) { _ in })
        } else {
          items.append(UIAction(title: String(localized: "Pin to Mac")) { [weak self] _ in self?.app.pinToMac(tab) })
        }
      }
      let others = tab.isPrivate ? [] : app.spaces.filter { $0.syncId != app.currentSpace?.syncId }
      if !others.isEmpty {
        items.append(UIMenu(title: String(localized: "Move to Space"), children: others.map { space in
          UIAction(title: space.name, image: UIImage(systemName: SpaceGlyph.menuSymbol(for: space))) { [weak self] _ in
            self?.app.moveTab(tab.id, toSpace: space.syncId)
          }
        }))
      }
      sections.append(UIMenu(options: .displayInline, children: items))
    }
    let id = tab.id
    sections.append(UIAction(title: String(localized: "Close Tab"), image: UIImage(systemName: "xmark"), attributes: .destructive) { [weak self] _ in
      self?.close(id, animated: true)
    })
    return UIMenu(children: sections)
  }

  private func share(_ url: URL) {
    let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    sheet.popoverPresentationController?.sourceView = view
    present(sheet, animated: true)
  }
}

private extension DeckStageController.Phase {
  var isOpening: Bool {
    if case .opening = self { return true }
    return false
  }
}

private extension UIViewPropertyAnimator {
  func run(_ animations: @escaping () -> Void) {
    isInterruptible = true
    addAnimations(animations)
    startAnimation()
  }
}

private struct ScrollSpring {
  let from: Double
  let to: Double
  let velocity: Double
  let response: Double
  let start: CFTimeInterval

  func value(at time: CFTimeInterval) -> (Double, Bool) {
    let omega = 2 * Double.pi / response
    let t = max(time - start, 0)
    let x0 = from - to
    let offset = (x0 + (velocity + omega * x0) * t) * exp(-omega * t)
    let speed = (velocity - (velocity + omega * x0) * omega * t) * exp(-omega * t)
    let done = abs(offset) < 0.0005 && abs(speed) < 0.01
    return (done ? to : to + offset, done)
  }
}

private final class DisplayLinkProxy: NSObject {
  let handler: () -> Void
  init(_ handler: @escaping () -> Void) { self.handler = handler }
  @objc func fire() { handler() }
}

final class AccessibilityGate: UIView {
  var isOpen = false
  var claim: ((CGPoint, UIEvent?) -> TouchClaim)?

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard let claim, !isHidden, self.point(inside: point, with: event) else { return super.hitTest(point, with: event) }
    switch claim(point, event) {
    case .normal: return super.hitTest(point, with: event)
    case .pass: return nil
    case .own: return self
    }
  }

  override var accessibilityElementsHidden: Bool {
    get { !isOpen }
    set {}
  }

  override var accessibilityElements: [Any]? {
    get { isOpen ? super.accessibilityElements : [] }
    set { super.accessibilityElements = newValue }
  }

  override func accessibilityElementCount() -> Int {
    isOpen ? super.accessibilityElementCount() : 0
  }
}

final class PassthroughView: UIView {
  var accepts: (CGPoint) -> Bool = { _ in true }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard alpha > 0.01, !isHidden, isUserInteractionEnabled, accepts(point) else { return nil }
    let hit = super.hitTest(point, with: event)
    return hit === self ? nil : hit
  }
}

enum TouchClaim {
  case normal
  case pass
  case own
}
