import ArdiaBrowser
import ArdiaDesign
import SwiftUI
import UIKit

@MainActor
@Observable
final class DeckStageModel {
  var geometry = TabsDeckGeometry(container: CGSize(width: 402, height: 874), safeTop: 62, safeBottom: 34)
  var query = ""
  var isEmpty = false
  var isShowingArchiveCard = false
  var isConfirmingCloseAll = false
  var isConfirmingCloseIncognito = false
  var keyboardOverlap: CGFloat = 0
  var blurSearch = 0
  var gridScroll = 0
  var isPresented = false
  var isSearching = false

  static let archiveCardGap: CGFloat = 8

  static func barCenterY(_ geometry: TabsDeckGeometry, keyboardOverlap: CGFloat) -> CGFloat {
    guard keyboardOverlap > 0 else { return geometry.barCenterY }
    return geometry.container.height - keyboardOverlap - TabsLayout.barGap - TabsLayout.barHitTarget / 2
  }

  static func archiveCardCenterY(_ geometry: TabsDeckGeometry) -> CGFloat {
    geometry.barCenterY - TabsLayout.barCircle / 2 - archiveCardGap - TabsLayout.archiveCardHeight / 2
  }

  func set<Value: Equatable>(_ key: ReferenceWritableKeyPath<DeckStageModel, Value>, _ value: Value) {
    if self[keyPath: key] != value { self[keyPath: key] = value }
  }

  @ObservationIgnored var toggleGrid: () -> Void = {}
  @ObservationIgnored var openFromGrid: (UUID) -> Void = { _ in }
  @ObservationIgnored var closeFromGrid: (UUID) -> Void = { _ in }
  @ObservationIgnored var dismissArchiveCard: () -> Void = {}
  @ObservationIgnored var closeAll: () -> Void = {}
}

struct DeckStageEnvironment: Equatable {
  var look: ProfileLook
  var usesGlass: Bool
  var screenLayout: ScreenLayout
}

extension View {
  func deckStageEnvironment(_ app: AppModel, _ environment: DeckStageEnvironment) -> some View {
    self
      .environment(app)
      .environment(\.profileLook, environment.look)
      .environment(\.usesGlass, environment.usesGlass)
      .environment(\.screenLayout, environment.screenLayout)
  }
}

struct DeckStageTopChrome: View {
  @Bindable var stage: DeckStageModel
  @Environment(AppModel.self) private var app

  var body: some View {
    let geometry = stage.geometry
    ZStack {
      if stage.isEmpty {
        DeckEmptyState(geometry: geometry, isSearching: !trimmedQuery.isEmpty, showsArchive: app.hasArchivedTabs) { app.openArchive() }
          .transition(.opacity)
      }
      if stage.isShowingArchiveCard, !app.deck.isGrid {
        ArchiveIntervalCard(interval: Bindable(app.tabs).autoArchiveInterval) { stage.dismissArchiveCard() }
          .padding(.horizontal, geometry.safeSide + TabsLayout.headerSide)
          .frame(width: geometry.container.width)
          .position(x: geometry.container.width / 2, y: DeckStageModel.archiveCardCenterY(geometry))
      }
    }
    .frame(width: geometry.container.width, height: geometry.container.height)
    .accessibilityHidden(!stage.isPresented)
    .confirmationDialog(closeAllTitle, isPresented: $stage.isConfirmingCloseAll, titleVisibility: .visible) {
      Button(app.deckTabs.count == 1 ? String(localized: "Close Tab") : String(localized: "Close All Tabs"), role: .destructive) { stage.closeAll() }
    } message: {
      Text(app.tabs.privateTabs.isEmpty ? "They’ll stay in your Archive." : "Incognito tabs aren’t saved. Other tabs stay in your Archive.")
    }
    .confirmationDialog("Close Incognito Tabs?", isPresented: $stage.isConfirmingCloseIncognito, titleVisibility: .visible) {
      Button("Close Incognito Tabs", role: .destructive) { app.leaveIncognito() }
    } message: {
      Text("Their pages, cookies and history are cleared.")
    }
  }

  private var trimmedQuery: String { stage.query.trimmingCharacters(in: .whitespacesAndNewlines) }

  private var closeAllTitle: String {
    app.deckTabs.count == 1 ? String(localized: "Close 1 Tab?") : String(localized: "Close \(app.deckTabs.count) Tabs?")
  }
}

struct DeckStageGrid: View {
  let stage: DeckStageModel
  @Environment(AppModel.self) private var app

  var body: some View {
    let geometry = stage.geometry
    TabGridView(
      tabs: gridTabs,
      selectedID: app.tabs.selectedTabID,
      cardAspect: geometry.container.width / max(geometry.container.height, 1),
      topInset: geometry.safeTop + 8,
      bottomInset: geometry.container.height - geometry.barCenterY + TabsLayout.barHitTarget / 2 + 8,
      sideInset: geometry.safeSide + TabsLayout.headerSide + 4,
      memoryImage: { app.browse.covers.image(for: $0) },
      snapshots: app.web.snapshots,
      open: { stage.openFromGrid($0) },
      close: { stage.closeFromGrid($0) },
      scrollToken: stage.gridScroll
    )
    .frame(width: geometry.container.width, height: geometry.container.height)
    .accessibilityHidden(!stage.isPresented || !app.deck.isGrid)
  }

  private var gridTabs: [BrowserTab] {
    let needle = stage.query.trimmingCharacters(in: .whitespacesAndNewlines)
    let ordered = app.deckOrder
    guard !needle.isEmpty else { return ordered }
    return ordered.filter { TabText.matches($0, needle) }
  }
}

struct DeckStageBar: View {
  let stage: DeckStageModel

  var body: some View {
    DeckStageBarContent(stage: stage)
      .accessibilityHidden(!stage.isPresented)
  }
}

struct DeckSearchBlurDriver: View {
  let stage: DeckStageModel
  var focus: FocusState<Bool>.Binding

  var body: some View {
    Color.clear
      .allowsHitTesting(false)
      .accessibilityHidden(true)
      .onChange(of: stage.blurSearch) {
        focus.wrappedValue = false
        if stage.query.isEmpty { stage.isSearching = false }
      }
  }
}

struct DeckStageBarContent: View {
  @Bindable var stage: DeckStageModel
  @Environment(AppModel.self) private var app
  @FocusState private var isSearchFocused: Bool

  var body: some View {
    let geometry = stage.geometry
    ZStack(alignment: .bottom) {
      DeckBottomBar(
        geometry: geometry,
        isSearching: stage.isSearching,
        query: $stage.query,
        searchFocus: $isSearchFocused,
        plus: PlusActions(
          isIncognito: app.isIncognito,
          canReopen: app.tabs.canReopenClosed,
          newTab: { app.newTab() },
          newRegularTab: { app.newRegularTab() },
          newIncognitoTab: { app.newIncognitoTab() },
          reopen: { app.reopenLastClosed() }
        ),
        options: DeckOptions(
          isGrid: app.deck.isGrid,
          hasTabs: !app.deckTabs.isEmpty,
          privateCount: app.tabs.privateTabs.count,
          spaces: app.spaces,
          currentSpace: app.currentSpace?.syncId,
          toggleGrid: stage.toggleGrid,
          searchTabs: { stage.isSearching = true },
          endSearch: {
            stage.query = ""
            isSearchFocused = false
            stage.isSearching = false
          },
          openSynced: {
            if app.sync.phase == .off {
              app.sheet = .syncSetup
            } else {
              app.openSyncedSpaces()
            }
          },
          switchSpace: { app.switchSpace(to: $0) },
          openArchive: { app.openArchive() },
          openSettings: { app.sheet = .settings },
          closeIncognito: { stage.isConfirmingCloseIncognito = true },
          closeAll: { stage.isConfirmingCloseAll = true }
        )
      )
      .frame(width: geometry.container.width)
      .position(x: geometry.container.width / 2, y: DeckStageModel.barCenterY(geometry, keyboardOverlap: stage.keyboardOverlap))
    }
    .frame(width: geometry.container.width, height: geometry.container.height)
    .background { DeckSearchBlurDriver(stage: stage, focus: $isSearchFocused) }
    .onChange(of: stage.isSearching) { _, searching in
      if searching { isSearchFocused = true }
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
      guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
      withAnimation(.smooth(duration: 0.3)) { stage.keyboardOverlap = max(0, geometry.container.height - frame.minY) }
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
      withAnimation(.smooth(duration: 0.3)) { stage.keyboardOverlap = 0 }
    }
  }
}

struct PageBarStandIn: View {
  let stage: DeckStageModel
  @Environment(AppModel.self) private var app

  var body: some View {
    let tab = app.tabs.selectedTab
    let page = app.currentPage
    BottomBar(
      address: BarAddress(tab: tab, page: page),
      sideInset: stage.geometry.safeSide,
      safeBottom: stage.geometry.safeBottom,
      actions: BarActions(onTabs: {}, onAddress: {}, onPlus: {}, onMore: {}, onExpand: {}, onStep: { _ in }, onSelectTab: { _ in }, onCloseTab: {})
    )
    .frame(maxHeight: .infinity, alignment: .bottom)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

struct DeckStageHost: UIViewControllerRepresentable {
  let surface: AppModel.Surface
  @Environment(AppModel.self) private var app
  @Environment(\.profileLook) private var look
  @Environment(\.usesGlass) private var usesGlass
  @Environment(\.screenLayout) private var screenLayout

  func makeUIViewController(context: Context) -> DeckStageController {
    app.usesDeckStage = true
    let controller = DeckStageController(app: app)
    app.deckStage = controller
    Task { @MainActor [weak controller] in
      try? await Task.sleep(for: .seconds(1.5))
      controller?.prewarm()
    }
    return controller
  }

  func updateUIViewController(_ controller: DeckStageController, context: Context) {
    controller.environment = DeckStageEnvironment(look: look, usesGlass: usesGlass, screenLayout: screenLayout)
    controller.surfaceChanged(surface)
  }

  static func dismantleUIViewController(_ controller: DeckStageController, coordinator: ()) {
    controller.app.usesDeckStage = false
  }
}
