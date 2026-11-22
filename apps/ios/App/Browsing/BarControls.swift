import ArdiaBrowser
import ArdiaDesign
import SwiftUI

struct BarAddress: Equatable {
  var host: String
  var iconURL: String?
  var pageURL: String?
  var isPrivate: Bool
  var isInsecure: Bool

  init(tab: BrowserTab?, page: WebTab?) {
    let url = page?.url?.absoluteString ?? tab?.url
    host = page?.host ?? url.flatMap(BrowserURL.host(of:)) ?? tab.map(TabText.title(for:)) ?? String(localized: "New Tab")
    iconURL = tab?.faviconURL
    pageURL = url
    isPrivate = tab?.isPrivate ?? false
    if let page, page.url != nil {
      isInsecure = page.security == .insecure
    } else {
      isInsecure = url.flatMap { URL(string: $0)?.scheme?.lowercased() } == "http"
    }
  }
}

struct BarActions {
  var onTabs: () -> Void
  var onAddress: () -> Void
  var onPlus: () -> Void
  var onMore: () -> Void
  var onExpand: () -> Void
  var onStep: (Int) -> Void
  var onSelectTab: (UUID) -> Void
  var onCloseTab: () -> Void
}

struct BarTabsButton: View {
  let actions: BarActions

  @Environment(AppModel.self) private var app

  var body: some View {
    let order = app.deckOrder
    Button(action: actions.onTabs) {
      TabStackGlyph(tabs: Array(order.suffix(2)))
        .frame(width: BrowseLayout.barControl, height: BrowseLayout.barControl)
        .contentShape(.circle)
    }
    .buttonStyle(BarButtonStyle())
    .chromeSurface(in: .circle)
    .classicBarShadow()
    .contextMenu { BarRecentTabsMenu(order: order, actions: actions) }
    .accessibilityLabel("Tabs")
    .accessibilityValue(Text("^[\(order.count) tab](inflect: true)"))
    .accessibilityHint("Touch and hold for recent tabs.")
    .accessibilityActions {
      Button("Previous Tab") { actions.onStep(-1) }
      Button("Next Tab") { actions.onStep(1) }
    }
  }
}

struct BarTabsStackButton: View {
  let actions: BarActions

  @Environment(AppModel.self) private var app

  var body: some View {
    let order = app.deckOrder
    let others = order.filter { $0.id != app.tabs.selectedTabID }
    let front = others.last ?? order.last
    let back = others.count > 1 ? others[others.count - 2] : nil
    Button(action: actions.onTabs) {
      ArcTabStack(back: back, front: front)
        .contentShape(.rect)
    }
    .buttonStyle(BarButtonStyle())
    .padding(.leading, BrowseLayout.barSide)
    .contextMenu { BarRecentTabsMenu(order: order, actions: actions) }
    .accessibilityLabel("Tabs")
    .accessibilityValue(Text("^[\(order.count) tab](inflect: true)"))
    .accessibilityHint("Touch and hold for recent tabs.")
    .accessibilityActions {
      Button("Previous Tab") { actions.onStep(-1) }
      Button("Next Tab") { actions.onStep(1) }
    }
  }
}

struct BarRecentTabsMenu: View {
  let order: [BrowserTab]
  let actions: BarActions

  @Environment(AppModel.self) private var app

  var body: some View {
    let recent = order.filter { $0.id != app.tabs.selectedTabID }.suffix(8).reversed()
    ForEach(Array(recent)) { tab in
      Button(TabText.title(for: tab)) { actions.onSelectTab(tab.id) }
    }
    if !recent.isEmpty { Divider() }
    Button("Close Tab", systemImage: "xmark", role: .destructive, action: actions.onCloseTab)
  }
}

struct BarPlusCapsule: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "plus")
        .font(.system(size: BrowseLayout.barPlusGlyph, weight: .medium))
        .foregroundStyle(BrowsePalette.barGlyph)
        .frame(width: BrowseLayout.barPlus.width, height: BrowseLayout.barPlus.height)
        .background(BrowsePalette.barPlusFill, in: .capsule)
        .overlay { Capsule().strokeBorder(BrowsePalette.barControlEdge, lineWidth: 0.5) }
        .frame(height: BrowseLayout.barControl)
        .contentShape(.capsule)
    }
    .buttonStyle(BarPressStyle())
    .accessibilityLabel("New Search")
  }
}

struct BarPageMenuButton: View {
  let address: BarAddress
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "chevron.up")
        .font(.system(size: BrowseLayout.barChevronGlyph, weight: .semibold))
        .foregroundStyle(BrowsePalette.barGlyph)
        .frame(width: BrowseLayout.barCircle, height: BrowseLayout.barCircle)
        .background(BrowsePalette.barCircleFill, in: .circle)
        .overlay { Circle().strokeBorder(BrowsePalette.barControlEdge, lineWidth: 0.5) }
        .frame(width: BrowseLayout.hitTarget, height: BrowseLayout.barControl)
        .contentShape(.rect)
    }
    .buttonStyle(BarPressStyle())
    .accessibilityLabel("Page Menu")
    .accessibilityValue(address.isInsecure ? Text("\(address.host), Not Secure") : Text(address.host))
    .accessibilityHint("Shows this page’s address and actions.")
  }
}

struct BarPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .brightness(configuration.isPressed ? 0.08 : 0)
      .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: configuration.isPressed) { _, pressed in pressed }
  }
}

struct BarPlusButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "plus")
        .font(.system(size: BrowseLayout.barGlyph, weight: .medium))
        .foregroundStyle(BrowsePalette.foregroundPrimary)
        .frame(width: BrowseLayout.barControl, height: BrowseLayout.barControl)
        .contentShape(.circle)
    }
    .buttonStyle(BarButtonStyle())
    .chromeSurface(in: .circle)
    .classicBarShadow()
    .accessibilityLabel("New Search")
  }
}

private struct ClassicBarShadow: ViewModifier {
  @Environment(\.usesGlass) private var usesGlass

  func body(content: Content) -> some View {
    if usesGlass {
      content
    } else {
      content
        .compositingGroup()
        .shadow(color: BrowsePalette.classicBarShadow, radius: BrowseLayout.classicBarShadowRadius, y: 2)
    }
  }
}

extension View {
  func classicBarShadow() -> some View {
    modifier(ClassicBarShadow())
  }
}
