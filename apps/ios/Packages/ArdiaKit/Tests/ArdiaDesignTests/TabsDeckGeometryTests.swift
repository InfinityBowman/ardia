import ArdiaDesign
import CoreGraphics
import Testing

struct TabsDeckGeometryTests {
  let geometry = TabsDeckGeometry(container: CGSize(width: 393, height: 852), safeTop: 59, safeBottom: 34)

  @Test func `resting deck matches Arc's measured slots`() {
    let arc = TabsDeckGeometry(container: CGSize(width: 401, height: 878), safeTop: 0, safeBottom: 0)
    #expect(abs(arc.cardSize.width - 281) < 0.5)
    #expect(abs(arc.leading(at: 0) - 84) < 0.5)
    #expect(abs(arc.leading(at: 1) - 308) < 0.5)
    #expect(abs(arc.leading(at: -1) - 13) < 0.5)
    #expect(abs(arc.leading(at: -2) - 0) < 1)
    #expect(abs(arc.scale(at: -1) - 0.97) < 0.005)
    #expect(abs(arc.scale(at: -2) - 0.92) < 0.005)
    #expect(abs(arc.cardCenterY - 439) < 0.5)
    #expect(abs(arc.barCenterY - 849.5) < 0.5)
  }

  @Test func `the newest card is centred at the end of the deck`() {
    let arc = TabsDeckGeometry(container: CGSize(width: 401, height: 878), safeTop: 0, safeBottom: 0)
    let end = TabsDeckGeometry.endBlend(scroll: 4, count: 5)
    #expect(end == 1)
    #expect(abs(arc.leading(at: 0, end: end) - 60) < 0.5)
    #expect(abs(arc.leading(at: -1, end: end) - 13) < 0.5)
    #expect(TabsDeckGeometry.endBlend(scroll: 3, count: 5) == 0)
    #expect(TabsDeckGeometry.endBlend(scroll: 0, count: 1) == 1)
  }

  @Test func `the bar sits above the home indicator`() {
    let phone = TabsDeckGeometry(container: CGSize(width: 402, height: 874), safeTop: 62, safeBottom: 34)
    #expect(abs(phone.barCenterY - 811.5) < 0.5)
    #expect(phone.cardCenterY + phone.cardSize.height / 2 < phone.barCenterY - TabsDeckGeometry.barCircle / 2)
    #expect(phone.cardCenterY - phone.cardSize.height / 2 - TabsDeckGeometry.headerAboveCard >= phone.safeTop)
  }

  @Test func `the archive card above the bar lifts the cards`() {
    let bare = TabsDeckGeometry(container: CGSize(width: 402, height: 874), safeTop: 62, safeBottom: 34)
    let withCard = TabsDeckGeometry(container: CGSize(width: 402, height: 874), safeTop: 62, safeBottom: 34, reserveAboveBar: 51)
    #expect(withCard.cardCenterY + withCard.cardSize.height / 2 <= bare.barCenterY - TabsDeckGeometry.barCircle / 2 - 16 - 51 + 0.5)
    #expect(withCard.cardCenterY < bare.cardCenterY)
  }

  @Test func `the next card overlaps the focused one`() {
    #expect(geometry.leading(at: 1) < geometry.leading(at: 0) + geometry.cardSize.width)
  }

  @Test func `cards move without a jump as they cross the focus slot`() {
    let step = 0.001
    let leftSlope = (geometry.leading(at: 0) - geometry.leading(at: -step)) / step
    let rightSlope = (geometry.leading(at: step) - geometry.leading(at: 0)) / step
    #expect(abs(leftSlope - rightSlope) / rightSlope < 0.01)
  }

  @Test func `tucked cards stay near the edge and keep their order`() {
    for end in [CGFloat(0), 0.5, 1] {
      let positions = stride(from: -8.0, through: 1, by: 0.05).map { geometry.leading(at: $0, end: end) }
      #expect(positions.allSatisfy { $0 >= -geometry.container.width * 0.03 })
      #expect(zip(positions, positions.dropFirst()).allSatisfy { $0 < $1 })
    }
    let scales = stride(from: -8.0, through: 0, by: 0.5).map { geometry.scale(at: $0) }
    #expect(zip(scales, scales.dropFirst()).allSatisfy { $0 <= $1 })
  }

  @Test func `a mostly covered card shows only its favicon`() {
    #expect(geometry.visibleWidth(at: -1, isLast: false) < TabsDeckGeometry.headerFaviconOnlyWidth)
    #expect(geometry.visibleWidth(at: -1, isLast: false, end: 1) < TabsDeckGeometry.headerFaviconOnlyWidth)
    #expect(abs(geometry.visibleWidth(at: 0, isLast: false) - geometry.spacing) < 0.5)
    #expect(geometry.visibleWidth(at: 0, isLast: true) == geometry.cardSize.width)
  }

  @Test func `a flick carries the deck past the nearest card`() {
    #expect(geometry.settleTarget(from: 5, velocity: 0, count: 10) == 5)
    #expect(geometry.settleTarget(from: 5.2, velocity: -2000, count: 10) == 7)
    #expect(geometry.settleTarget(from: 0.2, velocity: 3000, count: 10) == 0)
    #expect(geometry.settleTarget(from: 9.4, velocity: -4000, count: 10) == 9)
  }

  @Test func `closing a card keeps the focused tab in the middle`() {
    #expect(TabsDeckGeometry.scrollAfterRemoving(index: 2, scroll: 5, remaining: 9) == 4)
    #expect(TabsDeckGeometry.scrollAfterRemoving(index: 5, scroll: 5, remaining: 9) == 5)
    #expect(TabsDeckGeometry.scrollAfterRemoving(index: 9, scroll: 9, remaining: 9) == 8)
    #expect(TabsDeckGeometry.scrollAfterRemoving(index: 0, scroll: 0, remaining: 0) == 0)
  }

  @Test func `a card closes by where Arc's release would carry it, never on a drag down`() {
    let height = geometry.cardSize.height
    #expect(!TabsDeckGeometry.shouldClose(translation: -136, velocity: 0, cardHeight: height))
    #expect(TabsDeckGeometry.shouldClose(translation: -10, velocity: -500, cardHeight: height))
    #expect(TabsDeckGeometry.shouldClose(translation: -130, velocity: -130, cardHeight: height))
    #expect(!TabsDeckGeometry.shouldClose(translation: -100, velocity: -100, cardHeight: height))
    #expect(!TabsDeckGeometry.shouldClose(translation: -88, velocity: 500, cardHeight: height))
    #expect(!TabsDeckGeometry.shouldClose(translation: 120, velocity: 900, cardHeight: height))
  }

  @Test func `only cards near the focus are built`() {
    #expect(TabsDeckGeometry.renderedRange(around: 30, count: 60) == 24..<36)
    #expect(TabsDeckGeometry.renderedRange(around: 0, count: 3) == 0..<3)
    #expect(TabsDeckGeometry.renderedRange(around: 0, count: 0).isEmpty)
  }

  @Test func `landscape cards fit between the header and the bar`() {
    let landscape = TabsDeckGeometry(container: CGSize(width: 852, height: 393), safeTop: 0, safeBottom: 21)
    let top = landscape.cardCenterY - landscape.cardSize.height / 2
    let bottom = landscape.cardCenterY + landscape.cardSize.height / 2
    #expect(top >= TabsDeckGeometry.headerAboveCard)
    #expect(bottom < landscape.barCenterY - 20)
  }
}
