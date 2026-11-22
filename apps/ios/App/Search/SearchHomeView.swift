import ArdiaBrowser
import ArdiaDesign
import ArdiaSync
import SwiftUI

struct SearchHomeView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.screenLayout) private var screenLayout

  var body: some View {
    let isTrayUp = app.browse.search != nil
    GeometryReader { proxy in
      let geometry = TabsDeckGeometry(
        container: CGSize(
          width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
          height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
        ),
        safeTop: proxy.safeAreaInsets.top,
        safeBottom: proxy.safeAreaInsets.bottom,
        safeSide: max(proxy.safeAreaInsets.leading, proxy.safeAreaInsets.trailing)
      )
      ZStack {
        backdrop
          .ignoresSafeArea()
        StartSpaces(geometry: spacesGeometry(geometry))
          .frame(width: geometry.container.width, alignment: screenLayout.column?.edge == .leading ? .trailing : .leading)
          .opacity(isTrayUp ? 0 : 1)
          .scaleEffect(isTrayUp && !reduceMotion ? 0.96 : 1)
          .allowsHitTesting(!isTrayUp)
          .ignoresSafeArea()
        bar(geometry)
          .opacity(isTrayUp ? 0 : 1)
          .allowsHitTesting(!isTrayUp)
          .ignoresSafeArea()
      }
    }
    .ignoresSafeArea(.keyboard)
    .animation(reduceMotion ? .easeOut(duration: 0.2) : Motion.searchRise, value: isTrayUp)
    .accessibilityHidden(isTrayUp)
    .preferredColorScheme(app.isIncognito ? .dark : nil)
    .task {
      await SearchSuggestionsModel.loadRecents(from: app.tabs)
      openTrayIfWanted()
    }
    .onChange(of: app.settings.isShowingOnboarding) { _, showing in
      if !showing { openTrayIfWanted() }
    }
  }

  private func spacesGeometry(_ geometry: TabsDeckGeometry) -> TabsDeckGeometry {
    guard let column = screenLayout.column else { return geometry }
    return TabsDeckGeometry(
      container: CGSize(width: column.contentWidth(in: geometry.container.width), height: geometry.container.height),
      safeTop: geometry.safeTop,
      safeBottom: geometry.safeBottom
    )
  }

  private func openTrayIfWanted() {
    guard app.settings.autoOpensKeyboard, !app.settings.isShowingOnboarding, app.browse.search == nil, app.sheet == nil else { return }
    app.browse.presentSearch(from: .home, incognitoOnCancel: app.isIncognito)
  }

  @ViewBuilder
  private func bar(_ geometry: TabsDeckGeometry) -> some View {
    if screenLayout.column == nil {
      StartPageBar(
        safeBottom: geometry.safeBottom,
        sideInset: geometry.safeSide,
        plus: plusActions,
        tabs: { app.showTabSwitcher() },
        settings: { app.sheet = .settings }
      )
      .frame(width: geometry.container.width, height: geometry.container.height, alignment: .bottom)
    } else {
      columnBar(geometry)
    }
  }

  private var plusActions: PlusActions {
    PlusActions(
      isIncognito: app.isIncognito,
      canReopen: app.tabs.canReopenClosed,
      newTab: { app.newTab() },
      newRegularTab: { app.newRegularTab() },
      newIncognitoTab: { app.newIncognitoTab() },
      reopen: { app.reopenLastClosed() }
    )
  }

  private func columnBar(_ geometry: TabsDeckGeometry) -> some View {
    StartBar(
      geometry: geometry,
      plus: PlusActions(
        isIncognito: app.isIncognito,
        canReopen: app.tabs.canReopenClosed,
        newTab: { app.newTab() },
        newRegularTab: { app.newRegularTab() },
        newIncognitoTab: { app.newIncognitoTab() },
        reopen: { app.reopenLastClosed() }
      ),
      tabs: { app.showTabSwitcher() },
      settings: { app.sheet = .settings }
    )
  }

  @ViewBuilder
  private var backdrop: some View {
    if app.isIncognito {
      ProfileBackdrop(look: .incognito)
    } else {
      ProfileBackdrop(themed: true)
    }
  }
}

struct StartSpaces: View {
  let geometry: TabsDeckGeometry
  @Environment(AppModel.self) private var app
  @Environment(\.screenLayout) private var screenLayout
  @State private var page: String?

  var body: some View {
    let spaces = app.spaces
    ZStack {
      if spaces.count > 1 {
        TabView(selection: $page) {
          ForEach(spaces) { space in
            StartSpacePage(geometry: geometry, space: space, spaces: spaces)
              .ignoresSafeArea()
              .tag(Optional(space.syncId))
          }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        SpacePageDots(count: spaces.count, index: spaces.firstIndex { $0.syncId == app.currentSpace?.syncId } ?? 0)
          .position(x: geometry.container.width / 2, y: screenLayout.column == nil ? geometry.barCenterY - TabsLayout.pageDotsAboveBar : geometry.barCenterY)
      } else if let space = spaces.first {
        StartSpacePage(geometry: geometry, space: space, spaces: spaces)
      } else {
        StartWelcome()
          .frame(width: geometry.container.width - 2 * (geometry.safeSide + StartLayout.side))
          .position(x: geometry.container.width / 2, y: geometry.container.height * StartLayout.centerShare)
      }
    }
    .frame(width: geometry.container.width, height: geometry.container.height)
    .onAppear { page = app.currentSpace?.syncId }
    .onChange(of: app.currentSpace?.syncId) { _, id in
      if page != id { page = id }
    }
    .onChange(of: page) { _, id in
      if let id { app.switchSpace(to: id) }
    }
    .sensoryFeedback(.selection, trigger: app.currentSpace?.syncId)
  }
}

struct StartSpacePage: View {
  let geometry: TabsDeckGeometry
  let space: SyncedProfile
  let spaces: [SyncedProfile]
  @Environment(AppModel.self) private var app

  var body: some View {
    let switcherY = geometry.container.height * TabsLayout.startSwitcherRatio
    ZStack(alignment: .top) {
      Color.clear
      SpaceSwitcher(spaces: spaces, current: space) { app.switchSpace(to: $0) }
        .position(x: geometry.container.width / 2, y: switcherY)
      if !space.pinned.tiles.isEmpty {
        PinnedTiles(tiles: space.pinned.tiles) { url, title in app.openPinned(url: url, title: title) }
          .padding(.horizontal, geometry.safeSide + TabsLayout.tileSide)
          .frame(width: geometry.container.width)
          .offset(y: switcherY + TabsLayout.startTilesGap)
      }
    }
    .frame(width: geometry.container.width, height: geometry.container.height)
    .contentShape(.rect)
  }
}

struct StartWelcome: View {
  @Environment(AppModel.self) private var app
  @Environment(\.openURL) private var openURL

  var body: some View {
    VStack(spacing: 0) {
      mark
        .padding(.bottom, StartLayout.markGap)
      Text(title)
        .font(.body.weight(.semibold))
        .foregroundStyle(StartPalette.title)
        .multilineTextAlignment(.center)
        .padding(.bottom, StartLayout.titleGap)
      Text(detail)
        .font(.subheadline)
        .foregroundStyle(StartPalette.detail)
        .multilineTextAlignment(.center)
        .padding(.bottom, action == nil ? 0 : StartLayout.buttonGap)
      if let action {
        Button(action: action.run) {
          Text(action.title)
            .font(.body.weight(.medium))
            .foregroundStyle(StartPalette.title)
            .padding(.horizontal, StartLayout.buttonPadding)
            .frame(minHeight: StartLayout.buttonHeight)
            .background(StartPalette.button, in: .rect(cornerRadius: StartLayout.buttonRadius, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(PageMenuPressStyle())
      }
    }
  }

  @ViewBuilder
  private var mark: some View {
    if app.isIncognito {
      Image(systemName: "eyeglasses")
        .font(.system(size: StartLayout.eyes, weight: .semibold))
        .foregroundStyle(.white.opacity(0.85))
        .frame(width: StartLayout.mark, height: StartLayout.mark)
        .accessibilityHidden(true)
    } else {
      AppIconPreview(side: StartLayout.mark)
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
    }
  }

  private var title: LocalizedStringKey {
    if app.isIncognito { return "You’re browsing Incognito" }
    if !app.defaultBrowser.isDefault { return "Want links to open in Ardia?" }
    if app.sync.phase == .off { return "Bring your Mac’s tabs along" }
    return "No open tabs"
  }

  private var detail: LocalizedStringKey {
    if app.isIncognito { return "Incognito tabs aren’t saved to your history or your Archive." }
    if !app.defaultBrowser.isDefault { return "Make Ardia your default browser and every link you tap opens here." }
    if app.sync.phase == .off { return "Sync with Ardia on your Mac to see its spaces and pinned sites here." }
    return "Tap + to search or type an address."
  }

  private struct StartAction {
    let title: LocalizedStringKey
    let run: () -> Void
  }

  private var action: StartAction? {
    if app.isIncognito { return nil }
    if !app.defaultBrowser.isDefault {
      return StartAction(title: "Set Ardia as Default Browser") {
        app.defaultBrowser.willOpenSystemSettings()
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
      }
    }
    if app.sync.phase == .off {
      return StartAction(title: "Sync With Your Mac") { app.sheet = .syncSetup }
    }
    return nil
  }
}

struct StartPageBar: View {
  let safeBottom: CGFloat
  var sideInset: CGFloat = 0
  let plus: PlusActions
  let tabs: () -> Void
  let settings: () -> Void

  var body: some View {
    ZStack {
      BarTabsStackButton(actions: BarActions(
        onTabs: tabs,
        onAddress: {},
        onPlus: plus.newTab,
        onMore: settings,
        onExpand: {},
        onStep: { _ in },
        onSelectTab: { _ in },
        onCloseTab: {}
      ))
      .frame(maxWidth: .infinity, alignment: .leading)
      BarPlusCapsule(action: plus.newTab)
        .contextMenu {
          if plus.isIncognito {
            Button("New Tab", action: plus.newRegularTab)
            Button("New Incognito Tab", action: plus.newTab)
          } else {
            Button("New Incognito Tab", action: plus.newIncognitoTab)
          }
          if plus.canReopen {
            Button("Reopen Closed Tab", action: plus.reopen)
          }
        }
        .accessibilityLabel(plus.isIncognito ? "New Incognito Tab" : "New Tab")
      BarCircleButton(symbol: "gearshape", label: "Settings", action: settings)
        .padding(.trailing, BrowseLayout.barSide - (BrowseLayout.hitTarget - BrowseLayout.barCircle) / 2)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .frame(height: BrowseLayout.barControl)
    .padding(.horizontal, sideInset)
    .padding(.bottom, BrowseLayout.barLine(safeBottom: safeBottom) - BrowseLayout.barControl / 2)
    .frame(maxWidth: .infinity)
    .background(alignment: .bottom) {
      BarBand(height: BrowseLayout.barHeight(safeBottom: safeBottom))
    }
  }
}

enum StartLayout {
  static let mark: CGFloat = 128
  static let eyes: CGFloat = 64
  static let markGap: CGFloat = 36
  static let titleGap: CGFloat = 8
  static let buttonGap: CGFloat = 20
  static let buttonHeight: CGFloat = 34
  static let buttonRadius: CGFloat = 10
  static let buttonPadding: CGFloat = 12
  static let side: CGFloat = 40
  static let centerShare: CGFloat = 0.6
}

enum StartPalette {
  static let title = Color.primary
  static let detail = Color.adaptive(light: .black.opacity(0.5), dark: .white.opacity(0.45))
  static let button = Color.adaptive(light: .black.opacity(0.07), dark: .white.opacity(0.14))
}

#Preview("Start") {
  SearchHomeView()
    .environment(AppModel(isDemo: true))
}
