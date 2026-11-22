import ArdiaBrowser
import ArdiaDesign
import SwiftUI
import UIKit
import WebKit

/// The tab deck on a phone, built for speed:
///
/// - It is created once and stays mounted; showing it is a state change, never a view build.
/// - Cards are UIViews moved by `UIViewPropertyAnimator`, so transitions run in the render server and
///   a busy main thread cannot drop their frames. Every transition can be reversed or redirected
///   mid-flight; taps are hit-tested against where cards are on screen, not where they are going.
/// - The page's card is a GPU `snapshotView` of the live web view, free to make; the saved thumbnail
///   is taken afterwards with WebKit's asynchronous snapshot.
/// - A tapped tab is selected at once, so its page is ready under the deck when the card lands.
///
/// The header, grid, archive card and bar stay SwiftUI, hosted above the cards.
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
  /// The page's bar, kept built at all times so swapping to it is an opacity change, not a SwiftUI build.
  private let pageBar = UIHostingController(rootView: AnyView(EmptyView()))
  private let pageBarShell = AccessibilityGate()
  private let topChromeShell = PassthroughView()
  private let barShell = PassthroughView()
  private let cardsView = UIView()

  private var phase: Phase = .hidden
  private var order: [UUID] = []
  private var scroll: Double = 0
  private var cards: [UUID: DeckCardView] = [:]
  private var headers: [UUID: DeckCardHeaderView] = [:]
  private var lifts: [UUID: CGFloat] = [:]
  private var transition: UIViewPropertyAnimator?
  private var geometry: TabsDeckGeometry { stage.geometry }
  private var shownSpace: String?
  private var observing = false

  private var settle: ScrollSpring?
  private var settleLink: CADisplayLink?
  private enum Drag { case horizontal(start: Double), lift(UUID, start: CGFloat) }
  private var drag: Drag?
  private var panStart: CGPoint = .zero
  private var tickedCard: Int?
  /// The touch event a tabs-button press during a landing was claimed in. UIKit hit-tests a touch
  /// more than once; every pass for that event must keep it with the root.
  private var ownedTouchEvent: TimeInterval?
  private let selection = UISelectionFeedbackGenerator()
  private let impact = UIImpactFeedbackGenerator(style: .light)

  init(app: AppModel) {
    self.app = app
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { nil }

  // MARK: - View

  override func loadView() {
    let root = AccessibilityGate()
    root.claim = { [weak self] point, event in self?.rootClaim(point, event: event) ?? .normal }
    // isHidden, not alpha 0: a transparent full-screen tree still sits in front of the page for
    // accessibility, hiding the page's elements from VoiceOver.
    root.isHidden = true
    root.backgroundColor = .clear
    // The deck is dark whatever the system appearance, as Arc's is: pages read as lit cards on a
    // space-tinted night backdrop. The page's own bar (pageBar) keeps the page's appearance.
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
    root.addSubview(pageBarShell)
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
    pageBar.rootView = AnyView(PageBarStandIn(safeSide: stage.geometry.safeSide).deckStageEnvironment(app, environment))
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
    let chrome = stage.isShowingArchiveCard && !app.deck.isGrid ? TabsLayout.archiveCardBottom : TabsLayout.headerBottom
    let next = TabsDeckGeometry(
      container: view.bounds.size,
      safeTop: insets.top,
      safeBottom: insets.bottom,
      safeSide: max(insets.left, insets.right),
      chromeBottom: insets.top + chrome
    )
    guard next != stage.geometry, next.container.width > 0 else { return }
    stage.geometry = next
    for card in cards.values { card.resize(to: next.cardSize) }
    if phase == .settled { layoutCards() }
  }

  // MARK: - Surface

  /// Set while the deck has been shown directly from a tap and `app.surface` has not caught up yet.
  private var awaitingSurface = false

  /// Builds the cards for the current tabs while the app is idle after launch, so the first open
  /// pays no construction cost.
  func prewarm() {
    guard phase == .hidden, isViewLoaded else { return }
    updateGeometry()
    order = sourceOrder
    syncCards()
    UIView.performWithoutAnimation { layoutCards() }
  }

  /// Shows the deck from a tap without waiting for SwiftUI: the zoom-out is handed to Core Animation
  /// in this run-loop pass, and the surface change (and SwiftUI's re-render of the page behind) follows.
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
      // Something else took the user away (a search result, the grid, a received tab): leave at once.
      hide()
    }
  }

  private func present() {
    HarnessProbe.mark("deck.present")
    updateGeometry()
    setPageBar(false)
    stage.set(\.query, "")
    shownSpace = app.currentSpace?.syncId
    stage.set(\.isShowingArchiveCard, app.deck.shouldOfferArchiveCard(openTabs: app.deckTabs.count))
    updateGeometry()
    order = sourceOrder
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
      // Plain entrance (from the start page, the grid, reduced motion): a quick fade.
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
    let animator = UIViewPropertyAnimator(duration: 0.5, timingParameters: Self.spring(response: 0.26))
    animator.isUserInteractionEnabled = true
    animator.isInterruptible = true
    animator.addAnimations { self.layoutCards(progress: 1); self.backdrop.view.alpha = 1 }
    animator.addAnimations({ self.topChromeShell.alpha = 1; self.layoutHeaders(alpha: 1) }, delayFactor: 0.45)
    animator.addCompletion { [weak self] position in
      guard let self, case .opening = self.phase else { return }
      if position == .end { self.settled() }
    }
    transition = animator
    animator.startAnimation()
    commitNow()
  }

  /// The page just left. Its saved thumbnail is taken as soon as the zoom-out is on the render
  /// server, while the page is still in the window: waiting for the deck to come to rest lost it
  /// whenever another card was tapped first, and that card later landed on a stale picture that
  /// jumped to the live page.
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

  /// Opens a tab from the deck. Selecting happens now, so the page is in place before the card lands.
  private func open(_ id: UUID) {
    HarnessProbe.mark("deck.cardTap")
    stage.blurSearch += 1
    if case .opening(id) = phase {
      // Tapped the page's own card mid zoom-out: head straight back from wherever it is. A fresh
      // ease-out from the current position lands in a fixed, short time; reversing the spring would
      // replay its whole slow tail.
      HarnessProbe.mark("deck.return")
      stopTransition()
      phase = .returning(id)
      setPageBar(true)
      runHome(to: id, duration: Self.returnDuration)
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
    runHome(to: id, duration: Self.landingDuration)
    // The animation is committed to Core Animation first; selecting the tab (waking its web view,
    // re-rendering the page underneath) then happens while the card is already moving.
    commitNow()
    app.beginOpening(id)
  }

  /// Reverses a landing card back into the deck, from wherever it is on screen.
  private func reopen(from id: UUID) {
    guard order.contains(id) else { return }
    stopTransition()
    phase = .opening(id)
    setPageBar(false)
    let animator = UIViewPropertyAnimator(duration: 0.5, timingParameters: Self.spring(response: 0.26))
    animator.isInterruptible = true
    animator.addAnimations {
      self.layoutCards(progress: 1)
      self.backdrop.view.alpha = 1
      self.topChromeShell.alpha = 1
      self.layoutHeaders(alpha: 1)
    }
    animator.addCompletion { [weak self] position in
      guard let self, case .opening = self.phase, position == .end else { return }
      self.settled()
    }
    transition = animator
    animator.startAnimation()
    commitNow()
  }

  /// Expands the card for `id` to fill the screen and hands over to the page when it lands.
  private func runHome(to id: UUID, duration: TimeInterval) {
    let animator = UIViewPropertyAnimator(duration: duration, timingParameters: Self.landing)
    animator.isInterruptible = true
    animator.addAnimations {
      self.layoutCards(progress: 0)
      self.backdrop.view.alpha = 0
      self.topChromeShell.alpha = 0
      self.layoutHeaders(alpha: 0)
    }
    animator.addCompletion { [weak self] position in
      guard let self, position == .end else { return }
      switch self.phase {
      case .closing(id), .returning(id): self.finishClosing(on: id)
      default: break
      }
    }
    transition = animator
    animator.startAnimation()
  }

  /// A card growing into its page. Long enough to read as a move rather than a cut; it never holds
  /// anyone up, since a press on the tabs button reverses it at any point.
  private static let landingDuration: TimeInterval = 0.34
  /// Going back into the page just left, from partway out: a shorter trip.
  private static let returnDuration: TimeInterval = 0.28
  /// A soft ease-out with a definite end (what the hand-off to the page needs). Less front-loaded
  /// than a snap: about 60% of the way at a third of the time, then a long gentle settle.
  private static let landing = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.2, y: 0.8), controlPoint2: CGPoint(x: 0.2, y: 1))

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
    guard let animator = transition else { return }
    transition = nil
    if animator.state == .active {
      animator.stopAnimation(false)
      animator.finishAnimation(at: .current)
    }
  }

  private static func spring(response: Double, velocity: CGVector = .zero) -> UISpringTimingParameters {
    let stiffness = pow(2 * .pi / response, 2)
    return UISpringTimingParameters(mass: 1, stiffness: stiffness, damping: 2 * sqrt(stiffness), initialVelocity: velocity)
  }

  // MARK: - Cards

  private var sourceOrder: [UUID] {
    let needle = stage.query.trimmingCharacters(in: .whitespacesAndNewlines)
    let ordered = app.deckOrder
    guard !needle.isEmpty else { return ordered.map(\.id) }
    return ordered.filter { TabText.matches($0, needle) }.map(\.id)
  }

  /// Makes a card and header for every tab in the order and drops the rest.
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
      // Everything but the tapped card gathers back into the tabs button.
      guard order.contains(expanded) else { return .stay }
      return id == expanded ? .expanded : .launcher
    }
  }

  /// Roles while zooming out of a page, and while reversing that zoom back into it.
  private func launchRole(for id: UUID, at index: Int, expanded: UUID?) -> DeckRole {
    guard let expanded, let expandedIndex = order.firstIndex(of: expanded) else { return .stay }
    if id == expanded { return .expanded }
    return index < expandedIndex ? .launcher : .slideRight
  }

  /// Puts every card where the current phase, scroll and progress say it belongs. Called inside an
  /// animator to animate there, or outside one to jump.
  private func layoutCards(progress: Double = 1) {
    let range = TabsDeckGeometry.renderedRange(around: scroll, count: order.count)
    for (index, id) in order.enumerated() {
      guard let card = cards[id], let header = headers[id] else { continue }
      let role = role(for: id, at: index)
      let visible = range.contains(index) || role == .expanded
      card.isHidden = !visible
      header.isHidden = !visible
      guard visible else { continue }
      let motion = DeckMotion(relative: Double(index) - scroll, scaleProgress: progress, positionProgress: progress, lift: Double(lifts[id] ?? 0), vanish: 0)
      let pose = DeckPose.resolve(motion, role: role, geometry: geometry, isLast: index == order.count - 1, tilt: tilt(at: index))
      card.center = pose.center
      card.transform = CGAffineTransform(rotationAngle: pose.rotation).scaledBy(x: pose.scale, y: pose.scale)
      card.setCorner(pose.corner / max(pose.scale, 0.01), edge: 0.5 / max(pose.scale, 0.01))
      card.alpha = pose.opacity
      // Leaving the deck, gathered cards fly over the growing page into the button; arriving, they
      // come out from behind it.
      let expanded = role == .expanded ? 100_000.0 : (role == .launcher && isLanding ? 200_000.0 : 0)
      card.layer.zPosition = CGFloat(Double(index) * 2 + expanded)
      header.layer.zPosition = CGFloat(Double(index) * 2 + 1 + expanded)
      let width = max(pose.visibleWidth - 8, 0)
      let cardHeight = geometry.cardSize.height * pose.scale
      let cardWidth = geometry.cardSize.width * pose.scale
      header.frame = CGRect(
        x: pose.center.x - cardWidth / 2,
        y: pose.center.y - cardHeight / 2 - TabsLayout.headerGap - TabsDeckGeometry.headerHeight,
        width: width,
        height: TabsDeckGeometry.headerHeight
      )
      header.layout(width: width)
      if phase == .settled { header.alpha = max(0, 1 + (lifts[id] ?? 0) / 120) }
    }
  }

  private var isLanding: Bool {
    switch phase {
    case .closing, .returning: true
    default: false
    }
  }

  /// Gathered cards fan out a little, like the stack on the tabs button.
  private func tilt(at index: Int) -> CGFloat {
    index % 2 == 0 ? -0.2 : -0.07
  }

  private func layoutHeaders(alpha: CGFloat) {
    for (id, header) in headers { header.alpha = alpha * max(0, 1 + (lifts[id] ?? 0) / 120) }
  }

  /// While a card lands, the page it lands on is already in place underneath.
  /// - A finger on the page's tabs button turns straight back into the deck, on touch-down: the
  ///   landing is nearly over by then, and anything that waits (a gesture recognizer, even a
  ///   zero-duration long press, fires some 40 ms later) finds the deck already gone.
  /// - A touch anywhere else lands the card at once and goes through to the page, so the page is
  ///   live from the first touch.
  private func rootClaim(_ point: CGPoint, event: UIEvent?) -> TouchClaim {
    guard let event, event.type == .touches else { return .normal }
    if ownedTouchEvent == event.timestamp { return .own }
    guard isLanding else { return .normal }
    if isOnPageTabsButton(point) {
      if case .closing(let id) = phase { turnBack(to: id) }
      if case .returning(let id) = phase { turnBack(to: id) }
      // The rest of this touch was the tabs press; nothing in the deck may act on it.
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

  /// A tabs-button press that reached the page's own bar while a card was still landing.
  /// Returns whether it turned back into the deck.
  func turnBackIfLanding() -> Bool {
    switch phase {
    case .closing(let id), .returning(let id):
      turnBack(to: id)
      return true
    default:
      return false
    }
  }

  /// The header strip (and archive card), or everything when the grid or empty state is up.
  private func topChromeTakes(_ point: CGPoint) -> Bool {
    if stage.isEmpty { return true }
    let chrome = stage.isShowingArchiveCard ? TabsLayout.archiveCardBottom : TabsLayout.headerBottom
    return point.y < geometry.safeTop + chrome
  }

  /// The bottom bar's strip, wherever the keyboard has pushed it.
  private func barTakes(_ point: CGPoint) -> Bool {
    point.y >= barTop - 8
  }

  private var barTop: CGFloat {
    let overlap = stage.keyboardOverlap
    let center = overlap > 0 ? geometry.container.height - overlap - TabsLayout.barGap - TabsLayout.barCircle / 2 : geometry.barCenterY
    return center - TabsLayout.barCircle / 2
  }

  private func setVisible(_ visible: Bool) {
    view.isHidden = !visible
    (view as? AccessibilityGate)?.isOpen = visible
    view.accessibilityViewIsModal = visible
    stage.set(\.isPresented, visible)
  }

  /// Which bar is showing: the deck's, or (from the moment a tab is tapped) the page's.
  private func setPageBar(_ page: Bool) {
    barShell.alpha = page ? 0 : 1
    barShell.isUserInteractionEnabled = !page
    pageBarShell.alpha = page ? 1 : 0
  }

  /// Hands the animation just started to Core Animation now, before any heavy work in this pass.
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

  // MARK: - Thumbnails

  /// A GPU copy of the page as it is on screen (no main-thread drawing), sized to the page.
  private func liveSnapshot(of webView: WKWebView) -> UIView? {
    webView.snapshotView(afterScreenUpdates: false)
  }

  /// The saved card image, taken by WebKit off the main thread once the deck is already moving.
  private func captureThumbnail(of webView: WKWebView, tabID: UUID) {
    let configuration = WKSnapshotConfiguration()
    // `false` hands back a blank white image for a page that is already on screen; `true` waits for
    // the next paint, which costs nothing here since WebKit renders it off the main thread.
    configuration.afterScreenUpdates = true
    // 2x pixels: sharp on a card, and 44% of the bytes of a 3x capture.
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

  // MARK: - Gestures

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    let landing: Bool
    switch phase {
    case .hidden: return false
    case .opening, .settled: landing = false
    case .closing, .returning: landing = true
    }
    // Cards take no touches while one lands: the deck is leaving.
    return !landing
  }

  /// Where the page's bar draws its tabs button (leading end of the bar), generously.
  private func isOnPageTabsButton(_ point: CGPoint) -> Bool {
    let leading = view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? view.bounds.width - point.x : point.x
    return point.y >= barTop - 16 && leading <= geometry.safeSide + TabsLayout.barSideInset + TabsLayout.barCircle + 28
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
    false
  }

  /// The card under a point as it is on screen right now, mid-animation included.
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
      // The direction is decided on the first real movement; at .began the translation can be zero.
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
          close(id, animated: true)
        } else {
          lifts[id] = nil
          UIViewPropertyAnimator(duration: 0.5, timingParameters: Self.spring(response: 0.3)).run { self.layoutCards() }
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

  /// A drag during the zoom-out takes over from wherever the cards are.
  private func landOpening() {
    stopTransition()
    settled()
    UIView.performWithoutAnimation {
      layoutCards()
      setChrome(alpha: 1, backdrop: 1)
    }
  }

  // MARK: - Scroll settling

  /// Scroll is a single number the cards are laid out from, so it settles on a display link with
  /// a critically damped spring: interruptible at any instant by the next drag.
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

  // MARK: - Closing tabs

  private func close(_ id: UUID, animated: Bool) {
    guard order.contains(id) else { return }
    let remove = { [weak self] in
      guard let self, let index = self.order.firstIndex(of: id) else { return }
      let focus = TabsDeckGeometry.scrollAfterRemoving(index: index, scroll: Int(self.scroll.rounded()), remaining: self.order.count - 1)
      self.order.remove(at: index)
      self.scroll = Double(focus)
      self.cards[id]?.removeFromSuperview()
      self.headers[id]?.removeFromSuperview()
      self.cards[id] = nil
      self.headers[id] = nil
      self.lifts[id] = nil
      self.stage.isEmpty = self.order.isEmpty
      UIViewPropertyAnimator(duration: 0.5, timingParameters: Self.spring(response: 0.36)).run { self.layoutCards() }
      self.app.closeTab(id)
    }
    guard animated, !UIAccessibility.isReduceMotionEnabled, let card = cards[id] else {
      remove()
      return
    }
    let lift = (lifts[id] ?? 0) - geometry.cardSize.height * 0.18
    UIView.animate(withDuration: TabsMotion.flyAway, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
      card.center.y += lift - (self.lifts[id] ?? 0)
      card.transform = card.transform.scaledBy(x: 0.72, y: 0.72)
      card.alpha = 0
      self.headers[id]?.alpha = 0
    } completion: { _ in remove() }
  }

  // MARK: - Keeping up with the model

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

  /// Shows the grid or the stack. Both stay built; this only crossfades them.
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

  // MARK: - Card menu

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

/// A critically damped spring for one number, evaluated in closed form so any instant can be read.
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

/// A container whose subtree accessibility sees only while it is open. SwiftUI gathers a
/// representable's accessibility elements through its own bridge, which ignores `isHidden`, so the
/// hidden deck (and the inert copy of the page's bar) must say outright that it has none.
final class AccessibilityGate: UIView {
  var isOpen = false
  /// Who gets a touch at a point; nil is `.normal` everywhere.
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

/// Lets touches fall through outside the region its hosted SwiftUI draws controls in. Since iOS 18
/// a hosting view reports itself as the hit view for its own buttons, so "did the hit land on the
/// hosting view" can't tell a control from empty space; the owner says where the controls are.
final class PassthroughView: UIView {
  var accepts: (CGPoint) -> Bool = { _ in true }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard alpha > 0.01, !isHidden, isUserInteractionEnabled, accepts(point) else { return nil }
    let hit = super.hitTest(point, with: event)
    return hit === self ? nil : hit
  }
}

enum TouchClaim {
  /// Ordinary hit testing.
  case normal
  /// Through to whatever is underneath.
  case pass
  /// Kept by the view itself; none of its subviews see it.
  case own
}
