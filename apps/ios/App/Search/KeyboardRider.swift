import ArdiaDesign
import SwiftUI
import UIKit

struct RiderGrowth: Equatable {
  var panelHeight: CGFloat
  var lineAboveBottom: CGFloat
  var bandAboveBottom: CGFloat
  var fieldTop: CGFloat
  var fieldInset: CGFloat
  var fieldHeight: CGFloat
  var fieldLeading: CGFloat
  var fieldTrailing: CGFloat
  var capsule: CGSize
  var glyphSize: CGFloat
  var font: UIFont
  var panelFill: UIColor
  var panelBlurs: Bool
  var panelEdge: UIColor
  var panelRadius: CGFloat
  var fieldFill: UIColor
  var fieldEdge: UIColor
  var glyph: UIColor
  var placeholder: UIColor
  var text: UIColor
  var accessory: UIColor
  var accent: UIColor
  var tileFill: UIColor
  var tileEdge: UIColor
  var initialText: String
  var showsAccessories: Bool
  var dim: CGFloat
  var handsBackToBar: Bool
}

struct KeyboardRider<Content: View, Icons: View & Equatable, Band: View & Equatable>: UIViewControllerRepresentable {
  var holdsLift: Bool
  var dragOffset: CGFloat
  var isVisible: Bool
  var isInteractive: Bool
  var growth: RiderGrowth
  var onDismiss: () -> Void
  var onClosed: () -> Void = {}
  let content: Content
  let icons: Icons
  let band: Band

  final class Coordinator {
    var icons: Icons?
    var band: Band?
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIViewController(context: Context) -> KeyboardRiderController {
    KeyboardRiderController()
  }

  func updateUIViewController(_ controller: KeyboardRiderController, context: Context) {
    let transaction = context.transaction
    let coordinator = context.coordinator
    controller.onDismiss = onDismiss
    controller.onClosed = onClosed
    if coordinator.icons != icons {
      coordinator.icons = icons
      controller.setIcons(AnyView(icons))
    }
    if coordinator.band != band {
      coordinator.band = band
      controller.setBand(AnyView(band))
    }
    controller.update(
      content: AnyView(content),
      holdsLift: holdsLift,
      dragOffset: dragOffset,
      isVisible: isVisible,
      isInteractive: isInteractive,
      growth: growth,
      animatesDrag: transaction.animation != nil && !transaction.disablesAnimations
    )
  }
}

private final class PassThroughView: UIView {
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let hit = super.hitTest(point, with: event)
    return hit === self ? nil : hit
  }
}

private final class ShapeView: UIView {
  override class var layerClass: AnyClass { CAShapeLayer.self }
  var shape: CAShapeLayer { layer as! CAShapeLayer }
}

private final class PanelMaterialView: UIView {
  private let blur = BarBlurView()
  private let tint = UIView()
  private var blurs = true

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    clipsToBounds = true
    layer.cornerCurve = .continuous
    layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    for view in [blur, tint] {
      view.frame = bounds
      view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      addSubview(view)
    }
  }

  required init?(coder: NSCoder) { nil }

  func configure(_ growth: RiderGrowth) {
    if blurs != growth.panelBlurs {
      blurs = growth.panelBlurs
      blur.isHidden = !blurs
    }
    if tint.backgroundColor != growth.panelFill { tint.backgroundColor = growth.panelFill }
    if layer.cornerRadius != growth.panelRadius { layer.cornerRadius = growth.panelRadius }
    let edge = growth.panelEdge.cgColor
    if layer.borderColor != edge { layer.borderColor = edge }
    layer.borderWidth = 1 / max(traitCollection.displayScale, 1)
  }
}

private final class RiderDimView: UIView {
  var onTap: () -> Void = {}

  override init(frame: CGRect) {
    super.init(frame: frame)
    isAccessibilityElement = true
    accessibilityLabel = String(localized: "Close Search")
    accessibilityTraits = .button
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
  }

  required init?(coder: NSCoder) { nil }

  @objc private func tapped() { onTap() }

  override func accessibilityActivate() -> Bool {
    onTap()
    return true
  }
}

final class FieldMorphView: UIView {
  private let skin = UIView()
  private let tile = UIView()
  private let plus = UIImageView()
  private let label = UILabel()
  private let caret = UIView()
  private let mic = UIImageView()
  private let eyes = UIImageView()

  static let plusInsetOpen: CGFloat = 15
  static let plusToText: CGFloat = 21.5

  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = true
    isUserInteractionEnabled = false
    layer.cornerCurve = .continuous
    skin.layer.cornerCurve = .continuous
    skin.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    tile.layer.cornerCurve = .continuous
    tile.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    caret.layer.cornerRadius = 1
    label.lineBreakMode = .byClipping
    for view in [tile, skin, label, caret, mic, eyes, plus] { addSubview(view) }
  }

  required init?(coder: NSCoder) { nil }

  private var symbolKey: (CGFloat, CGFloat)?

  func configure(_ growth: RiderGrowth, text: String, showsCaret: Bool) {
    skin.backgroundColor = growth.fieldFill
    skin.layer.borderColor = growth.fieldEdge.cgColor
    skin.layer.borderWidth = 1 / max(traitCollection.displayScale, 1)
    tile.backgroundColor = growth.tileFill
    tile.layer.borderColor = growth.tileEdge.cgColor
    tile.layer.borderWidth = 0.5
    loadSymbols(glyphSize: growth.glyphSize, accessorySize: growth.font.pointSize)
    plus.tintColor = growth.glyph
    label.font = growth.font
    label.text = text.isEmpty ? String(localized: "Search...") : text
    label.textColor = text.isEmpty ? growth.placeholder : growth.text
    caret.backgroundColor = growth.accent
    caret.isHidden = !showsCaret
    for view in [mic, eyes] {
      view.tintColor = growth.accessory
      view.isHidden = !growth.showsAccessories || !text.isEmpty
    }
  }

  func loadSymbols(glyphSize: CGFloat, accessorySize: CGFloat) {
    guard symbolKey?.0 != glyphSize || symbolKey?.1 != accessorySize else { return }
    symbolKey = (glyphSize, accessorySize)
    plus.image = UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: glyphSize, weight: .medium))
    mic.image = UIImage(systemName: "mic", withConfiguration: UIImage.SymbolConfiguration(pointSize: accessorySize, weight: .medium))
    eyes.image = UIImage(systemName: "eyeglasses", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
    label.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 17))
    label.text = String(localized: "Search...")
    for view in [plus, mic, eyes, label] { view.sizeToFit() }
  }

  func pose(open: Bool, growth: RiderGrowth, fieldWidth: CGFloat) {
    let height = open ? growth.fieldHeight : growth.capsule.height
    let plusX = open ? Self.plusInsetOpen : growth.capsule.width / 2
    plus.center = CGPoint(x: plusX, y: height / 2)
    let textX = open ? growth.fieldLeading : growth.capsule.width / 2 + Self.plusToText
    let lineHeight = ceil(growth.font.lineHeight)
    label.frame = CGRect(x: textX, y: (height - lineHeight) / 2, width: fieldWidth, height: lineHeight)
    let caretHeight = lineHeight + 2
    caret.frame = CGRect(x: textX - 2, y: (height - caretHeight) / 2, width: 2, height: caretHeight)
    mic.center = CGPoint(x: fieldWidth - growth.fieldTrailing - 72 + 12, y: height / 2)
    eyes.center = CGPoint(x: fieldWidth - growth.fieldTrailing - 18, y: height / 2)
    layer.cornerRadius = height / 2
    skin.layer.cornerRadius = height / 2
    tile.layer.cornerRadius = height / 2
  }

  func setPlus(visible: Bool) { plus.alpha = visible ? 1 : 0 }
  func setSkin(visible: Bool) { skin.alpha = visible ? 1 : 0 }
  func setTile(visible: Bool) { tile.alpha = visible ? 1 : 0 }
  func setText(visible: Bool) {
    for view in [label, caret, mic, eyes] { view.alpha = visible ? 1 : 0 }
  }
}

@MainActor
enum SearchMotion {
  static weak var rider: KeyboardRiderController?

  static func begin(_ request: BrowseSession.SearchRequest) {
    rider?.prime(initialText: request.initialText, dims: request.origin == .page)
  }

  static func end() {
    rider?.end()
  }

  static func drag(_ dy: CGFloat) -> Bool {
    rider?.drag(dy) ?? false
  }

  static func dragEnded(_ dy: CGFloat, velocity: CGFloat, commits: Bool) -> Bool? {
    rider?.dragEnded(dy, velocity: velocity, commits: commits)
  }
}

final class KeyboardRiderController: UIViewController {
  var onDismiss: () -> Void = {}
  var onClosed: () -> Void = {}

  private let host = UIHostingController(rootView: AnyView(EmptyView()))
  private let iconsHost = UIHostingController(rootView: AnyView(EmptyView()))
  private let bandHost = UIHostingController(rootView: AnyView(EmptyView()))
  private let dim = RiderDimView()
  private let riser = PassThroughView()
  private let body = PassThroughView()
  private let material = PanelMaterialView()
  private let fieldMask = UIView()
  private let maskBase = ShapeView()
  private let maskHole = UIView()
  private let morph = FieldMorphView()
  private var growth: RiderGrowth?
  private var isVisible = false
  private var isInteractive = false
  private var holdsLift = false
  private var heldLift: CGFloat?
  private var dragOffset: CGFloat = 0
  private var keyboardOverlap: CGFloat = 0
  private var awaitingKeyboard = false
  private var openTarget: CGFloat = 0
  private var generation = 0
  private var waitGeneration = 0
  private var settledLift: CGFloat?
  private var pendingVisibility: Bool?
  private var pendingGeneration = 0
  private var requestedVisible = false
  private var isDraggingOpen = false
  private var launchVelocity: CGFloat = 0
  private var opensFromDrag = false
  private var dragPeak: CGFloat = 0
  private var isMorphing = false
  nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

  static let liftKey = "searchPanel.keyboardLift"
  static let keyboardThreshold: CGFloat = 120
  static let keyboardWait: TimeInterval = 3
  static let keyboardSwapWait: TimeInterval = 0.6
  static let smallFrameGrace: TimeInterval = 0.3
  static let instantFrame: TimeInterval = 0.05
  static let handoffDelay: TimeInterval = 0.3
  static let handoffFade: TimeInterval = 0.08
  static let plusFade: TimeInterval = 0.08
  static let plusFadeDelay: TimeInterval = 0.04
  static let skinFade: TimeInterval = 0.1
  static let bodyFade: TimeInterval = 0.1
  static let iconsFadeOut: TimeInterval = 0.2
  static let iconsFadeIn: TimeInterval = 0.15
  static let iconsFadeInDelay: TimeInterval = 0.1
  static let handBackFade: TimeInterval = 0.035
  static let handBackRowsFade: TimeInterval = 0.05
  static let handBackIconsDelay: TimeInterval = 0.02
  static let handBackIconsFade: TimeInterval = 0.06
  static let closeTextFade: TimeInterval = 0.06
  static let closeFade: TimeInterval = 0.08
  static let closeFadeDelay: TimeInterval = 0.36
  static let closeSettle: TimeInterval = 0.45
  static let dimFade: TimeInterval = 0.25
  static let dimClear: TimeInterval = 0.12
  static let defaultKeyboardLift: CGFloat = 336
  static let symbolWarmDelay: TimeInterval = 1.5
  static let pendingLimit: TimeInterval = 0.6
  static let dragIconsFade: TimeInterval = 0.03
  static let dragHandover: TimeInterval = 0.04
  static let dragRowsDelay: TimeInterval = 0.12
  static let dragRowsFade: TimeInterval = 0.03
  static let dragRubber: CGFloat = 0.3
  static let dragReverse: CGFloat = 150
  static let dragReverseDistance: CGFloat = 12
  static let recessionClose: Double = 0.26

  deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }

  override func loadView() {
    let container = PassThroughView()
    container.backgroundColor = .clear
    container.isHidden = true
    view = container
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    SearchMotion.rider = self
    dim.backgroundColor = .clear
    dim.onTap = { [weak self] in self?.onDismiss() }
    view.addSubview(dim)
    view.addSubview(riser)
    addChild(bandHost)
    bandHost.view.backgroundColor = .clear
    bandHost.view.isUserInteractionEnabled = false
    bandHost.view.alpha = 0
    if #available(iOS 16.4, *) { bandHost.safeAreaRegions = [] }
    riser.addSubview(bandHost.view)
    bandHost.didMove(toParent: self)
    addChild(host)
    host.view.backgroundColor = .clear
    if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
    body.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    riser.addSubview(body)
    material.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    body.addSubview(material)
    body.addSubview(host.view)
    host.didMove(toParent: self)
    maskBase.shape.fillRule = .evenOdd
    maskBase.shape.fillColor = UIColor.black.cgColor
    maskHole.backgroundColor = .black
    maskHole.layer.cornerCurve = .continuous
    fieldMask.addSubview(maskBase)
    fieldMask.addSubview(maskHole)
    addChild(iconsHost)
    iconsHost.view.backgroundColor = .clear
    iconsHost.view.isUserInteractionEnabled = false
    iconsHost.view.alpha = 0
    if #available(iOS 16.4, *) { iconsHost.safeAreaRegions = [] }
    riser.addSubview(iconsHost.view)
    iconsHost.didMove(toParent: self)
    morph.alpha = 0
    riser.addSubview(morph)
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.symbolWarmDelay) { [weak self] in
      let size = UIFontMetrics(forTextStyle: .body).scaledValue(for: 17)
      self?.morph.loadSymbols(glyphSize: BrowseLayout.barPlusGlyph, accessorySize: size)
    }
    let center = NotificationCenter.default
    if KeyboardReplay.isActive {
      observers.append(center.addObserver(forName: KeyboardReplay.notification, object: nil, queue: .main) { [weak self] note in
        let info = KeyboardChange(note)
        MainActor.assumeIsolated { self?.keyboardWillChange(info) }
      })
    } else {
      observers.append(center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
        let info = KeyboardChange(note)
        MainActor.assumeIsolated { self?.keyboardWillChange(info) }
      })
      observers.append(center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] note in
        var info = KeyboardChange(note)
        info.hides = true
        MainActor.assumeIsolated { self?.keyboardWillChange(info) }
      })
    }
    observers.append(center.addObserver(forName: UITextField.textDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.handOff() }
    })
    observers.append(center.addObserver(forName: UITextField.textDidBeginEditingNotification, object: nil, queue: .main) { [weak self] note in
      let field = note.object as? UITextField
      MainActor.assumeIsolated {
        guard let self, let field, field.isDescendant(of: self.host.view) else { return }
        self.textField = field
      }
    })
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let bounds = view.bounds
    dim.frame = bounds
    if riser.bounds.size != bounds.size {
      sizeRiser()
      if !view.isHidden, growth != nil { place(top: restingTop()) }
    }
  }

  private func sizeRiser() {
    riser.bounds = CGRect(origin: .zero, size: view.bounds.size)
    body.frame = riser.bounds
    material.frame = body.bounds
    host.view.frame = body.bounds
    bandHost.view.frame = riser.bounds
  }

  private var screenHeight: CGFloat { view.bounds.height }
  private var safeBottom: CGFloat { view.window?.safeAreaInsets.bottom ?? view.safeAreaInsets.bottom }

  private var keyboardLift: CGFloat {
    keyboardOverlap > Self.keyboardThreshold ? keyboardOverlap : max(keyboardOverlap, safeBottom)
  }

  private var expectedLift: CGFloat {
    if keyboardOverlap > Self.keyboardThreshold { return keyboardOverlap }
    let stored = Self.rememberedLift
    return stored > 0 ? max(CGFloat(stored), safeBottom) : Self.defaultKeyboardLift
  }

  private func openTop(lift: CGFloat) -> CGFloat {
    screenHeight - lift - (growth?.panelHeight ?? 0)
  }

  private var closedTop: CGFloat {
    screenHeight - (growth?.bandAboveBottom ?? 0)
  }

  private func restingTop() -> CGFloat {
    guard isVisible else { return closedTop }
    return openTop(lift: currentLift) + dragOffset
  }

  private var currentLift: CGFloat {
    if holdsLift, let heldLift { return heldLift }
    return awaitingKeyboard ? openTarget : keyboardLift
  }

  private func place(top: CGFloat) {
    riser.center = CGPoint(x: view.bounds.width / 2, y: top + riser.bounds.height / 2)
  }

  private var fieldWidth: CGFloat {
    view.bounds.width - (growth?.fieldInset ?? 0) * 2
  }

  private var fieldRect: CGRect {
    guard let growth else { return .zero }
    return CGRect(x: growth.fieldInset, y: growth.fieldTop, width: fieldWidth, height: growth.fieldHeight)
  }

  private var capsuleRect: CGRect {
    guard let growth else { return .zero }
    let line = growth.bandAboveBottom - growth.lineAboveBottom
    return CGRect(
      x: (view.bounds.width - growth.capsule.width) / 2,
      y: line - growth.capsule.height / 2,
      width: growth.capsule.width,
      height: growth.capsule.height
    )
  }

  func setIcons(_ icons: AnyView) {
    iconsHost.rootView = icons
  }

  func setBand(_ band: AnyView) {
    bandHost.rootView = band
  }

  func update(content: AnyView, holdsLift: Bool, dragOffset: CGFloat, isVisible visible: Bool, isInteractive: Bool, growth: RiderGrowth, animatesDrag: Bool) {
    host.rootView = content
    if self.growth != growth { material.configure(growth) }
    self.growth = growth
    let iconsFrame = CGRect(x: 0, y: 0, width: view.bounds.width, height: growth.bandAboveBottom)
    if iconsHost.view.frame != iconsFrame { iconsHost.view.frame = iconsFrame }
    requestedVisible = visible
    if let pendingVisibility, pendingVisibility == visible { self.pendingVisibility = nil }
    let visible = pendingVisibility ?? visible
    if isInteractive != self.isInteractive || host.view.isUserInteractionEnabled != isInteractive {
      self.isInteractive = isInteractive
      host.view.isUserInteractionEnabled = isInteractive
      dim.isUserInteractionEnabled = isInteractive
    }

    if isDraggingOpen {
      if visible != isVisible { HarnessProbe.mark("rider.visibleWhileDragging", "\(visible)") }
      return
    }
    if visible != isVisible {
      self.holdsLift = holdsLift
      heldLift = holdsLift ? currentLift : nil
      self.dragOffset = visible ? dragOffset : self.dragOffset
      visible ? open() : close()
      return
    }
    guard visible else { return }

    var moves = false
    if holdsLift != self.holdsLift {
      heldLift = holdsLift ? currentLift : nil
      self.holdsLift = holdsLift
      moves = !holdsLift
    }
    if dragOffset != self.dragOffset {
      self.dragOffset = dragOffset
      if !moves, !animatesDrag {
        UIView.performWithoutAnimation { place(top: restingTop()) }
        return
      }
      moves = true
    }
    if moves { spring(response: BrowseLayout.searchOpenResponse) { self.place(top: self.restingTop()) } }
  }

  func prime(initialText: String, dims: Bool) {
    guard !isVisible, view.window != nil, var growth else { return }
    growth.initialText = initialText
    growth.dim = dims ? CGFloat(BrowseLayout.trayDim) : 0
    self.growth = growth
    holdsLift = false
    heldLift = nil
    dragOffset = 0
    HarnessProbe.mark("search.primed")
    hold(visible: true)
    open()
    CATransaction.flush()
  }

  func end() {
    guard isVisible, growth?.handsBackToBar == true else { return }
    HarnessProbe.mark("search.ended")
    hold(visible: false)
    close()
    CATransaction.flush()
  }

  private func hold(visible: Bool) {
    pendingVisibility = visible
    pendingGeneration += 1
    let holding = pendingGeneration
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.pendingLimit) { [weak self] in
      guard let self, self.pendingGeneration == holding, self.pendingVisibility != nil else { return }
      self.pendingVisibility = nil
      guard self.requestedVisible != self.isVisible else { return }
      self.requestedVisible ? self.open() : self.close()
    }
  }

  private func hideField() {
    guard growth != nil else { return }
    let bounds = host.view.bounds
    let hole = fieldRect.insetBy(dx: -1.5, dy: -1.5)
    UIView.performWithoutAnimation {
      fieldMask.frame = bounds
      maskBase.frame = bounds
      let path = UIBezierPath(rect: bounds)
      path.append(UIBezierPath(roundedRect: hole, cornerRadius: hole.height / 2))
      maskBase.shape.path = path.cgPath
      maskHole.layer.removeAllAnimations()
      maskHole.frame = hole
      maskHole.layer.cornerRadius = hole.height / 2
      maskHole.alpha = 0
    }
    if host.view.mask !== fieldMask { host.view.mask = fieldMask }
  }

  private func showField() {
    host.view.mask = nil
  }

  private func open() {
    guard let growth else { return }
    HarnessProbe.follow(riser, as: "rider")
    HarnessProbe.follow(morph, as: "morph")
    generation += 1
    isVisible = true
    let fromDrag = opensFromDrag && !view.isHidden
    opensFromDrag = false
    let reopening = !view.isHidden && !fromDrag
    view.isHidden = false
    UIView.performWithoutAnimation {
      view.layoutIfNeeded()
      if riser.bounds.size != view.bounds.size { sizeRiser() }
      host.view.layoutIfNeeded()
    }
    awaitingKeyboard = keyboardOverlap <= Self.keyboardThreshold && !holdsLift
    openTarget = expectedLift
    let target = openTop(lift: currentLift) + dragOffset
    let field = fieldRect
    let launch = launchVelocity
    launchVelocity = 0
    if reopening {
      UIView.animate(withDuration: Self.bodyFade, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
        self.bandHost.view.alpha = 0
        self.material.alpha = 1
        self.host.view.alpha = 1
      }
    } else if fromDrag {
      UIView.animate(withDuration: Self.dragHandover, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
        self.bandHost.view.alpha = 0
        self.material.alpha = 1
      }
      later(Self.dragRowsDelay, over: Self.dragRowsFade) {
        self.host.view.alpha = 1
      }
    } else {
      bandHost.view.layer.removeAllAnimations()
      bandHost.view.alpha = 0
      material.layer.removeAllAnimations()
      material.alpha = 1
      host.view.layer.removeAllAnimations()
      host.view.alpha = 1
    }

    if UIAccessibility.isReduceMotionEnabled {
      iconsHost.view.alpha = 0
      morph.alpha = 0
      isMorphing = false
      showField()
      UIView.performWithoutAnimation { place(top: target) }
      if !reopening { body.alpha = 0 }
      UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
        self.body.alpha = 1
        self.dim.backgroundColor = UIColor.black.withAlphaComponent(growth.dim)
      }
      scheduleKeyboardWait(Self.keyboardWait)
      return
    }

    if fromDrag {
      UIView.performWithoutAnimation {
        morph.configure(growth, text: growth.initialText, showsCaret: true)
        morph.setText(visible: true)
      }
    } else if !reopening {
      UIView.performWithoutAnimation {
        body.alpha = 0
        place(top: closedTop)
        iconsHost.view.alpha = 1
        morph.frame = capsuleRect
        morph.configure(growth, text: growth.initialText, showsCaret: true)
        morph.pose(open: false, growth: growth, fieldWidth: field.width)
        morph.setPlus(visible: true)
        morph.setTile(visible: true)
        morph.setSkin(visible: false)
        morph.setText(visible: true)
      }
    } else {
      morph.configure(growth, text: currentFieldText(), showsCaret: true)
      morph.setText(visible: true)
    }
    hideField()
    morph.alpha = 1
    isMorphing = true
    UIView.animate(withDuration: Self.bodyFade, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
      self.body.alpha = 1
    }
    if growth.handsBackToBar, !reopening, !fromDrag {
      UIView.performWithoutAnimation { bandHost.view.alpha = 1 }
      UIView.animate(withDuration: Self.bodyFade, delay: 0, options: [.beginFromCurrentState, .curveEaseIn]) {
        self.bandHost.view.alpha = 0
      }
    }

    let presentedTop = (riser.layer.presentation() ?? riser.layer).frame.minY
    let distance = target - presentedTop
    spring(response: BrowseLayout.searchOpenResponse, velocity: abs(distance) > 1 ? launch / distance : 0) {
      self.place(top: target)
    }
    if growth.dim > 0 {
      PageRecession.shared.animate(to: 1, velocity: launch < 0 ? min(-launch / PageRecession.dragReach, 8) : 0)
    }
    spring(response: BrowseLayout.searchWidenResponse) {
      self.morph.frame = field
      self.morph.pose(open: true, growth: growth, fieldWidth: field.width)
    }
    UIView.animate(withDuration: Self.skinFade, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
      self.morph.setSkin(visible: true)
      self.morph.setTile(visible: false)
    }
    later(Self.plusFadeDelay, over: Self.plusFade) {
      self.morph.setPlus(visible: false)
    }
    UIView.animate(withDuration: Self.iconsFadeOut, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
      self.iconsHost.view.alpha = 0
    }
    UIView.animate(withDuration: Self.dimFade, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
      self.dim.backgroundColor = UIColor.black.withAlphaComponent(growth.dim)
    }
    let opened = generation
    later(Self.handoffDelay, over: Self.handoffFade, {
      self.morph.alpha = 0
      self.maskHole.alpha = 1
    }, completion: { [weak self] in
      guard let self, self.generation == opened, self.isVisible else { return }
      self.isMorphing = false
      self.showField()
    })
    scheduleKeyboardWait(Self.keyboardWait)
  }

  private func scheduleKeyboardWait(_ wait: TimeInterval) {
    guard awaitingKeyboard else { return }
    waitGeneration += 1
    let waiting = waitGeneration
    let opened = generation
    DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
      guard let self, self.generation == opened, self.waitGeneration == waiting, self.isVisible, self.awaitingKeyboard else { return }
      self.awaitingKeyboard = false
      if self.keyboardOverlap > 0 { self.settledLift = self.keyboardLift }
      guard !self.holdsLift else { return }
      self.spring(response: BrowseLayout.searchOpenResponse) { self.place(top: self.restingTop()) }
    }
  }

  private func handOff() {
    guard isMorphing, isVisible else { return }
    isMorphing = false
    let opened = generation
    UIView.animate(withDuration: Self.handoffFade, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
      self.morph.alpha = 0
      self.maskHole.alpha = 1
    } completion: { [weak self] _ in
      guard let self, self.generation == opened, self.isVisible else { return }
      self.showField()
    }
  }

  private func close() {
    guard let growth else { return }
    HarnessProbe.follow(riser, as: "rider")
    HarnessProbe.follow(morph, as: "morph")
    generation += 1
    isVisible = false
    awaitingKeyboard = false
    let closing = generation
    if let settledLift {
      Self.remember(settledLift)
      self.settledLift = nil
    }

    if UIAccessibility.isReduceMotionEnabled {
      PageRecession.shared.set(0)
      UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState]) {
        self.body.alpha = 0
        self.dim.backgroundColor = .clear
        self.morph.alpha = 0
      } completion: { _ in self.finishClose(closing) }
      return
    }

    let field = fieldRect
    let text = currentFieldText()
    let opening = isMorphing
    isMorphing = false
    UIView.performWithoutAnimation {
      if !opening {
        morph.frame = field
        morph.configure(growth, text: text, showsCaret: false)
        morph.pose(open: true, growth: growth, fieldWidth: field.width)
        morph.setPlus(visible: false)
        morph.setSkin(visible: true)
        morph.setTile(visible: false)
      } else {
        morph.configure(growth, text: text, showsCaret: false)
      }
      morph.setText(visible: true)
    }
    morph.layer.removeAnimation(forKey: "opacity")
    morph.alpha = 1
    hideField()

    spring(response: BrowseLayout.searchCloseResponse) {
      self.place(top: self.closedTop)
    }
    if PageRecession.shared.progress > 0 {
      PageRecession.shared.animate(to: 0, response: Self.recessionClose)
    }
    let speed = Double(view.window?.layer.speed ?? 1)
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeSettle / max(speed, 0.01)) { [weak self] in
      self?.finishClose(closing)
    }
    spring(response: BrowseLayout.searchCloseResponse) {
      self.morph.frame = self.capsuleRect
      self.morph.pose(open: false, growth: growth, fieldWidth: field.width)
    }
    UIView.animate(withDuration: Self.closeTextFade, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
      self.morph.setText(visible: false)
    }
    later(Self.plusFadeDelay * 2, over: Self.plusFade) {
      self.morph.setPlus(visible: true)
    }

    guard growth.handsBackToBar else {
      later(Self.iconsFadeInDelay, over: Self.iconsFadeIn) {
        self.iconsHost.view.alpha = 1
      }
      UIView.animate(withDuration: Self.dimFade, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
        self.dim.backgroundColor = .clear
      }
      later(Self.closeFadeDelay, over: Self.closeFade) {
        self.body.alpha = 0
        self.morph.alpha = 0
      }
      return
    }

    UIView.animate(withDuration: Self.handBackFade, delay: 0, options: [.beginFromCurrentState, .curveLinear]) {
      self.material.alpha = 0
      self.bandHost.view.alpha = 1
      self.morph.setSkin(visible: false)
      self.morph.setTile(visible: true)
    }
    UIView.animate(withDuration: Self.handBackRowsFade, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
      self.host.view.alpha = 0
    }
    later(Self.handBackIconsDelay, over: Self.handBackIconsFade) {
      self.iconsHost.view.alpha = 1
    }
    UIView.animate(withDuration: Self.dimClear, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
      self.dim.backgroundColor = .clear
    }
  }

  private func finishClose(_ closing: Int) {
    guard generation == closing, !isVisible else { return }
    view.isHidden = true
    showField()
    iconsHost.view.alpha = 0
    bandHost.view.alpha = 0
    morph.alpha = 0
    material.alpha = 1
    host.view.alpha = 1
    body.alpha = 1
    dragOffset = 0
    heldLift = nil
    onClosed()
  }

  private weak var textField: UITextField?

  private func currentFieldText() -> String {
    func find(_ view: UIView) -> UITextField? {
      if let field = view as? UITextField { return field }
      for subview in view.subviews {
        if let found = find(subview) { return found }
      }
      return nil
    }
    if textField == nil || textField?.isDescendant(of: host.view) != true { textField = find(host.view) }
    return textField?.text ?? growth?.initialText ?? ""
  }

  private func keyboardWillChange(_ change: KeyboardChange) {
    guard let window = view.window else { return }
    let previousLift = currentLift
    var overlap: CGFloat = 0
    if !change.hides, let end = change.end {
      let local = view.convert(end, from: window.screen.coordinateSpace)
      overlap = max(0, view.bounds.maxY - local.minY)
    }
    let arrived = overlap > Self.keyboardThreshold
    keyboardOverlap = overlap
    HarnessProbe.mark("rider.keyboard", "\(Int(overlap)) \(change.hides ? "hide" : "show") \(change.duration)")
    guard isVisible else { return }
    if awaitingKeyboard {
      guard !change.hides else { return }
      guard arrived else {
        scheduleKeyboardWait(Self.smallFrameGrace)
        return
      }
      awaitingKeyboard = false
      settledLift = keyboardLift
      guard !holdsLift else { return }
      spring(response: BrowseLayout.searchOpenResponse) { self.place(top: self.restingTop()) }
      return
    }
    if change.hides, textField?.isFirstResponder == true, !holdsLift {
      awaitingKeyboard = true
      openTarget = previousLift
      scheduleKeyboardWait(Self.keyboardSwapWait)
      return
    }
    if arrived { settledLift = keyboardLift }
    guard !holdsLift else { return }
    if change.duration < Self.instantFrame {
      spring(response: BrowseLayout.searchOpenResponse) { self.place(top: self.restingTop()) }
      return
    }
    let options = UIView.AnimationOptions(rawValue: UInt(change.curve) << 16).union([.beginFromCurrentState, .allowUserInteraction])
    UIView.animate(withDuration: change.duration, delay: 0, options: options) {
      self.place(top: self.restingTop())
    }
  }

  private func later(_ delay: TimeInterval, over duration: TimeInterval, _ animations: @escaping () -> Void, completion: (() -> Void)? = nil) {
    let total = delay + duration
    UIView.animateKeyframes(withDuration: total, delay: 0, options: [.allowUserInteraction, .calculationModeLinear]) {
      UIView.addKeyframe(withRelativeStartTime: delay / total, relativeDuration: duration / total, animations: animations)
    } completion: { _ in
      completion?()
    }
  }

  private static var cachedLift: Double?

  private static var rememberedLift: Double {
    if let cachedLift { return cachedLift }
    let stored = UserDefaults.standard.double(forKey: liftKey)
    cachedLift = stored
    return stored
  }

  private static func remember(_ lift: CGFloat) {
    let value = Double(lift)
    guard rememberedLift != value else { return }
    cachedLift = value
    UserDefaults.standard.set(value, forKey: liftKey)
  }

  private func spring(response: Double, velocity: CGFloat = 0, _ animations: @escaping () -> Void) {
    UIView.animate(springDuration: response, bounce: 0, initialSpringVelocity: velocity, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: animations)
  }

  func drag(_ dy: CGFloat) -> Bool {
    guard view.window != nil, let growth, !UIAccessibility.isReduceMotionEnabled else { return false }
    if !isDraggingOpen {
      guard !isVisible, growth.handsBackToBar else { return false }
      isDraggingOpen = true
      dragPeak = 0
      generation += 1
      view.isHidden = false
      HarnessProbe.follow(riser, as: "rider", for: 4)
      UIView.performWithoutAnimation {
        view.layoutIfNeeded()
        if riser.bounds.size != view.bounds.size { sizeRiser() }
        riser.layer.removeAllAnimations()
        place(top: closedTop)
        body.alpha = 1
        material.alpha = 0
        host.view.alpha = 0
        bandHost.view.alpha = 1
        iconsHost.view.alpha = 1
        dim.backgroundColor = .clear
        morph.layer.removeAllAnimations()
        morph.frame = capsuleRect
        morph.configure(growth, text: "", showsCaret: false)
        morph.pose(open: false, growth: growth, fieldWidth: fieldWidth)
        morph.setPlus(visible: true)
        morph.setTile(visible: true)
        morph.setSkin(visible: false)
        morph.setText(visible: false)
        morph.alpha = 1
      }
      UIView.animate(withDuration: Self.dragIconsFade, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
        self.iconsHost.view.alpha = 0
      }
    }
    dragPeak = min(dragPeak, dy)
    let up = max(-dy, 0)
    let reach = max(closedTop - openTop(lift: expectedLift), 1)
    let travel = up <= reach ? up : reach + (up - reach) * Self.dragRubber
    let share = min(up / PageRecession.dragReach, 1)
    UIView.performWithoutAnimation {
      riser.layer.removeAnimation(forKey: "position")
      place(top: closedTop - travel)
      dim.backgroundColor = UIColor.black.withAlphaComponent(CGFloat(BrowseLayout.trayDim) * share)
    }
    PageRecession.shared.set(share)
    return true
  }

  func dragEnded(_ dy: CGFloat, velocity: CGFloat, commits: Bool) -> Bool? {
    guard isDraggingOpen else { return nil }
    isDraggingOpen = false
    let reversed = velocity > Self.dragReverse && dy > dragPeak + Self.dragReverseDistance
    if commits, !reversed {
      launchVelocity = min(velocity, 0)
      opensFromDrag = true
      return true
    }
    generation += 1
    let cancelling = generation
    let top = (riser.layer.presentation() ?? riser.layer).frame.minY
    let distance = closedTop - top
    spring(response: BrowseLayout.searchCloseResponse, velocity: abs(distance) > 1 ? velocity / distance : 0) {
      self.place(top: self.closedTop)
    }
    PageRecession.shared.animate(to: 0, response: Self.recessionClose, velocity: velocity > 0 ? -min(velocity / PageRecession.dragReach, 8) : 0)
    UIView.animate(withDuration: Self.dimClear, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
      self.dim.backgroundColor = .clear
      self.iconsHost.view.alpha = 1
    }
    let speed = Double(view.window?.layer.speed ?? 1)
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeSettle / max(speed, 0.01)) { [weak self] in
      guard let self, self.generation == cancelling, !self.isVisible, !self.isDraggingOpen else { return }
      self.view.isHidden = true
      self.iconsHost.view.alpha = 0
      self.bandHost.view.alpha = 0
      self.morph.alpha = 0
      self.material.alpha = 1
      self.host.view.alpha = 1
    }
    return false
  }
}

nonisolated private struct KeyboardChange: Sendable {
  var end: CGRect?
  var duration: TimeInterval
  var curve: Int
  var hides = false

  init(_ note: Notification) {
    let info = note.userInfo ?? [:]
    end = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
    duration = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
    curve = (info[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int) ?? 7
    hides = (info[KeyboardReplay.hidesKey] as? Bool) ?? false
  }
}
