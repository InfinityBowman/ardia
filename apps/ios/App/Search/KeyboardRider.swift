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
  var fieldFill: UIColor
  var fieldEdge: UIColor
  var glyph: UIColor
  var placeholder: UIColor
  var text: UIColor
  var accessory: UIColor
  var accent: UIColor
  var initialText: String
  var showsAccessories: Bool
  var dim: CGFloat
}

struct KeyboardRider<Content: View, Icons: View>: UIViewControllerRepresentable {
  var holdsLift: Bool
  var dragOffset: CGFloat
  var isVisible: Bool
  var isInteractive: Bool
  var growth: RiderGrowth
  var onDismiss: () -> Void
  var onClosed: () -> Void = {}
  let content: Content
  let icons: Icons

  func makeUIViewController(context: Context) -> KeyboardRiderController {
    KeyboardRiderController()
  }

  func updateUIViewController(_ controller: KeyboardRiderController, context: Context) {
    let transaction = context.transaction
    controller.onDismiss = onDismiss
    controller.onClosed = onClosed
    controller.update(
      content: AnyView(content),
      icons: AnyView(icons),
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
    caret.layer.cornerRadius = 1
    label.lineBreakMode = .byClipping
    for view in [skin, label, caret, mic, eyes, plus] { addSubview(view) }
  }

  required init?(coder: NSCoder) { nil }

  private var symbolKey: (CGFloat, CGFloat)?

  func configure(_ growth: RiderGrowth, text: String, showsCaret: Bool) {
    skin.backgroundColor = growth.fieldFill
    skin.layer.borderColor = growth.fieldEdge.cgColor
    skin.layer.borderWidth = 1 / max(traitCollection.displayScale, 1)
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
  }

  func setPlus(visible: Bool) { plus.alpha = visible ? 1 : 0 }
  func setSkin(visible: Bool) { skin.alpha = visible ? 1 : 0 }
}

final class KeyboardRiderController: UIViewController {
  var onDismiss: () -> Void = {}
  var onClosed: () -> Void = {}

  private let host = UIHostingController(rootView: AnyView(EmptyView()))
  private let iconsHost = UIHostingController(rootView: AnyView(EmptyView()))
  private let dim = RiderDimView()
  private let riser = PassThroughView()
  private let body = PassThroughView()
  private let cover = UIView()
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
  private var isMorphing = false
  nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

  static let liftKey = "searchPanel.keyboardLift"
  static let keyboardThreshold: CGFloat = 120
  static let keyboardWait: TimeInterval = 0.45
  static let handoffDelay: TimeInterval = 0.3
  static let handoffFade: TimeInterval = 0.08
  static let plusFade: TimeInterval = 0.08
  static let plusFadeDelay: TimeInterval = 0.04
  static let skinFade: TimeInterval = 0.1
  static let bodyFade: TimeInterval = 0.1
  static let iconsFadeOut: TimeInterval = 0.2
  static let iconsFadeIn: TimeInterval = 0.15
  static let iconsFadeInDelay: TimeInterval = 0.1
  static let closeFade: TimeInterval = 0.08
  static let closeFadeDelay: TimeInterval = 0.36
  static let closeSettle: TimeInterval = 0.45
  static let dimFade: TimeInterval = 0.25
  static let defaultKeyboardLift: CGFloat = 336
  static let symbolWarmDelay: TimeInterval = 1.5

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
    dim.backgroundColor = .clear
    dim.onTap = { [weak self] in self?.onDismiss() }
    view.addSubview(dim)
    view.addSubview(riser)
    addChild(host)
    host.view.backgroundColor = .clear
    if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
    body.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    riser.addSubview(body)
    body.addSubview(host.view)
    host.didMove(toParent: self)
    cover.isUserInteractionEnabled = false
    cover.layer.cornerCurve = .continuous
    cover.alpha = 0
    body.addSubview(cover)
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
    observers.append(center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
      let info = KeyboardChange(note)
      MainActor.assumeIsolated { self?.keyboardWillChange(info) }
    })
    observers.append(center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] note in
      var info = KeyboardChange(note)
      info.hides = true
      MainActor.assumeIsolated { self?.keyboardWillChange(info) }
    })
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
      riser.bounds = CGRect(origin: .zero, size: bounds.size)
      body.frame = riser.bounds
      host.view.frame = body.bounds
      if !view.isHidden, growth != nil { place(top: restingTop()) }
    }
  }

  private var screenHeight: CGFloat { view.bounds.height }
  private var safeBottom: CGFloat { view.window?.safeAreaInsets.bottom ?? view.safeAreaInsets.bottom }

  private var keyboardLift: CGFloat {
    keyboardOverlap > Self.keyboardThreshold ? keyboardOverlap : safeBottom
  }

  private var expectedLift: CGFloat {
    if keyboardOverlap > Self.keyboardThreshold { return keyboardOverlap }
    let stored = Self.rememberedLift ?? UserDefaults.standard.double(forKey: Self.liftKey)
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

  func update(content: AnyView, icons: AnyView, holdsLift: Bool, dragOffset: CGFloat, isVisible visible: Bool, isInteractive: Bool, growth: RiderGrowth, animatesDrag: Bool) {
    host.rootView = content
    iconsHost.rootView = icons
    self.growth = growth
    let iconsFrame = CGRect(x: 0, y: 0, width: view.bounds.width, height: growth.bandAboveBottom)
    if iconsHost.view.frame != iconsFrame { iconsHost.view.frame = iconsFrame }
    if isInteractive != self.isInteractive || host.view.isUserInteractionEnabled != isInteractive {
      self.isInteractive = isInteractive
      host.view.isUserInteractionEnabled = isInteractive
      dim.isUserInteractionEnabled = isInteractive
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

  private func open() {
    guard let growth else { return }
    generation += 1
    isVisible = true
    let reopening = !view.isHidden
    view.isHidden = false
    UIView.performWithoutAnimation {
      view.layoutIfNeeded()
      if riser.bounds.size != view.bounds.size {
        riser.bounds = CGRect(origin: .zero, size: view.bounds.size)
        body.frame = riser.bounds
        host.view.frame = body.bounds
      }
      host.view.layoutIfNeeded()
    }
    awaitingKeyboard = keyboardOverlap <= Self.keyboardThreshold && !holdsLift
    openTarget = expectedLift
    let target = openTop(lift: currentLift) + dragOffset
    let field = fieldRect
    cover.frame = field.insetBy(dx: -1.5, dy: -1.5)
    cover.layer.cornerRadius = cover.bounds.height / 2
    cover.backgroundColor = growth.panelFill

    if UIAccessibility.isReduceMotionEnabled {
      iconsHost.view.alpha = 0
      cover.alpha = 0
      morph.alpha = 0
      isMorphing = false
      UIView.performWithoutAnimation { place(top: target) }
      if !reopening { body.alpha = 0 }
      UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
        self.body.alpha = 1
        self.dim.backgroundColor = UIColor.black.withAlphaComponent(growth.dim)
      }
      scheduleKeyboardWait()
      return
    }

    if !reopening {
      UIView.performWithoutAnimation {
        body.alpha = 0
        place(top: closedTop)
        iconsHost.view.alpha = 1
        morph.frame = capsuleRect
        morph.configure(growth, text: growth.initialText, showsCaret: true)
        morph.pose(open: false, growth: growth, fieldWidth: field.width)
        morph.setPlus(visible: true)
        morph.setSkin(visible: false)
      }
    } else {
      morph.configure(growth, text: currentFieldText(), showsCaret: true)
    }
    cover.alpha = 1
    morph.alpha = 1
    isMorphing = true
    UIView.animate(withDuration: Self.bodyFade, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
      self.body.alpha = 1
    }

    spring(response: BrowseLayout.searchOpenResponse) {
      self.place(top: target)
    }
    spring(response: BrowseLayout.searchWidenResponse) {
      self.morph.frame = field
      self.morph.pose(open: true, growth: growth, fieldWidth: field.width)
    }
    UIView.animate(withDuration: Self.skinFade, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
      self.morph.setSkin(visible: true)
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
      self.cover.alpha = 0
    }, completion: { [weak self] in
      guard let self, self.generation == opened else { return }
      self.isMorphing = false
    })
    scheduleKeyboardWait()
  }

  private func scheduleKeyboardWait() {
    guard awaitingKeyboard else { return }
    let opened = generation
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.keyboardWait) { [weak self] in
      guard let self, self.generation == opened, self.isVisible, self.awaitingKeyboard else { return }
      self.awaitingKeyboard = false
      self.rememberLift()
      guard !self.holdsLift else { return }
      self.spring(response: BrowseLayout.searchOpenResponse) { self.place(top: self.restingTop()) }
    }
  }

  private func handOff() {
    guard isMorphing, isVisible else { return }
    isMorphing = false
    UIView.animate(withDuration: Self.handoffFade, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
      self.morph.alpha = 0
      self.cover.alpha = 0
    }
  }

  private func close() {
    guard let growth else { return }
    generation += 1
    isVisible = false
    awaitingKeyboard = false
    let closing = generation

    if UIAccessibility.isReduceMotionEnabled {
      UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState]) {
        self.body.alpha = 0
        self.dim.backgroundColor = .clear
        self.morph.alpha = 0
        self.cover.alpha = 0
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
      } else {
        morph.configure(growth, text: text, showsCaret: false)
      }
    }
    morph.layer.removeAnimation(forKey: "opacity")
    cover.layer.removeAnimation(forKey: "opacity")
    morph.alpha = 1
    cover.alpha = 1

    spring(response: BrowseLayout.searchCloseResponse) {
      self.place(top: self.closedTop)
    }
    let speed = Double(view.window?.layer.speed ?? 1)
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeSettle / max(speed, 0.01)) { [weak self] in
      self?.finishClose(closing)
    }
    spring(response: BrowseLayout.searchCloseResponse) {
      self.morph.frame = self.capsuleRect
      self.morph.pose(open: false, growth: growth, fieldWidth: field.width)
    }
    later(Self.plusFadeDelay * 2, over: Self.plusFade) {
      self.morph.setPlus(visible: true)
    }
    later(Self.iconsFadeInDelay, over: Self.iconsFadeIn) {
      self.iconsHost.view.alpha = 1
    }
    UIView.animate(withDuration: Self.dimFade, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
      self.dim.backgroundColor = .clear
    }
    later(Self.closeFadeDelay, over: Self.closeFade) {
      self.body.alpha = 0
      self.cover.alpha = 0
      self.morph.alpha = 0
    }
  }

  private func finishClose(_ closing: Int) {
    guard generation == closing, !isVisible else { return }
    view.isHidden = true
    iconsHost.view.alpha = 0
    morph.alpha = 0
    cover.alpha = 0
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
    var overlap: CGFloat = 0
    if !change.hides, let end = change.end {
      let local = view.convert(end, from: window.screen.coordinateSpace)
      overlap = max(0, view.bounds.maxY - local.minY)
    }
    keyboardOverlap = overlap
    guard isVisible else { return }
    if overlap > Self.keyboardThreshold || awaitingKeyboard { rememberLift() }
    if awaitingKeyboard {
      guard overlap > Self.keyboardThreshold || change.hides == false else { return }
      awaitingKeyboard = false
      guard !holdsLift else { return }
      spring(response: BrowseLayout.searchOpenResponse) { self.place(top: self.restingTop()) }
      return
    }
    guard !holdsLift else { return }
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

  private func rememberLift() {
    let lift = Double(keyboardLift)
    guard Self.rememberedLift != lift else { return }
    Self.rememberedLift = lift
    UserDefaults.standard.set(lift, forKey: Self.liftKey)
  }

  private static var rememberedLift: Double?

  private func spring(response: Double, _ animations: @escaping () -> Void) {
    UIView.animate(springDuration: response, bounce: 0, initialSpringVelocity: 0, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: animations)
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
  }
}
