import QuartzCore
import UIKit

@MainActor
final class PageRecession {
  static let shared = PageRecession()
  static let scale: CGFloat = 0.952
  static let radius: CGFloat = 24
  static let response: Double = 0.25
  static let dragReach: CGFloat = 160

  private weak var page: UIView?
  private let mask = CALayer()
  private(set) var progress: CGFloat = 0
  private var generation = 0

  private init() {
    mask.backgroundColor = UIColor.black.cgColor
    mask.cornerCurve = .continuous
  }

  func adopt(_ view: UIView) {
    guard page !== view else { return }
    if let page, progress > 0 { clear(page) }
    page = view
    progress = 0
  }

  func set(_ value: CGFloat) {
    guard let page, page.window != nil else { return }
    generation += 1
    progress = min(max(value, 0), 1)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    removeAnimations(from: page)
    apply(progress, to: page)
    CATransaction.commit()
  }

  func animate(to value: CGFloat, response: Double = PageRecession.response, velocity: CGFloat = 0) {
    guard let page, page.window != nil else { return }
    let target = min(max(value, 0), 1)
    let from = presented(page)
    generation += 1
    let animating = generation
    progress = target
    if page.layer.mask !== mask {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      apply(from.progress, to: page)
      CATransaction.commit()
    }
    let geometry = Self.geometry(target, in: page)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    CATransaction.setCompletionBlock { [weak self, weak page] in
      MainActor.assumeIsolated {
        guard let self, let page, self.generation == animating, self.progress == 0 else { return }
        self.clear(page)
      }
    }
    let spring = { (keyPath: String, fromValue: Any, toValue: Any) -> CASpringAnimation in
      let animation = CASpringAnimation(perceptualDuration: response, bounce: 0)
      animation.keyPath = keyPath
      animation.fromValue = fromValue
      animation.toValue = toValue
      animation.initialVelocity = velocity
      animation.duration = animation.settlingDuration
      animation.fillMode = .backwards
      return animation
    }
    page.layer.add(spring("sublayerTransform", NSValue(caTransform3D: from.transform), NSValue(caTransform3D: geometry.transform)), forKey: "recession.transform")
    mask.add(spring("bounds", NSValue(cgRect: from.bounds), NSValue(cgRect: CGRect(origin: .zero, size: geometry.card.size))), forKey: "recession.bounds")
    mask.add(spring("position", NSValue(cgPoint: from.position), NSValue(cgPoint: CGPoint(x: geometry.card.midX, y: geometry.card.midY))), forKey: "recession.position")
    mask.add(spring("cornerRadius", from.radius, geometry.radius), forKey: "recession.radius")
    apply(target, to: page, keepingMask: true)
    CATransaction.commit()
  }

  private struct Presented {
    var progress: CGFloat
    var transform: CATransform3D
    var bounds: CGRect
    var position: CGPoint
    var radius: CGFloat
  }

  private func presented(_ page: UIView) -> Presented {
    let layer = page.layer.presentation() ?? page.layer
    let shape = page.layer.mask === mask ? (mask.presentation() ?? mask) : nil
    let rest = Self.geometry(0, in: page)
    let scale = layer.sublayerTransform.m11
    let current = (1 - scale) / (1 - Self.scale)
    return Presented(
      progress: min(max(current, 0), 1),
      transform: layer.sublayerTransform,
      bounds: shape?.bounds ?? CGRect(origin: .zero, size: rest.card.size),
      position: shape?.position ?? CGPoint(x: rest.card.midX, y: rest.card.midY),
      radius: shape?.cornerRadius ?? 0
    )
  }

  private func apply(_ value: CGFloat, to page: UIView, keepingMask: Bool = false) {
    let geometry = Self.geometry(value, in: page)
    page.layer.sublayerTransform = geometry.transform
    mask.bounds = CGRect(origin: .zero, size: geometry.card.size)
    mask.position = CGPoint(x: geometry.card.midX, y: geometry.card.midY)
    mask.cornerRadius = geometry.radius
    if value > 0 || keepingMask {
      if page.layer.mask !== mask { page.layer.mask = mask }
    } else {
      clear(page)
    }
  }

  private func removeAnimations(from page: UIView) {
    for key in ["recession.transform"] { page.layer.removeAnimation(forKey: key) }
    for key in ["recession.bounds", "recession.position", "recession.radius"] { mask.removeAnimation(forKey: key) }
  }

  private func clear(_ page: UIView) {
    removeAnimations(from: page)
    page.layer.sublayerTransform = CATransform3DIdentity
    if page.layer.mask === mask { page.layer.mask = nil }
  }

  private static func geometry(_ value: CGFloat, in page: UIView) -> (transform: CATransform3D, card: CGRect, radius: CGFloat) {
    let bounds = page.bounds
    let top = page.window.map { page.convert(CGPoint(x: 0, y: $0.safeAreaInsets.top), from: $0).y } ?? 0
    let scale = 1 - (1 - Self.scale) * value
    let pivot = top - bounds.midY
    let transform = CATransform3DConcat(
      CATransform3DConcat(CATransform3DMakeTranslation(0, -pivot, 0), CATransform3DMakeScale(scale, scale, 1)),
      CATransform3DMakeTranslation(0, pivot, 0)
    )
    let width = bounds.width * scale
    let card = CGRect(x: bounds.midX - width / 2, y: top, width: width, height: (bounds.maxY - top) * scale)
    return (transform, card, Self.radius * value)
  }
}
