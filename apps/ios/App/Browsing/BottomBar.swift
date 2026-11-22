import ArdiaBrowser
import ArdiaDesign
import SwiftUI

struct BottomBar: View {
  enum Arrangement {
    case row
    case column(ScreenLayout.SideColumn, CGSize)
  }

  let address: BarAddress
  var arrangement = Arrangement.row
  var sideInset: CGFloat = 0
  var safeBottom: CGFloat = 0
  var pageColor: Color?
  let actions: BarActions

  var body: some View {
    if case .column(let column, let size) = arrangement {
      SideColumnStack(column: column, size: size) {
        BarTabsButton(actions: actions)
        BarSiteButton(address: address, action: actions.onAddress)
        BarRoundMenuButton(action: actions.onMore)
        BarPlusButton(action: actions.onPlus)
      }
    } else {
      rowBar
    }
  }

  private var rowBar: some View {
    ZStack {
      BarTabsStackButton(actions: actions)
        .frame(maxWidth: .infinity, alignment: .leading)
      BarPlusCapsule(action: actions.onPlus)
      BarPageMenuButton(address: address, action: actions.onMore)
        .padding(.trailing, BrowseLayout.barSide - (BrowseLayout.hitTarget - BrowseLayout.barCircle) / 2)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .frame(height: BrowseLayout.barControl)
    .padding(.horizontal, sideInset)
    .padding(.bottom, safeBottom + BrowseLayout.barButtonLine - BrowseLayout.barControl / 2)
    .frame(maxWidth: .infinity)
    .background(alignment: .bottom) {
      BarBand(height: BrowseLayout.barBand + safeBottom, pageColor: pageColor)
    }
  }
}

struct BarBand: View {
  let height: CGFloat
  let pageColor: Color?

  var body: some View {
    let line = BrowseLayout.barBand - BrowseLayout.barButtonLine
    VStack(spacing: 0) {
      LinearGradient(colors: [BrowsePalette.barBandTop.opacity(0), BrowsePalette.barFadeEdge], startPoint: .top, endPoint: .bottom)
        .frame(height: BrowseLayout.barFade)
      LinearGradient(
        stops: [
          .init(color: BrowsePalette.barBandTop, location: 0),
          .init(color: BrowsePalette.barBandMiddle, location: line / height),
          .init(color: BrowsePalette.barBandBottom, location: BrowseLayout.barBand / height),
          .init(color: BrowsePalette.barBandBottom, location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .background(pageColor ?? Color(.systemBackground))
      .frame(height: height)
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

enum BarPalette {
  static let tileFill = Color.adaptive(light: Color(hex: 0x767680, opacity: 0.2), dark: Color.white.opacity(0.2))
  static let tileEdge = Color.adaptive(light: Color.black.opacity(0.14), dark: Color.white.opacity(0.28))
}

struct BarButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: configuration.isPressed) { _, pressed in pressed }
  }
}

struct TabStackGlyph: View {
  let tabs: [BrowserTab]

  var body: some View {
    ZStack {
      switch tabs.count {
      case 0:
        RoundedRectangle(cornerRadius: BrowseLayout.tabStackRadius, style: .continuous)
          .strokeBorder(BrowsePalette.foregroundSecondary, lineWidth: 1.5)
          .frame(width: BrowseLayout.tabStackTile.width, height: BrowseLayout.tabStackTile.height)
      case 1:
        TabThumbnail(tab: tabs[0])
          .rotationEffect(.degrees(-4))
      default:
        TabThumbnail(tab: tabs[0])
          .rotationEffect(.degrees(-12))
          .offset(x: -4, y: 1)
        TabThumbnail(tab: tabs[1])
          .rotationEffect(.degrees(6))
          .offset(x: 4, y: -1)
      }
    }
    .accessibilityHidden(true)
  }
}

struct ArcTabStack: View {
  let back: BrowserTab?
  let front: BrowserTab?

  var body: some View {
    let width = BrowseLayout.tabsButtonWidth
    let height = BrowseLayout.barControl
    let origin = CGPoint(x: BrowseLayout.barSide, y: height / 2)
    ZStack(alignment: .topLeading) {
      if let back {
        TabThumbnail(tab: back)
          .rotationEffect(.degrees(BrowseLayout.tabStackBackTilt))
          .position(x: BrowseLayout.tabStackBack.x - origin.x, y: origin.y + BrowseLayout.tabStackBack.y)
      }
      if let front {
        TabThumbnail(tab: front)
          .rotationEffect(.degrees(BrowseLayout.tabStackFrontTilt))
          .position(x: BrowseLayout.tabStackFront.x - origin.x, y: origin.y + BrowseLayout.tabStackFront.y)
      } else {
        RoundedRectangle(cornerRadius: BrowseLayout.tabStackRadius, style: .continuous)
          .strokeBorder(BrowsePalette.barGlyph, lineWidth: 1.5)
          .frame(width: BrowseLayout.tabStackTile.width, height: BrowseLayout.tabStackTile.height)
          .rotationEffect(.degrees(BrowseLayout.tabStackFrontTilt))
          .position(x: BrowseLayout.tabStackFront.x - origin.x, y: origin.y + BrowseLayout.tabStackFront.y)
      }
    }
    .frame(width: width, height: height)
    .accessibilityHidden(true)
  }
}

struct TabThumbnail: View {
  let tab: BrowserTab

  @Environment(AppModel.self) private var app
  @State private var image: CGImage?

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: BrowseLayout.tabStackRadius, style: .continuous)
  }

  var body: some View {
    let size = BrowseLayout.tabStackTile
    ZStack {
      if let memory = app.browse.covers.image(for: tab.id) ?? app.deck.memoryImage(for: tab.id) {
        Image(uiImage: memory)
          .resizable()
          .scaledToFill()
          .frame(width: size.width, height: size.height, alignment: .top)
      } else if let image {
        Image(decorative: image, scale: 1)
          .resizable()
          .scaledToFill()
          .frame(width: size.width, height: size.height, alignment: .top)
      } else {
        fallback
      }
    }
    .frame(width: size.width, height: size.height)
    .clipShape(shape)
    .overlay { shape.strokeBorder(BarPalette.tileEdge, lineWidth: 0.5) }
    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
    .task(id: tab.snapshotFileName) {
      guard let name = tab.snapshotFileName else {
        image = nil
        return
      }
      image = app.web.snapshots.cachedImage(named: name)
      if image == nil { image = await app.web.snapshots.image(named: name) }
    }
  }

  @ViewBuilder
  private var fallback: some View {
    if tab.isPrivate {
      TabsPalette.incognitoCard
      IncognitoGlyph(size: 12)
    } else {
      ZStack {
        if let theme = ToneColor(hex: tab.themeColorHex) { theme.color } else { BarPalette.tileFill }
        FaviconImage(iconURL: tab.faviconURL, pageURL: tab.url, size: 12)
      }
    }
  }
}

struct PressableStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.94 : 1)
      .animation(Motion.press, value: configuration.isPressed)
  }
}
