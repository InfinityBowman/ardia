import ArdiaBrowser
import ArdiaDesign
import SwiftUI
import UIKit

struct BrowsingView: View {
  var isFront = true

  @Environment(AppModel.self) private var app
  @Environment(\.profileLook) private var look
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var pager = TabPager()
  @State private var barVisibility = BottomBarVisibility()
  @State private var pageSpan = PageSpan(width: 402, safeSide: 0)
  @State private var homeInset: CGFloat = 34
  @State private var barLink = BarScrollLink()
  @State private var storedCover: StoredCover?
  @Environment(\.screenLayout) private var screenLayout
  @Environment(\.usesGlass) private var usesGlass

  var body: some View {
    @Bindable var browse = app.browse
    let tab = app.tabs.selectedTab
    ZStack(alignment: .bottom) {
      Rectangle().fill(screenLayout.column == nil ? AnyShapeStyle(look.surface) : AnyShapeStyle(.background)).ignoresSafeArea()
      if let tab {
        pageLayer(tab)
          .overlay(alignment: .top) { statusStrip(tab) }
          .padding(columnEdge, screenLayout.column?.contentReserve ?? 0)
          .ignoresSafeArea()
      }
      TabPagerStageHost(pager: pager, app: app)
        .ignoresSafeArea()
        .accessibilityHidden(true)
      Color.clear
        .ignoresSafeArea(.keyboard)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { homeInset = $0 }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      if let column = screenLayout.column {
        columnBar(column)
      } else if screenLayout == .phone {
        bar
      }
    }
    .overlay(alignment: .top) {
      if let page = currentWebPage {
        LoadingLine(progress: MotionDemo.loadFreeze ?? page.progress, isLoading: MotionDemo.loadFreeze != nil || page.isLoading)
          .id(page.id)
          .ignoresSafeArea(edges: .horizontal)
      }
    }
    .onGeometryChange(for: PageSpan.self) { proxy in
      let insets = proxy.safeAreaInsets
      return PageSpan(width: proxy.size.width + insets.leading + insets.trailing, safeSide: max(insets.leading, insets.trailing))
    } action: { pageSpan = $0 }
    .modifier(PageRequestAlert(page: currentWebPage))
    .sheet(isPresented: $browse.isToolbarPresented) {
      if let id = app.tabs.selectedTabID {
        ToolbarSheet(tabID: id)
      }
    }
    .sheet(item: Binding(get: { app.web.shareRequest }, set: { app.web.shareRequest = $0 })) { url in
      ActivitySheet(url: url)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .ignoresSafeArea()
    }
    .fullScreenCover(item: Binding(get: { browse.readerTabID.map(ReaderTarget.init) }, set: { browse.readerTabID = $0?.id })) { target in
      ReaderView(tabID: target.id)
    }
    .onChange(of: browse.deckRequested) { _, requested in
      guard requested else { return }
      browse.deckRequested = false
      openDeck()
    }
    .onChange(of: browse.stepRequest) { _, request in
      guard let request else { return }
      browse.stepRequest = nil
      stepTab(request.delta)
    }
    .onChange(of: app.settings.collapsesBottomBar, initial: true) { _, collapses in
      barLink.isEnabled = collapses
    }
    .task { await collapseBarForDemo() }
    .onChange(of: isFindingInPage) { _, active in
      barVisibility.findSessionChanged(isActive: active)
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
      barVisibility.keyboardWillShow()
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
      barVisibility.keyboardDidHide()
    }
    .onChange(of: app.tabs.selectedTabID, initial: true) { _, id in
      barVisibility.expand()
      barLink.show(animated: false)
      app.goBackToSearchIfEmpty()
      if let id { _ = app.web.webTab(for: id) }
      pager.selectionChanged()
    }
    .task { await pager.runDemoFreeze() }
    .task { await pager.runDemoScript() }
    .onChange(of: isFront) { _, front in
      if front {
        barVisibility.expand()
        barLink.show(animated: false)
      }
    }
    .onChange(of: findScope) { old, _ in
      endFindInPage(on: old.tabID)
    }
    .onDisappear {
      endFindInPage(on: app.tabs.selectedTabID)
    }
    .toolbarColorScheme(isFront ? statusScheme : nil, for: .statusBar)
    .accessibilityHidden(!isFront)
  }


  private var isFindingInPage: Bool {
    currentWebPage?.isFindingInPage ?? false
  }

  private var findScope: FindScope {
    FindScope(
      tabID: app.tabs.selectedTabID,
      pageIsFront: isFront && app.browse.readerTabID == nil && app.browse.search == nil && !app.browse.isVoicePresented
    )
  }

  private func endFindInPage(on id: UUID?) {
    guard let id else { return }
    app.web.existingWebTab(id)?.dismissFindInPage()
  }

  private var tone: PageTone? {
    guard let tab = app.tabs.selectedTab else { return nil }
    return app.browse.tone(for: tab, page: currentWebPage)
  }

  private var statusScheme: ColorScheme? {
    guard app.browse.search == nil else { return nil }
    return tone?.top?.scheme
  }

  @ViewBuilder
  private func statusStrip(_ tab: BrowserTab) -> some View {
    if let top = tone?.top {
      Color.clear
        .frame(height: 0)
        .background(alignment: .top) {
          top.color
            .ignoresSafeArea(edges: .top)
            .animation(.easeOut(duration: 0.25), value: top)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
  }

  private var currentWebPage: WebTab? {
    app.currentPage
  }

  @ViewBuilder
  private func pageLayer(_ tab: BrowserTab) -> some View {
    let page = app.web.existingWebTab(tab.id)
    let browse = app.browse
    ZStack {
      WebPageView(
        page: page,
        tab: tab,
        cover: cover(for: tab),
        swipeMode: app.preferences.swipeNavigation,
        topInset: screenLayout.isWide || screenLayout.fold != nil ? DuoLayout.toolbarClearance : 0,
        bottomInset: screenLayout == .phone ? BrowseLayout.barHeight(safeBottom: homeInset) : 0,
        barLink: screenLayout == .phone ? barLink : nil,
        onTone: { id, tone in browse.setTone(tone, for: id) }
      )
      if MotionDemo.loadFreeze != nil {
        PageLoadingPlaceholder(tab: tab, backdrop: look.surface, revealDelay: Motion.placeholderDelay)
      }
      if let failure = page?.failure, let page {
        PageFailureView(failure: failure) { page.reload() }
          .transition(.opacity)
      }
    }
    .task(id: tab.id) { await loadStoredCover(for: tab) }
  }

  private func cover(for tab: BrowserTab) -> UIImage? {
    if let image = app.browse.covers.image(for: tab.id) ?? app.deck.memoryImage(for: tab.id) { return image }
    if storedCover?.id == tab.id, let image = storedCover?.image { return image }
    // A thumbnail already decoded in memory beats a title card while the stored cover loads.
    return tab.snapshotFileName.flatMap(app.web.snapshots.cachedImage(named:)).map { UIImage(cgImage: $0) }
  }

  private func loadStoredCover(for tab: BrowserTab) async {
    guard app.browse.covers.image(for: tab.id) == nil, app.deck.memoryImage(for: tab.id) == nil,
          let name = tab.snapshotFileName, let image = await app.web.snapshots.image(named: name) else { return }
    storedCover = StoredCover(id: tab.id, image: UIImage(cgImage: image))
  }

  private func openDeck() {
    HarnessProbe.mark("tabs.tap")
    app.browse.thawOrder()
    // One capture serves the page cover, the deck's zoom-out handoff and the saved thumbnail.
    // It used to be drawn twice on the main thread (and written to disk twice) on every tap.
    if app.usesDeckStage {
      app.showTabSwitcher()
    } else {
      app.showTabSwitcher(handoff: rememberCurrentCover())
    }
  }

  @discardableResult
  private func rememberCurrentCover() -> UIImage? {
    guard let id = app.tabs.selectedTabID, let page = app.web.existingWebTab(id), !page.isLoading, page.failure == nil,
          let webView = page.webView, let image = PageCoverCache.capture(webView) else { return nil }
    app.browse.covers.store(image, for: id)
    return image
  }

  private var barActions: BarActions {
    BarActions(
      onTabs: { pager.landNow(); openDeck() },
      onAddress: { pager.landNow(); editAddress() },
      onPlus: { pager.landNow(); openSearch() },
      onMore: { pager.landNow(); app.browse.isToolbarPresented = true },
      onExpand: { withAnimation(barMotion) { barVisibility.expand() } },
      onStep: stepTab,
      onSelectTab: { id in switchTab(to: id, order: app.swipeOrder) },
      onCloseTab: closeCurrentTab
    )
  }

  private var columnEdge: Edge.Set {
    screenLayout.column?.edge == .leading ? .leading : .trailing
  }

  private func columnBar(_ column: ScreenLayout.SideColumn) -> some View {
    GeometryReader { proxy in
      let insets = proxy.safeAreaInsets
      BottomBar(
        address: BarAddress(tab: app.tabs.selectedTab, page: currentWebPage),
        arrangement: .column(column, CGSize(width: proxy.size.width + insets.leading + insets.trailing, height: proxy.size.height + insets.top + insets.bottom)),
        actions: barActions
      )
      .ignoresSafeArea()
    }
    .opacity(isBarShown ? 1 : 0)
    .allowsHitTesting(isBarShown)
    .animation(barMotion, value: isBarShown)
    .ignoresSafeArea(.keyboard)
  }

  private var bar: some View {
    let height = BrowseLayout.barHeight(safeBottom: homeInset)
    let content = BottomBar(
      address: BarAddress(tab: app.tabs.selectedTab, page: currentWebPage),
      sideInset: pageSpan.safeSide,
      safeBottom: homeInset,
      pageColor: tone?.bottom?.color,
      actions: barActions
    )
    .frame(height: height + BrowseLayout.barFade, alignment: .bottom)
    .environment(app)
    .environment(\.profileLook, look)
    .environment(\.usesGlass, usesGlass)
    .environment(\.screenLayout, screenLayout)
    .environment(\.colorScheme, barScheme)
    barLink.onSwipeUp = { pager.landNow(); openSearch() }
    return PageBarHost(link: barLink, pager: pager, fade: BrowseLayout.barFade, content: content)
      .frame(height: height + BrowseLayout.barFade)
      .offset(y: isRowBarShown ? 0 : height + BrowseLayout.barFade)
      .opacity(isRowBarShown ? 1 : 0)
      .allowsHitTesting(isRowBarShown)
      .animation(barMotion, value: isRowBarShown)
      .frame(maxHeight: .infinity, alignment: .bottom)
      .ignoresSafeArea(.container, edges: [.bottom, .horizontal])
      .ignoresSafeArea(.keyboard)
  }

  private var barMotion: Animation {
    reduceMotion ? .easeOut(duration: 0.2) : Motion.barCollapse
  }

  private var barPresentation: BottomBarVisibility.Presentation {
    // The bar stays put while the search tray is up: the tray and keyboard cover it, and it is
    // live the instant search closes instead of fading back in after the keyboard has gone.
    barVisibility.presentation
  }

  private var isBarShown: Bool {
    barPresentation != .hidden
  }

  private var isRowBarShown: Bool {
    barPresentation != .hidden
  }

  private func editAddress() {
    guard let tab = app.tabs.selectedTab else { return }
    app.browse.presentSearch(from: .page, text: app.currentQuery(for: tab), selectsAll: true)
  }

  private func collapseBarForDemo() async {
    guard ProcessInfo.processInfo.arguments.contains("-BrowseCollapsed") else { return }
    try? await Task.sleep(for: .seconds(MotionDemo.delay))
    barLink.hide()
  }

  @Environment(\.colorScheme) private var systemScheme

  private var barScheme: ColorScheme {
    tone?.bottom?.scheme ?? systemScheme
  }

  private func openSearch() {
    app.newTab()
  }

  private func switchTab(to id: UUID, order: [BrowserTab]) {
    rememberCurrentCover()
    app.browse.freezeOrder(order.map(\.id))
    app.openTab(id)
  }

  private func closeCurrentTab() {
    guard let id = app.tabs.selectedTabID else { return }
    app.closeTab(id)
  }

  private func stepTab(_ delta: Int) {
    let order = app.swipeOrder
    guard let index = order.firstIndex(where: { $0.id == app.tabs.selectedTabID }), order.indices.contains(index + delta) else { return }
    switchTab(to: order[index + delta].id, order: order)
  }
}

nonisolated struct PageSpan: Equatable {
  let width: CGFloat
  let safeSide: CGFloat
}

struct StoredCover {
  let id: UUID
  let image: UIImage
}

struct FindScope: Equatable {
  let tabID: UUID?
  let pageIsFront: Bool
}

struct ReaderTarget: Identifiable {
  let id: UUID
}
