import CoreGraphics
import Foundation

public struct TabsDeckGeometry: Equatable, Sendable {
  public static let referenceWidth: CGFloat = 401
  public static let cardWidthRatio: CGFloat = 281.0 / referenceWidth
  public static let focusLeadingRatio: CGFloat = 84.0 / referenceWidth
  public static let stepRatio: CGFloat = 224.0 / referenceWidth
  public static let firstTuckRatio: CGFloat = 13.0 / referenceWidth
  public static let tuckReachRatio: CGFloat = 19.4 / referenceWidth
  public static let tuckFalloff: CGFloat = 1.1
  public static let tuckShrink: CGFloat = 0.03
  public static let tuckShrinkPower: CGFloat = 1.415
  public static let tuckMinimumScale: CGFloat = 0.7
  public static let tuckDim: CGFloat = 0.4
  public static let headerHeight: CGFloat = 20
  public static let headerAboveCard: CGFloat = 28
  public static let headerInset: CGFloat = 18
  public static let barCenterAboveSafeBottom: CGFloat = 28.5
  public static let barCircle: CGFloat = 33.5
  public static let cardClearanceAboveBar: CGFloat = 16
  public static let topReserve: CGFloat = 8
  public static let chromeGap: CGFloat = 21
  public static let headerFaviconOnlyWidth: CGFloat = 72

  public let container: CGSize
  public let safeTop: CGFloat
  public let safeBottom: CGFloat
  public let safeSide: CGFloat
  public let cardSize: CGSize
  public let focusLeading: CGFloat
  public let centeredLeading: CGFloat
  public let spacing: CGFloat
  public let firstTuck: CGFloat
  public let tuckReach: CGFloat
  public let cardCenterY: CGFloat

  public init(container: CGSize, safeTop: CGFloat, safeBottom: CGFloat, safeSide: CGFloat = 0, chromeBottom: CGFloat? = nil, reserveAboveBar: CGFloat = 0) {
    self.container = container
    self.safeTop = safeTop
    self.safeBottom = safeBottom
    self.safeSide = safeSide
    let width = max(container.width, 1)
    let height = max(container.height, 1)
    let barCenter = height - safeBottom - Self.barCenterAboveSafeBottom
    let bandTop = (chromeBottom.map { $0 + Self.chromeGap } ?? safeTop + Self.topReserve) + Self.headerAboveCard
    let bandBottom = barCenter - Self.barCircle / 2 - Self.cardClearanceAboveBar - reserveAboveBar
    let band = max(bandBottom - bandTop, 120)
    let aspect = height / width
    let cardWidth = min(width * Self.cardWidthRatio, band / aspect)
    let cardHeight = cardWidth * aspect
    cardSize = CGSize(width: cardWidth, height: cardHeight)
    focusLeading = width * Self.focusLeadingRatio
    centeredLeading = (width - cardWidth) / 2
    spacing = min(cardWidth, width * Self.stepRatio)
    firstTuck = width * Self.firstTuckRatio
    tuckReach = width * Self.tuckReachRatio
    let lowest = bandTop + cardHeight / 2
    let highest = max(bandBottom - cardHeight / 2, lowest)
    cardCenterY = min(max(height / 2, lowest), highest)
  }

  public static func endBlend(scroll: Double, count: Int) -> CGFloat {
    guard count > 1 else { return 1 }
    let t = CGFloat(min(max(scroll - Double(count - 2), 0), 1))
    return t * t * (3 - 2 * t)
  }

  public func focusLeading(end: CGFloat) -> CGFloat {
    focusLeading + (centeredLeading - focusLeading) * min(max(end, 0), 1)
  }

  public func leading(at relative: Double, end: CGFloat = 0) -> CGFloat {
    let p = CGFloat(relative)
    let focus = focusLeading(end: end)
    if p >= 0 { return focus + spacing * p }
    let tailSlope = tuckReach * Self.tuckFalloff
    if p <= -1 {
      return firstTuck - tuckReach * (1 - exp(Self.tuckFalloff * (p + 1)))
    }
    let secant = focus - firstTuck
    let startSlope = tailSlope
    let endSlope = min(spacing, 3.3 * secant)
    let t = p + 1
    let t2 = t * t
    let t3 = t2 * t
    let h00 = 2 * t3 - 3 * t2 + 1
    let h10 = t3 - 2 * t2 + t
    let h01 = -2 * t3 + 3 * t2
    let h11 = t3 - t2
    return h00 * firstTuck + h10 * startSlope + h01 * focus + h11 * endSlope
  }

  public func scale(at relative: Double) -> CGFloat {
    guard relative < 0 else { return 1 }
    return max(1 - Self.tuckShrink * pow(CGFloat(-relative), Self.tuckShrinkPower), Self.tuckMinimumScale)
  }

  public func dim(at relative: Double) -> CGFloat {
    guard relative < 0 else { return 0 }
    return min(CGFloat(-relative), 1) * Self.tuckDim
  }

  public func center(at relative: Double, end: CGFloat = 0) -> CGPoint {
    CGPoint(x: leading(at: relative, end: end) + cardSize.width * scale(at: relative) / 2, y: cardCenterY)
  }

  public func visibleWidth(at relative: Double, isLast: Bool, end: CGFloat = 0) -> CGFloat {
    let own = cardSize.width * scale(at: relative)
    guard !isLast else { return own }
    return min(own, max(0, leading(at: relative + 1, end: end) - leading(at: relative, end: end)))
  }

  public var expandedScale: CGFloat { container.width / max(cardSize.width, 1) }

  public var expandedCenter: CGPoint { CGPoint(x: container.width / 2, y: container.height / 2) }

  public var barCenterY: CGFloat { container.height - safeBottom - Self.barCenterAboveSafeBottom }

  public var tabButtonCenter: CGPoint {
    CGPoint(x: safeSide + 53.5, y: barCenterY - 4)
  }

  public var tabButtonBackCenter: CGPoint {
    CGPoint(x: safeSide + 38, y: barCenterY + 1.5)
  }

  public func scrollDelta(forDrag translation: CGFloat) -> Double {
    Double(-translation / spacing)
  }

  public static func rubberBand(_ scroll: Double, count: Int) -> Double {
    let upper = Double(max(count - 1, 0))
    if scroll < 0 { return -pow(-scroll, 0.7) * 0.35 }
    if scroll > upper { return upper + pow(scroll - upper, 0.7) * 0.35 }
    return scroll
  }

  public func settleTarget(from scroll: Double, velocity: CGFloat, count: Int) -> Int {
    guard count > 0 else { return 0 }
    let projected = scroll - Double(velocity / spacing) * 0.22
    return min(max(Int(projected.rounded()), 0), count - 1)
  }

  public static func renderedRange(around scroll: Double, count: Int) -> Range<Int> {
    guard count > 0 else { return 0..<0 }
    let anchor = Int(scroll.rounded())
    let lower = max(0, anchor - 6)
    let upper = min(count, anchor + 6)
    return lower < upper ? lower..<upper : 0..<0
  }

  public static func scrollAfterRemoving(index removed: Int, scroll: Int, remaining: Int) -> Int {
    guard remaining > 0 else { return 0 }
    let shifted = removed < scroll ? scroll - 1 : scroll
    return min(max(shifted, 0), remaining - 1)
  }

  public static let closeDistance: CGFloat = 150
  public static let closeProjection: CGFloat = 0.3

  public static func shouldClose(translation: CGFloat, velocity: CGFloat, cardHeight: CGFloat) -> Bool {
    guard translation < 0 else { return false }
    let projected = -translation - velocity * closeProjection
    return projected >= closeDistance
  }
}
