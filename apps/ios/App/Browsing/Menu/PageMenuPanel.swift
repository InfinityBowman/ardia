import ArdiaDesign
import SwiftUI

struct PageMenuPanel: View {
  @Environment(AppModel.self) private var app
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.displayScale) private var displayScale
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @State private var shownID: UUID?
  @State private var isMounted = false
  @State private var rise: CGFloat = 0
  @State private var dimmed = false
  @State private var drag: CGFloat = 0
  @State private var measured = PageMenuMeasuredHeight()
  @State private var panelFills = false
  @State private var generation = 0
  @State private var riders: Double = 0
  @State private var handOff: Double = 1
  @ScaledMetric(relativeTo: .body) private var capsuleHeight: CGFloat = PageMenuLayout.addressHeight

  var body: some View {
    GeometryReader { proxy in
      let safeBottom = proxy.safeAreaInsets.bottom
      let travel = PageMenuLayout.travel(panelHeight: measured.height, safeBottom: safeBottom)
      let isShown = shownID != nil
      ZStack(alignment: .bottom) {
        if isMounted {
          panel(shownID, safeBottom: safeBottom, maxHeight: proxy.size.height - PageMenuLayout.topGap)
            .environment(\.colorScheme, menuScheme)
            .environment(\.pageMenuBarScheme, colorScheme)
            .environment(\.pageMenuShown, isShown)
            .overlay(alignment: .top) {
              PageMenuBarRiders(addressHeight: capsuleHeight)
                .opacity(riders)
            }
            .background(alignment: .top) {
              dim(height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom, isShown: isShown)
            }
            .offset(y: (1 - rise) * travel + drag)
            .environment(\.pageMenuRise, rise)
            .opacity(isShown ? handOff : 0)
            .allowsHitTesting(isShown)
            .accessibilityHidden(!isShown)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) { app.browse.isToolbarPresented = false }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
      .ignoresSafeArea()
    }
    .onChange(of: app.browse.isToolbarPresented, initial: true) { _, presented in
      presented ? open() : close()
    }
    .task { await prewarm() }
  }

  private func dim(height: CGFloat, isShown: Bool) -> some View {
    Color.black
      .opacity(dimmed ? PageMenuLayout.dim : 0)
      .frame(height: height)
      .alignmentGuide(.top) { $0[.bottom] - PageMenuLayout.panelRadius }
      .contentShape(.rect)
      .onTapGesture { app.browse.isToolbarPresented = false }
      .allowsHitTesting(isShown)
      .accessibilityHidden(!isShown)
      .accessibilityLabel("Close Menu")
      .accessibilityAddTraits(.isButton)
  }

  private func panel(_ id: UUID?, safeBottom: CGFloat, maxHeight: CGFloat) -> some View {
    ToolbarSheet(tabID: id, panelMaxHeight: maxHeight - safeBottom, onClose: { app.browse.isToolbarPresented = false })
      .padding(.bottom, safeBottom)
      .background(alignment: .top) {
        fill
          .modifier(PageMenuRiseOpacity(rise: rise, curve: .landing))
          .clipShape(UnevenRoundedRectangle(topLeadingRadius: PageMenuLayout.panelRadius, topTrailingRadius: PageMenuLayout.panelRadius, style: .continuous))
          .padding(.bottom, -PageMenuLayout.overhang)
          .allowsHitTesting(false)
      }
      .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured.height = $0 }
      .onGeometryChange(for: Bool.self) { $0.size.height >= maxHeight } action: { panelFills = $0 }
      .highPriorityGesture(pull, isEnabled: !panelFills)
      .simultaneousGesture(pull, isEnabled: panelFills)
  }

  private func prewarm() async {
    try? await Task.sleep(for: PageMenuLayout.prewarmDelay)
    guard !isMounted else { return }
    HarnessProbe.mark("menu.prewarm")
    var instant = Transaction()
    instant.disablesAnimations = true
    withTransaction(instant) { isMounted = true }
  }

  @ViewBuilder
  private var material: some View {
    if reduceTransparency {
      Palette.menuPanel
    } else {
      ZStack {
        BarBackdropBlur()
        Palette.menuMaterialTint
      }
    }
  }

  private var fill: some View {
    material
      .overlay(alignment: .top) {
        UnevenRoundedRectangle(topLeadingRadius: PageMenuLayout.panelRadius, topTrailingRadius: PageMenuLayout.panelRadius, style: .continuous)
          .stroke(Palette.menuPanelEdge, lineWidth: 1 / max(displayScale, 1))
      }
  }

  private var menuScheme: ColorScheme {
    guard let tab = app.tabs.selectedTab, let bottom = app.browse.tone(for: tab, page: app.currentPage).bottom else { return colorScheme }
    return bottom.scheme
  }

  private var pull: some Gesture {
    DragGesture(minimumDistance: 8, coordinateSpace: .global)
      .onChanged { value in
        drag = max(value.translation.height, 0)
      }
      .onEnded { value in
        let fling = value.predictedEndTranslation.height - value.translation.height
        if value.translation.height > PageMenuLayout.pullToClose || fling > PageMenuLayout.flingToClose {
          app.browse.isToolbarPresented = false
        } else {
          withAnimation(PageMenuLayout.open) { drag = 0 }
        }
      }
  }

  private func open() {
    HarnessProbe.mark("menu.open")
    guard let id = app.tabs.selectedTabID else {
      app.browse.isToolbarPresented = false
      return
    }
    let isWarm = isMounted
    var instant = Transaction()
    instant.disablesAnimations = true
    withTransaction(instant) {
      if shownID == nil {
        generation += 1
        riders = 1
      }
      isMounted = true
      handOff = 1
      shownID = id
      app.browse.pageMenuCarriesBarControls = true
      drag = 0
      if reduceMotion {
        rise = 1
        riders = 0
      }
    }
    let rising = {
      withAnimation(reduceMotion ? Motion.surfaceFade : PageMenuLayout.open) { rise = 1 }
      withAnimation(PageMenuLayout.ridersLeave) { riders = 0 }
      withAnimation(Motion.trayDim) { dimmed = true }
    }
    if isWarm {
      rising()
    } else {
      DispatchQueue.main.async(execute: rising)
    }
  }

  private func close() {
    guard shownID != nil else { return }
    HarnessProbe.mark("menu.close")
    let closing = generation
    if app.browse.search != nil, !reduceMotion {
      handToSearch(closing)
      return
    }
    withAnimation(PageMenuLayout.dimClear) { dimmed = false }
    withAnimation(reduceMotion ? Motion.surfaceFade : PageMenuLayout.ridersArrive) { riders = 1 }
    withAnimation(reduceMotion ? Motion.surfaceFade : PageMenuLayout.close) {
      rise = 0
      drag = 0
    } completion: {
      guard closing == generation, !app.browse.isToolbarPresented else { return }
      shownID = nil
      app.browse.pageMenuCarriesBarControls = false
      drag = 0
    }
  }
}

extension PageMenuPanel {
  private static let handOffFade = Animation.easeOut(duration: 0.1)

  private func handToSearch(_ closing: Int) {
    withAnimation(Self.handOffFade) {
      dimmed = false
      handOff = 0
    } completion: {
      guard closing == generation, !app.browse.isToolbarPresented else { return }
      var instant = Transaction()
      instant.disablesAnimations = true
      withTransaction(instant) {
        shownID = nil
        app.browse.pageMenuCarriesBarControls = false
        rise = 0
        riders = 1
        drag = 0
        handOff = 1
      }
    }
  }
}

final class PageMenuMeasuredHeight {
  var height: CGFloat = 560
}

extension EnvironmentValues {
  @Entry var pageMenuRise: CGFloat = 1
  @Entry var pageMenuBarScheme: ColorScheme?
  @Entry var pageMenuShown = true
  @Entry var pageMenuRevealAnimation: Animation? = PageMenuLayout.expand
}

struct PageMenuShownWatcher: ViewModifier {
  let onShow: () -> Void
  let onHide: () -> Void

  @Environment(\.pageMenuShown) private var isShown

  func body(content: Content) -> some View {
    content.onChange(of: isShown) { _, shown in
      shown ? onShow() : onHide()
    }
  }
}

enum PageMenuRiseCurve {
  case content
  case address
  case landing
  case plusGlyph

  func opacity(_ rise: CGFloat) -> Double {
    switch self {
    case .content: PageMenuLayout.contentOpacity(rise: rise)
    case .address: PageMenuLayout.addressOpacity(rise: rise)
    case .landing: PageMenuLayout.landingOpacity(rise: rise)
    case .plusGlyph: min(Double(1 - rise), PageMenuLayout.landingOpacity(rise: rise))
    }
  }
}

struct PageMenuRiseOpacity: ViewModifier, Animatable {
  var rise: CGFloat
  let curve: PageMenuRiseCurve

  var animatableData: CGFloat {
    get { rise }
    set { rise = newValue }
  }

  func body(content: Content) -> some View {
    content.opacity(curve.opacity(rise))
  }
}

struct PageMenuContentFade: ViewModifier {
  @Environment(\.pageMenuRise) private var rise

  func body(content: Content) -> some View {
    content.modifier(PageMenuRiseOpacity(rise: rise, curve: .content))
  }
}

struct PageMenuAddressFade: ViewModifier {
  let isLarge: Bool

  @Environment(\.pageMenuRise) private var rise

  func body(content: Content) -> some View {
    content.modifier(PageMenuRiseOpacity(rise: isLarge ? 1 : rise, curve: .address))
  }
}

struct PageMenuAddressBackdrop: View {
  @Environment(\.pageMenuRise) private var rise
  @Environment(\.pageMenuBarScheme) private var barScheme
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    PageMenuAddressShape(rise: rise)
      .fill(Palette.menuGroup)
      .modifier(PageMenuRiseOpacity(rise: rise, curve: .landing))
      .overlay {
        Image(systemName: "plus")
          .font(.system(size: BrowseLayout.barPlusGlyph, weight: .medium))
          .foregroundStyle(BrowsePalette.barGlyph)
          .environment(\.colorScheme, barScheme ?? colorScheme)
          .modifier(PageMenuRiseOpacity(rise: rise, curve: .plusGlyph))
          .accessibilityHidden(true)
      }
  }
}

extension BarActions {
  static let inert = BarActions(onTabs: {}, onAddress: {}, onPlus: {}, onMore: {}, onExpand: {}, onStep: { _ in }, onSelectTab: { _ in }, onCloseTab: {})
}

struct PageMenuBarRiders: View {
  let addressHeight: CGFloat

  @Environment(AppModel.self) private var app

  var body: some View {
    ZStack {
      BarTabsStackButton(actions: .inert)
        .frame(maxWidth: .infinity, alignment: .leading)
      BarPageMenuButton(address: BarAddress(tab: app.tabs.selectedTab, page: app.currentPage), action: {})
        .padding(.trailing, BrowseLayout.barSide - (BrowseLayout.hitTarget - BrowseLayout.barCircle) / 2)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .frame(height: BrowseLayout.barControl)
    .padding(.top, PageMenuLayout.inset + addressHeight / 2 - BrowseLayout.barControl / 2)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

struct CarriedByPageMenu: ViewModifier {
  @Environment(AppModel.self) private var app

  func body(content: Content) -> some View {
    content.opacity(app.browse.pageMenuCarriesBarControls ? 0 : 1)
  }
}

nonisolated struct PageMenuAddressShape: Shape {
  var rise: CGFloat

  var animatableData: CGFloat {
    get { rise }
    set { rise = newValue }
  }

  func path(in rect: CGRect) -> Path {
    let start = BrowseLayout.barPlus
    let width = start.width + (rect.width - start.width) * rise
    let height = start.height + (rect.height - start.height) * rise
    let frame = CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    return Path(roundedRect: frame, cornerRadius: height / 2, style: .continuous)
  }
}
