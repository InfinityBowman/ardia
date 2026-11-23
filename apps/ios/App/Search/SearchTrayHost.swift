import ArdiaDesign
import SwiftUI

struct SearchTrayHost: View {
  @Environment(AppModel.self) private var app
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.screenLayout) private var screenLayout
  @Environment(\.profileLook) private var look
  @Environment(\.usesGlass) private var usesGlass
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @ScaledMetric(relativeTo: .title3) private var fieldScale: CGFloat = 1
  @State private var shown: BrowseSession.SearchRequest?
  @State private var presentation = 0
  @State private var isFocused = false
  @State private var isClosing = false
  @State private var hasLanded = false
  @State private var keyboard = KeyboardTracker()
  @State private var keyboardHeight: CGFloat = 0
  @State private var dragOffset: CGFloat = 0
  @State private var isDragging = false
  @State private var heldLift: CGFloat?
  @State private var trayHeight: CGFloat = 0
  @State private var settleTask: Task<Void, Never>?
  @State private var landingTask: Task<Void, Never>?
  @State private var removalTask: Task<Void, Never>?
  @State private var showsBarIcons = false

  static let keyboardThreshold: CGFloat = 120

  var body: some View {
    ZStack {
      keyboardProbe
      tray
    }
  }

  private var tray: some View {
    GeometryReader { proxy in
      let safeBottom = proxy.safeAreaInsets.bottom
      let keyboardUp = keyboardHeight > Self.keyboardThreshold
      let restsWithoutKeyboard = hasLanded && !keyboardUp && !isClosing
      let liveLift = restsWithoutKeyboard ? max(keyboardHeight, safeBottom) : keyboardHeight
      let isUp = keyboardUp || (!isClosing && hasLanded)
      let expected = !isClosing && keyboard.height > Self.keyboardThreshold ? keyboard.height : 0
      let lift = heldLift ?? max(liveLift, expected)
      let command = screenLayout.isWide ? CommandBarPlacement(proxy: proxy, lift: lift) : nil
      let maxHeight = command?.maxHeight ?? maxHeight(in: proxy, lift: lift)
      let progress = TrayDrag.progress(offset: dragOffset, travel: trayHeight + lift)
      let restingDrop = isUp || reduceMotion || command != nil ? 0 : maxHeight + BrowseLayout.sheetTopRadius
      ZStack(alignment: .bottom) {
        if command == nil {
          KeyboardRider(
            holdsLift: heldLift != nil,
            dragOffset: dragOffset,
            isVisible: shown != nil && !isClosing,
            isInteractive: shown != nil && !isClosing,
            growth: growth(panelHeight: maxHeight, safeBottom: safeBottom),
            onDismiss: { app.cancelSearch() },
            onClosed: { finishClosing() },
            preview: { AnyView(previewTray(maxHeight: maxHeight, safeBottom: safeBottom)) },
            content: riderContent(maxHeight: maxHeight, liveLift: liveLift, safeBottom: safeBottom),
            icons: barIcons(safeBottom: safeBottom),
            band: SearchBarBand(height: BrowseLayout.barHeight(safeBottom: safeBottom), isShown: handsBackToBar)
          )
          .ignoresSafeArea()
        } else if let shown {
          dim(over: shown)
            .opacity(isUp ? 1 - progress : 0)
            .animation(reduceMotion ? Motion.surfaceFade : Motion.trayDim, value: isUp)
            .allowsHitTesting(isUp && !isClosing)
            .ignoresSafeArea()
          SearchTray(request: shown, isFocused: $isFocused, maxHeight: maxHeight, dismissDrag: dismissDrag(lift: liveLift), pull: pull(lift: liveLift))
            .id(presentation)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { trayHeight = $0 }
            .modifier(CommandBarFrame(placement: command, isUp: isUp))
            .offset(y: command == nil ? safeBottom - lift + dragOffset + restingDrop : dragOffset)
            .opacity(isUp || (!reduceMotion && command == nil) ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: command == nil ? .bottom : .top)
            .allowsHitTesting(!isClosing)
            .accessibilityAddTraits(.isModal)
        }
      }
      .onChange(of: liveLift, initial: true) { _, live in
        guard shown != nil else { return }
        if live > Self.keyboardThreshold, !isClosing, !hasLanded {
          landingTask?.cancel()
          hasLanded = true
        }
        if !isDragging, let held = heldLift, abs(live - held) < 2 {
          heldLift = nil
        }
      }
    }
    .ignoresSafeArea(.keyboard)
    .onAppear {
      keyboard.start()
      KeyboardPrewarm.schedule()
    }
    .task { await SearchSuggestionsModel.loadRecents(from: app.tabs) }
    .onChange(of: app.browse.search, initial: true) { _, request in
      if let request {
        present(request)
      } else if shown != nil {
        beginClosing()
      }
    }
  }

  private func riderContent(maxHeight: CGFloat, liveLift: CGFloat, safeBottom: CGFloat) -> some View {
    Group {
      if let shown {
        SearchTray(
          request: shown,
          isFocused: $isFocused,
          maxHeight: maxHeight,
          dismissDrag: dismissDrag(lift: liveLift),
          pull: pull(lift: liveLift),
          barLineAboveBottom: BrowseLayout.barLine(safeBottom: safeBottom) - safeBottom
        )
        .id(presentation)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { trayHeight = $0 }
        .accessibilityAddTraits(.isModal)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .ignoresSafeArea()
    .environment(app)
    .environment(\.profileLook, look)
    .environment(\.usesGlass, usesGlass)
    .environment(\.screenLayout, screenLayout)
  }

  private func previewTray(maxHeight: CGFloat, safeBottom: CGFloat) -> some View {
    SearchTray(
      request: BrowseSession.SearchRequest(origin: .page, initialText: "", selectsAll: false, incognitoOnCancel: nil),
      isFocused: .constant(false),
      maxHeight: maxHeight,
      dismissDrag: DragGesture(),
      pull: TrayPull(changed: { _ in }, ended: { _, _ in }),
      barLineAboveBottom: BrowseLayout.barLine(safeBottom: safeBottom) - safeBottom
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .ignoresSafeArea()
    .environment(app)
    .environment(\.profileLook, look)
    .environment(\.usesGlass, usesGlass)
    .environment(\.screenLayout, screenLayout)
  }

  private func barIcons(safeBottom: CGFloat) -> SearchBarIcons {
    SearchBarIcons(safeBottom: safeBottom, isShown: showsBarIcons && handsBackToBar, app: app, look: look, usesGlass: usesGlass, screenLayout: screenLayout)
  }

  private var handsBackToBar: Bool {
    app.surface == .browsing && app.tabs.selectedTabID != nil
  }

  private func growth(panelHeight: CGFloat, safeBottom: CGFloat) -> RiderGrowth {
    let incognito = app.isIncognito
    let colors = PanelColors.resolved(incognito: incognito, dark: colorScheme == .dark, opaque: reduceTransparency)
    return RiderGrowth(
      panelHeight: panelHeight,
      lineAboveBottom: BrowseLayout.barLine(safeBottom: safeBottom),
      bandAboveBottom: BrowseLayout.barHeight(safeBottom: safeBottom),
      fieldTop: BrowseLayout.sheetFieldTop,
      fieldInset: BrowseLayout.sheetFieldInset,
      fieldHeight: BrowseLayout.searchFieldHeight * fieldScale,
      fieldLeading: BrowseLayout.sheetFieldLeading,
      fieldTrailing: BrowseLayout.sheetFieldTrailing,
      capsule: BrowseLayout.barPlus,
      glyphSize: BrowseLayout.barPlusGlyph,
      font: PanelColors.font(for: dynamicTypeSize),
      panelFill: colors.panelFill,
      panelBlurs: colors.panelBlurs,
      panelRadius: BrowseLayout.sheetPanelRadius,
      fieldFill: colors.fieldFill,
      fieldEdge: colors.fieldEdge,
      glyph: colors.glyph,
      placeholder: colors.placeholder,
      text: colors.text,
      accessory: colors.accessory,
      accent: colors.accent,
      tileFill: colors.tileFill,
      tileEdge: colors.tileEdge,
      initialText: shown?.initialText ?? "",
      showsAccessories: !incognito && !dynamicTypeSize.isAccessibilitySize,
      dim: shown?.origin == .page ? BrowseLayout.trayDim : 0,
      handsBackToBar: handsBackToBar
    )
  }

  private var keyboardProbe: some View {
    GeometryReader { proxy in
      Color.clear
        .onChange(of: proxy.safeAreaInsets.bottom, initial: true) { _, inset in
          let target = inset > Self.keyboardThreshold ? inset : 0
          guard target != keyboardHeight else { return }
          withAnimation(keyboard.animation) { keyboardHeight = target }
        }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func dim(over request: BrowseSession.SearchRequest) -> some View {
    Color.black
      .opacity(request.origin == .page ? BrowseLayout.trayDim : 0.001)
      .contentShape(.rect)
      .onTapGesture { app.cancelSearch() }
      .accessibilityLabel("Close Search")
      .accessibilityAddTraits(.isButton)
  }

  private func maxHeight(in proxy: GeometryProxy, lift: CGFloat) -> CGFloat {
    let preferred = BrowseLayout.sheetAboveKeyboard + BrowseLayout.searchFieldHeight * (fieldScale - 1)
    let available = proxy.size.height + proxy.safeAreaInsets.bottom - lift - Spacing.tight - BrowseLayout.panelAboveKeyboard
    return max(min(preferred, available), 0)
  }

  private func present(_ request: BrowseSession.SearchRequest) {
    removalTask?.cancel()
    settleTask?.cancel()
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      if shown == nil || isClosing { presentation += 1 }
      shown = request
      isClosing = false
      hasLanded = keyboardHeight > Self.keyboardThreshold
      dragOffset = 0
      heldLift = nil
      isDragging = false
    }
    app.browse.trayHoldsKeyboard = true
    if !showsBarIcons { DispatchQueue.main.async { showsBarIcons = true } }
    landingTask?.cancel()
    landingTask = Task {
      try? await Task.sleep(for: .milliseconds(450))
      guard !Task.isCancelled, shown != nil, !isClosing, !hasLanded else { return }
      withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Motion.searchRise) { hasLanded = true }
    }
  }

  private func refreshRecents() {
    let tabs = app.tabs
    Task {
      await SearchSuggestionsModel.loadRecents(from: tabs)
      try? await Task.sleep(for: .seconds(3))
      guard shown == nil else { return }
      await SearchSuggestionsModel.loadRecents(from: tabs)
    }
  }

  private func beginClosing() {
    guard !isClosing else { return }
    landingTask?.cancel()
    settleTask?.cancel()
    isFocused = false
    if !screenLayout.isWide || (keyboardHeight > Self.keyboardThreshold && heldLift == nil) {
      isClosing = true
    } else {
      let travel = trayHeight + (heldLift ?? 0) + BrowseLayout.sheetTopRadius
      withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Motion.trayDismiss) {
        isClosing = true
        if heldLift != nil, !reduceMotion { dragOffset = max(dragOffset, travel) }
      }
    }
    removalTask?.cancel()
    let phone = !screenLayout.isWide
    removalTask = Task {
      for _ in 0..<20 where keyboardHeight > Self.keyboardThreshold && !phone {
        try? await Task.sleep(for: .milliseconds(50))
      }
      try? await Task.sleep(for: phone ? .seconds(2) : .milliseconds(450))
      guard !Task.isCancelled, isClosing else { return }
      finishClosing()
    }
  }

  private func finishClosing() {
    guard isClosing else { return }
    removalTask?.cancel()
    finish()
    refreshRecents()
  }

  private func finish() {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      shown = nil
      isClosing = false
      hasLanded = false
      dragOffset = 0
      heldLift = nil
      isDragging = false
    }
    app.browse.trayHoldsKeyboard = false
  }

  private func dismissDrag(lift: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 6, coordinateSpace: .global)
      .onChanged { value in dragChanged(value.translation.height, lift: lift) }
      .onEnded { value in dragEnded(value.translation.height, velocity: value.velocity.height) }
  }

  /// The same pull, for a surface (the results) that decides for itself when a drag is a pull.
  private func pull(lift: CGFloat) -> TrayPull {
    TrayPull(
      changed: { dragChanged($0, lift: lift) },
      ended: { dragEnded($0, velocity: $1) }
    )
  }

  private func dragChanged(_ translation: CGFloat, lift: CGFloat) {
    guard !isClosing else { return }
    if !isDragging {
      isDragging = true
      settleTask?.cancel()
    }
    if TrayDrag.releasesKeyboard(translation: translation), isFocused {
      if heldLift == nil { heldLift = lift }
      isFocused = false
    }
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) { dragOffset = TrayDrag.offset(for: translation) }
  }

  private func dragEnded(_ translation: CGFloat, velocity: CGFloat) {
    guard isDragging else { return }
    isDragging = false
    if TrayDrag.shouldDismiss(translation: translation, velocity: velocity, trayHeight: trayHeight) {
      app.cancelSearch()
    } else {
      settle()
    }
  }

  private func settle() {
    let wasHolding = heldLift != nil
    if wasHolding, !app.settings.isShowingOnboarding { isFocused = true }
    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Motion.traySettle) { dragOffset = 0 }
    guard wasHolding else { return }
    settleTask = Task {
      try? await Task.sleep(for: .milliseconds(650))
      guard !Task.isCancelled, !isDragging else { return }
      withAnimation(Motion.traySettle) { heldLift = nil }
    }
  }
}

@MainActor
private struct PanelColors {
  let panelFill: UIColor
  let panelBlurs: Bool
  let fieldFill: UIColor
  let fieldEdge: UIColor
  let glyph: UIColor
  let placeholder: UIColor
  let text: UIColor
  let accessory: UIColor
  let accent: UIColor
  let tileFill: UIColor
  let tileEdge: UIColor

  private static var cache: [Int: PanelColors] = [:]
  private static var fonts: [DynamicTypeSize: UIFont] = [:]

  static func resolved(incognito: Bool, dark: Bool, opaque: Bool) -> PanelColors {
    let key = (incognito ? 4 : 0) + (dark ? 2 : 0) + (opaque ? 1 : 0)
    if let cached = cache[key] { return cached }
    let panelTraits = UITraitCollection(userInterfaceStyle: dark || incognito ? .dark : .light)
    let barTraits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
    func resolve(_ color: Color) -> UIColor { UIColor(color).resolvedColor(with: panelTraits) }
    let blurs = dark && !incognito && !opaque
    let fill: Color = incognito ? SearchPanelPalette.incognitoFill : blurs ? SearchPanelPalette.materialTint.opacity(SearchPanelPalette.materialTintShare) : SearchPanelPalette.fill
    let colors = PanelColors(
      panelFill: resolve(fill),
      panelBlurs: blurs,
      fieldFill: resolve(incognito ? SearchPanelPalette.incognitoField : SearchPanelPalette.field),
      fieldEdge: resolve(SearchPanelPalette.fieldEdge),
      glyph: UIColor(BrowsePalette.barGlyph).resolvedColor(with: barTraits),
      placeholder: resolve(SearchPanelPalette.placeholder),
      text: resolve(SearchPanelPalette.text),
      accessory: resolve(SearchPanelPalette.accessory),
      accent: resolve(BrowsePalette.searchAccent),
      tileFill: UIColor(BrowsePalette.barPlusFill).resolvedColor(with: barTraits),
      tileEdge: UIColor(BrowsePalette.barControlEdge).resolvedColor(with: barTraits)
    )
    cache[key] = colors
    return colors
  }

  static func font(for size: DynamicTypeSize) -> UIFont {
    if let cached = fonts[size] { return cached }
    let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 17))
    fonts[size] = font
    return font
  }
}

private struct SearchBarIcons: View, Equatable {
  let safeBottom: CGFloat
  let isShown: Bool
  let app: AppModel
  let look: ProfileLook
  let usesGlass: Bool
  let screenLayout: ScreenLayout

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.safeBottom == rhs.safeBottom && lhs.isShown == rhs.isShown && lhs.app === rhs.app
      && lhs.look == rhs.look && lhs.usesGlass == rhs.usesGlass && lhs.screenLayout == rhs.screenLayout
  }

  var body: some View {
    if isShown {
      BottomBar(
        address: BarAddress(tab: app.tabs.selectedTab, page: app.currentPage),
        safeBottom: safeBottom,
        iconsOnly: true,
        actions: BarActions(onTabs: {}, onAddress: {}, onPlus: {}, onMore: {}, onExpand: {}, onStep: { _ in }, onSelectTab: { _ in }, onCloseTab: {})
      )
      .frame(height: BrowseLayout.barHeight(safeBottom: safeBottom), alignment: .bottom)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .ignoresSafeArea()
      .allowsHitTesting(false)
      .accessibilityHidden(true)
      .environment(app)
      .environment(\.profileLook, look)
      .environment(\.usesGlass, usesGlass)
      .environment(\.screenLayout, screenLayout)
    }
  }
}

private struct SearchBarBand: View, Equatable {
  let height: CGFloat
  let isShown: Bool

  @Environment(\.displayScale) private var displayScale

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.height == rhs.height && lhs.isShown == rhs.isShown
  }

  var body: some View {
    if isShown {
      ZStack(alignment: .top) {
        BarBackdropBlur()
        VStack(spacing: 0) {
          LinearGradient(colors: [BrowsePalette.barBandTop, BrowsePalette.barBandBottom], startPoint: .top, endPoint: .bottom)
            .frame(height: height)
          BrowsePalette.barBandBottom
        }
        BrowsePalette.barBandEdge
          .frame(height: 1 / max(displayScale, 1))
      }
      .ignoresSafeArea()
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }
}
