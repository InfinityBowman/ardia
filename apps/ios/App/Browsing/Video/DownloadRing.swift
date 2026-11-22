import ArdiaBrowser
import ArdiaDesign
import QuartzCore
import SwiftUI
import UIKit

@MainActor
final class DownloadRingCenter {
  enum Phase: Equatable {
    case idle
    case indeterminate
    case progress(Double)
    case done
  }

  static let tickInterval: TimeInterval = 0.1
  static let doneHold: Duration = .milliseconds(1100)
  static let minimumStep = 0.004

  weak var manager: DownloadManager?
  weak var activity: DownloadActivity?
  private(set) var phase: Phase = .idle
  private let views = NSHashTable<DownloadRingView>.weakObjects()
  private var timer: Timer?
  private var doneHold: Task<Void, Never>?
  private var expectation: Task<Void, Never>?

  var isShowing: Bool { phase != .idle }

  func attach(_ view: DownloadRingView) {
    views.add(view)
    view.apply(phase, animated: false)
  }

  static let holdWindow: Duration = .milliseconds(1500)
  private var heldAt: ContinuousClock.Instant?

  func held() -> Bool {
    guard isShowing else { return false }
    heldAt = .now
    HarnessProbe.mark("ring.hold")
    return true
  }

  func takeHold() -> Bool {
    guard let heldAt else { return false }
    self.heldAt = nil
    return ContinuousClock.now - heldAt < Self.holdWindow
  }

  func refresh() {
    if isBusy {
      doneHold?.cancel()
      doneHold = nil
      startTicking()
      tick()
    } else {
      stopTicking()
      DispatchQueue.main.async { [weak self] in self?.settleIfIdle() }
    }
  }

  func expectDownload() {
    expectation?.cancel()
    expectation = Task { [weak self] in
      try? await Task.sleep(for: DownloadActivity.pendingTimeout)
      guard !Task.isCancelled, let self else { return }
      self.expectation = nil
      self.refresh()
    }
    refresh()
  }

  func expectationSettled() {
    expectation?.cancel()
    expectation = nil
    refresh()
  }

  func finishedLast() {
    guard !isBusy else { return }
    stopTicking()
    set(.done)
    HarnessProbe.mark("ring.done")
    doneHold?.cancel()
    doneHold = Task { [weak self] in
      try? await Task.sleep(for: Self.doneHold)
      guard !Task.isCancelled, let self, !self.isBusy else { return }
      self.doneHold = nil
      self.set(.idle)
    }
  }

  private var isBusy: Bool {
    expectation != nil || (manager?.hasRunningTransfers ?? false) || (activity?.isPending ?? false)
  }

  private func settleIfIdle() {
    guard !isBusy, doneHold == nil, phase != .idle else { return }
    set(.idle)
  }

  private func startTicking() {
    guard timer == nil else { return }
    let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    timer.tolerance = Self.tickInterval / 5
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  private func stopTicking() {
    timer?.invalidate()
    timer = nil
  }

  private func tick() {
    guard let manager else { return }
    let summary = manager.summary
    let next: Phase = summary.count == 0 ? .indeterminate : summary.fraction.map(Phase.progress) ?? .indeterminate
    if case .progress(let old) = phase, case .progress(let new) = next, abs(new - old) < Self.minimumStep { return }
    set(next)
  }

  private func set(_ next: Phase) {
    guard next != phase else { return }
    let previous = phase
    phase = next
    if previous == .idle { HarnessProbe.mark("ring.show") }
    if next == .idle { HarnessProbe.mark("ring.clear") }
    for view in views.allObjects { view.apply(next, animated: true) }
  }
}

final class DownloadRingView: UIView {
  static let lineWidth: CGFloat = 2.5
  static let gap: CGFloat = 1
  static let spinDuration: CFTimeInterval = 0.9
  static let step: CFTimeInterval = DownloadRingCenter.tickInterval * 1.2
  static let fade: CFTimeInterval = 0.18

  var circleDiameter: CGFloat = BrowseLayout.barCircle {
    didSet { if circleDiameter != oldValue { setNeedsLayout() } }
  }

  private var layersBuilt = false
  private let track = CAShapeLayer()
  private let arc = CAShapeLayer()
  private let check = CALayer()
  private let checkFill = CAShapeLayer()
  private let checkMark = CAShapeLayer()
  private var phase: DownloadRingCenter.Phase = .idle
  private var glyph = UIColor.label.cgColor
  private var success = UIColor.systemGreen.cgColor

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    isAccessibilityElement = false
    accessibilityElementsHidden = true
    isHidden = true
    layer.opacity = 0
  }

  required init?(coder: NSCoder) { nil }

  func setColors(glyph: CGColor, success: CGColor) {
    guard glyph != self.glyph || success != self.success else { return }
    self.glyph = glyph
    self.success = success
    guard layersBuilt else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    paint()
    CATransaction.commit()
  }

  private func buildLayers() {
    guard !layersBuilt else { return }
    layersBuilt = true
    for shape in [track, arc] {
      shape.fillColor = nil
      shape.lineWidth = Self.lineWidth
      shape.lineCap = .round
      layer.addSublayer(shape)
    }
    arc.strokeEnd = 0
    checkFill.fillColor = success
    checkMark.fillColor = nil
    checkMark.strokeColor = UIColor.white.cgColor
    checkMark.lineWidth = 2.5
    checkMark.lineCap = .round
    checkMark.lineJoin = .round
    check.addSublayer(checkFill)
    check.addSublayer(checkMark)
    check.opacity = 0
    layer.addSublayer(check)
    paint()
    setNeedsLayout()
  }

  private func paint() {
    track.strokeColor = glyph.copy(alpha: glyph.alpha * 0.18)
    arc.strokeColor = glyph
    checkFill.fillColor = success
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard layersBuilt else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    let radius = circleDiameter / 2 + Self.gap + Self.lineWidth / 2
    let ring = UIBezierPath(arcCenter: .zero, radius: radius, startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true).cgPath
    for shape in [track, arc] {
      shape.bounds = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
      shape.position = center
      shape.path = ring
    }
    let side = circleDiameter
    check.frame = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    checkFill.frame = check.bounds
    checkFill.path = UIBezierPath(ovalIn: check.bounds).cgPath
    checkMark.frame = check.bounds
    let mark = UIBezierPath()
    mark.move(to: CGPoint(x: side * 0.30, y: side * 0.52))
    mark.addLine(to: CGPoint(x: side * 0.44, y: side * 0.66))
    mark.addLine(to: CGPoint(x: side * 0.71, y: side * 0.37))
    checkMark.path = mark.cgPath
    CATransaction.commit()
  }

  func apply(_ next: DownloadRingCenter.Phase, animated: Bool) {
    let previous = phase
    phase = next
    if next == .idle, !layersBuilt { return }
    buildLayers()
    let reduceMotion = UIAccessibility.isReduceMotionEnabled
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    switch next {
    case .idle:
      fade(layer, to: 0, animated: animated) { [weak self] in
        guard let self, self.phase == .idle else { return }
        self.isHidden = true
        self.stopSpinning()
        self.arc.strokeEnd = 0
        self.check.opacity = 0
      }
    case .indeterminate:
      reveal(animated: animated && previous == .idle)
      fade(check, to: 0, animated: animated)
      arc.removeAnimation(forKey: "strokeEnd")
      arc.strokeStart = 0
      arc.strokeEnd = 0.28
      if reduceMotion { pulse() } else { spin() }
    case .progress(let fraction):
      reveal(animated: animated && previous == .idle)
      fade(check, to: 0, animated: animated)
      stopSpinning()
      move(to: CGFloat(min(max(fraction, 0), 1)), from: previous, animated: animated)
    case .done:
      reveal(animated: false)
      stopSpinning()
      move(to: 1, from: previous, animated: animated)
      fade(check, to: 1, animated: animated)
    }
    CATransaction.commit()
  }

  private func reveal(animated: Bool) {
    isHidden = false
    if layer.opacity < 1 || layer.animation(forKey: "opacity") != nil { fade(layer, to: 1, animated: animated) }
  }

  private func move(to end: CGFloat, from previous: DownloadRingCenter.Phase, animated: Bool) {
    let start: CGFloat
    if case .progress = previous {
      start = (arc.presentation()?.strokeEnd ?? arc.strokeEnd)
    } else if previous == .done {
      start = arc.strokeEnd
    } else {
      start = 0
    }
    arc.strokeStart = 0
    arc.strokeEnd = end
    guard animated, abs(end - start) > 0.001 else {
      arc.removeAnimation(forKey: "strokeEnd")
      return
    }
    let animation = CABasicAnimation(keyPath: "strokeEnd")
    animation.fromValue = start
    animation.toValue = end
    animation.duration = Self.step
    animation.timingFunction = CAMediaTimingFunction(name: .linear)
    arc.add(animation, forKey: "strokeEnd")
  }

  private func spin() {
    arc.removeAnimation(forKey: "pulse")
    arc.opacity = 1
    guard arc.animation(forKey: "spin") == nil else { return }
    let animation = CABasicAnimation(keyPath: "transform.rotation.z")
    animation.fromValue = 0
    animation.toValue = 2 * Double.pi
    animation.duration = Self.spinDuration
    animation.repeatCount = .infinity
    animation.isRemovedOnCompletion = false
    arc.add(animation, forKey: "spin")
  }

  private func pulse() {
    guard arc.animation(forKey: "pulse") == nil else { return }
    let animation = CABasicAnimation(keyPath: "opacity")
    animation.fromValue = 1
    animation.toValue = 0.35
    animation.duration = 0.8
    animation.autoreverses = true
    animation.repeatCount = .infinity
    arc.add(animation, forKey: "pulse")
  }

  private func stopSpinning() {
    arc.removeAnimation(forKey: "spin")
    arc.removeAnimation(forKey: "pulse")
    arc.opacity = 1
  }

  private func fade(_ target: CALayer, to opacity: Float, animated: Bool, completion: (() -> Void)? = nil) {
    let from = target.presentation()?.opacity ?? target.opacity
    target.opacity = opacity
    guard animated, from != opacity else {
      target.removeAnimation(forKey: "opacity")
      completion?()
      return
    }
    CATransaction.begin()
    CATransaction.setCompletionBlock(completion)
    let animation = CABasicAnimation(keyPath: "opacity")
    animation.fromValue = from
    animation.toValue = opacity
    animation.duration = Self.fade
    animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
    target.add(animation, forKey: "opacity")
    CATransaction.commit()
  }
}

struct DownloadRingOverlay: UIViewRepresentable {
  let center: DownloadRingCenter
  var diameter: CGFloat = BrowseLayout.barCircle

  func makeUIView(context: Context) -> DownloadRingView {
    let view = DownloadRingView()
    center.attach(view)
    return view
  }

  func updateUIView(_ view: DownloadRingView, context: Context) {
    view.circleDiameter = diameter
    view.setColors(
      glyph: BrowsePalette.barGlyph.resolve(in: context.environment).cgColor,
      success: Palette.success.resolve(in: context.environment).cgColor
    )
  }
}
