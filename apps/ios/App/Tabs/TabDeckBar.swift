import ArdiaDesign
import ArdiaSync
import SwiftUI

struct StartBar: View {
  let geometry: TabsDeckGeometry
  let plus: PlusActions
  let tabs: () -> Void
  let settings: () -> Void

  @Environment(\.screenLayout) private var screenLayout

  var body: some View {
    if let column = screenLayout.column {
      SideColumnStack(column: column, size: geometry.container) {
        GlassCircleButton(symbol: "square.on.square", label: "Tabs", diameter: DuoLayout.columnButton, action: tabs)
        PlusButton(actions: plus, width: DuoLayout.columnButton)
        GlassCircleButton(symbol: "gearshape", label: "Settings", diameter: DuoLayout.columnButton, action: settings)
      }
    } else {
      row
    }
  }

  private var row: some View {
    HStack(spacing: 0) {
      GlassCircleButton(symbol: "square.on.square", label: "Tabs", action: tabs)
      Spacer(minLength: TabsLayout.barGap)
      PlusButton(actions: plus, width: TabsLayout.glassPlusWidth)
      Spacer(minLength: TabsLayout.barGap)
      GlassCircleButton(symbol: "gearshape", label: "Settings", action: settings)
    }
    .padding(.horizontal, geometry.safeSide + TabsLayout.glassSideInset)
    .frame(width: geometry.container.width)
    .position(x: geometry.container.width / 2, y: geometry.barCenterY)
  }
}

struct DeckOptions {
  var isGrid: Bool
  var hasTabs: Bool
  var privateCount: Int
  var spaces: [SyncedProfile]
  var currentSpace: String?
  var toggleGrid: () -> Void
  var searchTabs: () -> Void
  var endSearch: () -> Void
  var openSynced: () -> Void
  var switchSpace: (String) -> Void
  var openArchive: () -> Void
  var openSettings: () -> Void
  var closeIncognito: () -> Void
  var closeAll: () -> Void
}

struct DeckBottomBar: View {
  let geometry: TabsDeckGeometry
  let isSearching: Bool
  @Binding var query: String
  var searchFocus: FocusState<Bool>.Binding
  let plus: PlusActions
  let options: DeckOptions

  var body: some View {
    Group {
      if isSearching {
        HStack(spacing: TabsLayout.barGap) {
          SearchTabsField(query: $query, focus: searchFocus)
          DeckBarCircle(symbol: "xmark", label: "Done Searching", action: options.endSearch)
        }
      } else {
        ZStack {
          DeckBarMenuCircle(symbol: "desktopcomputer", label: "Spaces From Your Mac", action: options.openSynced) { spacesMenu }
            .frame(maxWidth: .infinity, alignment: .leading)
          PlusButton(actions: plus, width: TabsLayout.barPlus.width, height: TabsLayout.barPlus.height, fill: TabsPalette.barCapsuleFill)
          DeckBarMenuCircle(symbol: "gearshape", label: "Settings", action: options.openSettings) { deckMenu }
            .accessibilityHint("Touch and hold for tab options.")
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
      }
    }
    .padding(.horizontal, geometry.safeSide + TabsLayout.barSideInset - (TabsLayout.barHitTarget - TabsLayout.barCircle) / 2)
  }

  @ViewBuilder
  private var spacesMenu: some View {
    if options.spaces.count > 1 {
      ForEach(options.spaces) { space in
        Button {
          options.switchSpace(space.syncId)
        } label: {
          if space.syncId == options.currentSpace {
            Label(space.name, systemImage: "checkmark")
          } else {
            Text(space.name)
          }
        }
      }
    }
    Button("Spaces From Your Mac", systemImage: "desktopcomputer", action: options.openSynced)
  }

  @ViewBuilder
  private var deckMenu: some View {
    Section {
      Button(options.isGrid ? "Show as Stack" : "Show as Grid", systemImage: options.isGrid ? "square.stack" : "square.grid.2x2", action: options.toggleGrid)
      if options.hasTabs {
        Button("Search Tabs", systemImage: "magnifyingglass", action: options.searchTabs)
      }
      Button("Archive", systemImage: "archivebox", action: options.openArchive)
    }
    Section {
      if options.privateCount > 0 {
        Button("Close Incognito Tabs", systemImage: "eyeglasses", role: .destructive, action: options.closeIncognito)
      }
      if options.hasTabs {
        Button("Close All Tabs", systemImage: "xmark", role: .destructive, action: options.closeAll)
      }
    }
    Button("Settings", systemImage: "gearshape", action: options.openSettings)
  }
}

struct DeckSearchBottomBar: View {
  let geometry: TabsDeckGeometry
  let isGrid: Bool
  @Binding var query: String
  var searchFocus: FocusState<Bool>.Binding
  let plus: PlusActions
  let toggleGrid: () -> Void

  var body: some View {
    HStack(spacing: TabsLayout.barGap) {
      GlassCircleButton(symbol: isGrid ? "square.stack" : "square.grid.2x2", label: isGrid ? "Show as Stack" : "Show as Grid", action: toggleGrid)
      SearchTabsField(query: $query, focus: searchFocus)
      PlusButton(actions: plus, width: TabsLayout.glassCircle)
    }
    .padding(.horizontal, geometry.safeSide + TabsLayout.glassSideInset)
  }
}

struct DeckPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .brightness(configuration.isPressed ? 0.12 : 0)
  }
}

struct DeckBarCircleFace: View {
  let symbol: String

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: TabsLayout.barGlyph, weight: .medium))
      .foregroundStyle(TabsPalette.barGlyph)
      .frame(width: TabsLayout.barCircle, height: TabsLayout.barCircle)
      .background(TabsPalette.barCircleFill, in: .circle)
      .frame(width: TabsLayout.barHitTarget, height: TabsLayout.barHitTarget)
      .contentShape(.circle)
  }
}

struct DeckBarCircle: View {
  let symbol: String
  let label: LocalizedStringKey
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      DeckBarCircleFace(symbol: symbol)
    }
    .buttonStyle(DeckPressStyle())
    .accessibilityLabel(label)
  }
}

struct DeckBarMenuCircle<Items: View>: View {
  let symbol: String
  let label: LocalizedStringKey
  let action: () -> Void
  @ViewBuilder let items: () -> Items

  var body: some View {
    Menu {
      items()
    } label: {
      DeckBarCircleFace(symbol: symbol)
    } primaryAction: {
      action()
    }
    .menuOrder(.fixed)
    .buttonStyle(DeckPressStyle())
    .accessibilityLabel(label)
  }
}

struct PlusActions {
  var isIncognito: Bool
  var canReopen: Bool
  var newTab: () -> Void
  var newRegularTab: () -> Void
  var newIncognitoTab: () -> Void
  var reopen: () -> Void
}

struct PlusButton: View {
  let actions: PlusActions
  let width: CGFloat
  var height = TabsLayout.glassCircle
  var fill: Color?

  var body: some View {
    Button(action: actions.newTab) {
      Image(systemName: "plus")
        .font(.system(size: TabsLayout.barPlusGlyph, weight: .medium))
        .foregroundStyle(fill == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(TabsPalette.barGlyph))
        .frame(width: width, height: height)
        .modifier(PlusSurface(fill: fill))
        .frame(height: max(height, TabsLayout.barHitTarget))
        .contentShape(.capsule)
    }
    .buttonStyle(DeckPressStyle())
    .contextMenu {
      if actions.isIncognito {
        Button("New Tab", action: actions.newRegularTab)
        Button("New Incognito Tab", action: actions.newTab)
      } else {
        Button("New Incognito Tab", action: actions.newIncognitoTab)
      }
      if actions.canReopen {
        Button("Reopen Closed Tab", action: actions.reopen)
      }
    }
    .accessibilityLabel(actions.isIncognito ? "New Incognito Tab" : "New Tab")
    .accessibilityHint("Touch and hold for more options.")
  }
}

private struct PlusSurface: ViewModifier {
  let fill: Color?

  func body(content: Content) -> some View {
    if let fill {
      content.background(fill, in: .capsule)
    } else {
      content.chromeSurface(in: .capsule)
    }
  }
}

struct GlassCircleButton: View {
  let symbol: String
  let label: LocalizedStringKey
  var diameter = TabsLayout.glassCircle
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      GlassCircleFace(symbol: symbol, diameter: diameter)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
  }
}

struct GlassCircleFace: View {
  let symbol: String
  var diameter = TabsLayout.glassCircle

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: 16, weight: .medium))
      .foregroundStyle(.primary)
      .frame(width: diameter, height: diameter)
      .contentShape(.circle)
      .chromeSurface(in: .circle)
  }
}

struct SearchTabsField: View {
  @Binding var query: String
  var focus: FocusState<Bool>.Binding

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      TextField("Search Tabs", text: $query)
        .font(.callout)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.search)
        .focused(focus)
        .accessibilityLabel("Search Tabs")
        .onSubmit { focus.wrappedValue = false }
      if !query.isEmpty {
        Button {
          query = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 19))
            .foregroundStyle(.secondary)
            .frame(width: 32, height: 32)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear Search")
      }
    }
    .padding(.leading, 13)
    .padding(.trailing, query.isEmpty ? 16 : 8)
    .frame(maxWidth: .infinity, minHeight: TabsLayout.barHitTarget)
    .contentShape(.capsule)
    .onTapGesture { focus.wrappedValue = true }
    .chromeSurface(in: .capsule)
  }
}
