import ArdiaBrowser
import ArdiaDesign
import SwiftUI

struct SearchTray<Drag: Gesture>: View {
  let request: BrowseSession.SearchRequest
  @Binding var isFocused: Bool
  let maxHeight: CGFloat
  let dismissDrag: Drag
  let pull: TrayPull
  var barLineAboveBottom: CGFloat?

  @Environment(AppModel.self) private var app
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.profileLook) private var look
  @Environment(\.displayScale) private var displayScale
  @State private var model: SearchSuggestionsModel?
  @State private var text = ""
  @State private var highlightedID: String?
  @State private var rowFrames: [String: CGRect] = [:]
  @State private var scrubTicks = 0
  @State private var scrubReleases = 0
  @State private var isScrubbing = false
  @State private var scrubStart: CGPoint?
  @State private var scrubStartTime = Date.distantPast
  @State private var rowsDrag = RowsDrag.undecided
  @State private var headerHeight: CGFloat = 0
  @State private var naturalRowsHeight: CGFloat = 0
  @State private var isSubmitting = false
  @ScaledMetric(relativeTo: .title3) private var fieldHeight = BrowseLayout.searchFieldHeight
  @ScaledMetric(relativeTo: .body) private var placeholderSize: CGFloat = 17

  private var isIncognito: Bool { app.isIncognito }
  private var isSheet: Bool { barLineAboveBottom != nil }
  private var rowsBudget: CGFloat { max(maxHeight - headerHeight, 0) }

  var body: some View {
    Group {
      if barLineAboveBottom != nil {
        sheetPanel
      } else {
        floatingPanel
      }
    }
    .environment(\.colorScheme, isIncognito ? .dark : colorScheme)
    .onAppear(perform: start)
    .onDisappear { model?.cancel() }
    .onChange(of: text) { _, newValue in
      guard !isSubmitting else { return }
      model?.update(newValue)
      highlightedID = nil
    }
    .onChange(of: app.isIncognito) { _, _ in rebuildModel() }
    .onChange(of: app.settings.isShowingOnboarding) { _, _ in isFocused = mayFocus }
    .onChange(of: app.browse.isVoicePresented) { _, _ in isFocused = mayFocus }
    .sensoryFeedback(.selection, trigger: scrubTicks)
    .sensoryFeedback(.impact(weight: .light), trigger: scrubReleases)
  }

  private var panelColumn: some View {
    VStack(spacing: 0) {
      header
      content
        .frame(maxWidth: .infinity)
        .frame(height: rowsBudget, alignment: .top)
        .clipped()
    }
    .frame(maxWidth: .infinity)
  }

  private var floatingPanel: some View {
    panelColumn
      .background { panelShape.fill(panelTint) }
      .clipShape(panelShape)
      .chromeSurface(in: panelShape, interactive: false, tinted: true)
      .shadow(color: .black.opacity(isIncognito ? 0.3 : 0.1), radius: 18, y: 4)
      .padding(.horizontal, BrowseLayout.panelInset)
      .padding(.bottom, BrowseLayout.panelAboveKeyboard)
  }

  private var sheetPanel: some View {
    panelColumn
      .background(alignment: .top) {
        sheetFill
          .padding(.bottom, -BrowseLayout.sheetOverhang)
          .allowsHitTesting(false)
      }
  }

  private var sheetFill: some View {
    let shape = UnevenRoundedRectangle(topLeadingRadius: BrowseLayout.sheetPanelRadius, topTrailingRadius: BrowseLayout.sheetPanelRadius, style: .continuous)
    return shape
      .fill(isIncognito ? SearchPanelPalette.incognitoFill : SearchPanelPalette.fill)
      .overlay { shape.stroke(SearchPanelPalette.edge, lineWidth: 1 / max(displayScale, 1)) }
  }

  private var header: some View {
    field
      .padding(.horizontal, barLineAboveBottom == nil ? BrowseLayout.panelFieldInset : BrowseLayout.sheetFieldInset)
      .padding(.top, barLineAboveBottom == nil ? BrowseLayout.panelFieldInset : BrowseLayout.sheetFieldTop)
      .padding(.bottom, isSheet ? BrowseLayout.sheetRowsGap : Spacing.hairline)
      .frame(maxWidth: .infinity)
      .contentShape(.rect)
      .highPriorityGesture(dismissDrag)
      .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
  }

  private var panelShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: BrowseLayout.panelRadius, style: .continuous)
  }

  private var panelTint: Color {
    if isIncognito { return BrowsePalette.incognitoSheet.opacity(reduceTransparency ? 1 : BrowseLayout.panelIncognitoShare) }
    return reduceTransparency ? look.surface : look.surface.opacity(BrowseLayout.panelTintShare)
  }

  private var fieldRow: some View {
    HStack(spacing: Spacing.tight) {
      OmniboxTextField(
        text: $text,
        isFocused: $isFocused,
        completion: model?.completion,
        placeholder: String(localized: "Search..."),
        isIncognito: isIncognito,
        selectsAllOnFocus: request.selectsAll,
        onPanel: isSheet,
        onSubmit: submit
      )
      .frame(maxWidth: .infinity)
      .frame(height: fieldHeight)
      .overlay(alignment: .leading) {
        if text.isEmpty, !isFocused {
          Text("Search...")
            .font(.system(size: placeholderSize))
            .foregroundStyle(isSheet ? SearchPanelPalette.placeholder : isIncognito ? Color.white.opacity(0.45) : BrowsePalette.foregroundTertiary)
            .lineLimit(1)
            .padding(.leading, CompletingTextField.horizontalInset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
      }
      .layoutPriority(1)
      fieldAccessories
        .fixedSize()
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
    .padding(.leading, isSheet ? BrowseLayout.sheetFieldLeading - CompletingTextField.horizontalInset : 18)
    .padding(.trailing, isSheet ? BrowseLayout.sheetFieldTrailing : 10)
    .frame(minHeight: fieldHeight)
  }

  @ViewBuilder
  private var fieldFill: some View {
    if isSheet {
      Capsule(style: .continuous)
        .fill(isIncognito ? SearchPanelPalette.incognitoField : SearchPanelPalette.field)
        .overlay {
          Capsule(style: .continuous)
            .strokeBorder(SearchPanelPalette.fieldEdge, lineWidth: 1 / max(displayScale, 1))
        }
    } else {
      Capsule(style: .continuous)
        .fill(isIncognito ? BrowsePalette.incognitoField : BrowsePalette.searchField)
        .overlay {
          Capsule(style: .continuous)
            .strokeBorder(isIncognito ? Color.white.opacity(0.1) : BrowsePalette.fieldStroke, lineWidth: 0.5)
        }
    }
  }

  private var field: some View {
    fieldRow.background { fieldFill }
  }

  @ViewBuilder
  private var fieldAccessories: some View {
    if !text.isEmpty {
      Button {
        text = ""
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.body)
          .foregroundStyle(isSheet ? SearchPanelPalette.accessory : isIncognito ? BrowsePalette.incognitoCaption : BrowsePalette.foregroundTertiary)
          .frame(width: 32, height: 40)
          .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Clear Text")
    } else if !dynamicTypeSize.isAccessibilitySize, !isIncognito {
      Button {
        app.browse.isVoicePresented = true
      } label: {
        Image(systemName: "mic")
          .font(.body.weight(.medium))
          .foregroundStyle(isSheet ? SearchPanelPalette.accessory : BrowsePalette.foregroundTertiary)
          .frame(width: 32, height: 40)
          .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Voice Search")
    }
    IncognitoToggle(isOn: isIncognito, tint: isSheet ? SearchPanelPalette.accessory : BrowsePalette.foregroundTertiary) {
      withAnimation(Motion.modeToggle) { app.isIncognito.toggle() }
    }
  }

  @ViewBuilder
  private var content: some View {
    let rows = model?.rows ?? []
    if isIncognito, text.isEmpty {
      Text("You’re browsing Incognito")
        .font(.title3.weight(.semibold))
        .foregroundStyle(BrowsePalette.incognitoCaption)
        .multilineTextAlignment(.center)
        .padding(.horizontal, Spacing.large)
        .frame(maxWidth: .infinity)
        .frame(height: rowsBudget)
        .contentShape(.rect)
        .gesture(dismissDrag)
        .transition(.opacity)
    } else if !rows.isEmpty, rowsBudget > 0 {
      rowsArea(rows)
        .transition(.opacity.animation(Motion.resultsIn))
    } else {
      Color.clear
        .contentShape(.rect)
        .gesture(dismissDrag)
    }
  }

  private func rowsArea(_ rows: [SearchSuggestion]) -> some View {
    let overflows = naturalRowsHeight > rowsBudget + 0.5
    return Group {
      if dynamicTypeSize.isAccessibilitySize {
        ScrollView {
          rowsColumn(rows)
        }
        .scrollDismissesKeyboard(.never)
        .scrollBounceBehavior(.basedOnSize)
      } else {
        rowsColumn(rows)
          .frame(height: rowsBudget, alignment: .top)
          .clipped()
          .mask { fadeMask(overflows: overflows) }
          .gesture(scrub(rows))
          .simultaneousGesture(rowsPull)
      }
    }
    .frame(height: rowsBudget, alignment: .top)
  }

  private func rowsColumn(_ rows: [SearchSuggestion]) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      rowStack(rows)
    }
    .padding(.bottom, Spacing.tight)
    .fixedSize(horizontal: false, vertical: true)
    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { naturalRowsHeight = $0 }
  }

  private func fadeMask(overflows: Bool) -> some View {
    LinearGradient(
      stops: [.init(color: .black, location: 0), .init(color: .black, location: overflows ? 0.7 : 1), .init(color: .black.opacity(overflows ? 0.15 : 1), location: 1)],
      startPoint: .top,
      endPoint: .bottom
    )
  }

  private func rowStack(_ rows: [SearchSuggestion]) -> some View {
    VStack(spacing: 0) {
      ForEach(rows) { suggestion in
        SuggestionRowView(
          suggestion: suggestion,
          typed: text,
          isHighlighted: highlightedID == suggestion.id,
          isIncognito: isIncognito,
          onPanel: isSheet
        )
        .gesture(TapGesture().onEnded { activate(suggestion) }, isEnabled: dynamicTypeSize.isAccessibilitySize)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("rows")) } action: { rowFrames[suggestion.id] = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { activate(suggestion) }
        .contextMenu { rowMenu(suggestion) }
      }
    }
    .padding(.horizontal, Spacing.tight)
    .coordinateSpace(.named("rows"))
  }

  @ViewBuilder
  private func rowMenu(_ suggestion: SearchSuggestion) -> some View {
    switch suggestion.kind {
    case .query:
      Button(isIncognito ? "Search in New Tab" : "Search in Incognito Tab", systemImage: isIncognito ? "plus.square.on.square" : "eyes") {
        leave()
        app.isIncognito.toggle()
        app.openSearch(suggestion.query)
      }
    case .calculation:
      if let value = suggestion.copyValue {
        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = value }
      }
    default:
      if let link = suggestion.url.flatMap(URL.init(string:)) {
        Button(isIncognito ? "Open in New Tab" : "Open in Incognito Tab", systemImage: isIncognito ? "plus.square.on.square" : "eyes") {
          openSwitchingMode(link)
        }
        Button("Copy Link", systemImage: "link") {
          app.web.copyLink(link)
          app.toasts.show(Toast(String(localized: "Copied Link"), symbol: "link"))
        }
        ShareLink(item: link) {
          Label("Share", systemImage: "square.and.arrow.up")
        }
      }
    }
  }

  private func openSwitchingMode(_ link: URL) {
    leave()
    app.isIncognito.toggle()
    app.openPage(link, origin: .typed)
  }

  private func scrub(_ rows: [SearchSuggestion]) -> some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .named("rows"))
      .onChanged { value in
        if scrubStart != value.startLocation {
          scrubStart = value.startLocation
          scrubStartTime = .now
          isScrubbing = false
          rowsDrag = .undecided
        }
        decideRowsDrag(value.translation)
        guard rowsDrag != .pull else { return }
        if abs(value.translation.height) > 6 || abs(value.translation.width) > 6 { isScrubbing = true }
        guard let hit = hitTest(value.location, rows: rows) else {
          highlightedID = nil
          return
        }
        if highlightedID != hit {
          if isScrubbing { scrubTicks += 1 }
          withAnimation(Motion.press) { highlightedID = hit }
        }
      }
      .onEnded { value in
        let wasScrubbing = isScrubbing && scrubStart == value.startLocation
        let wasPull = rowsDrag == .pull
        isScrubbing = false
        scrubStart = nil
        rowsDrag = .undecided
        let hit = hitTest(value.location, rows: rows)
        withAnimation(Motion.press) { highlightedID = nil }
        guard !wasPull, let hit, let suggestion = rows.first(where: { $0.id == hit }) else { return }
        if wasScrubbing { scrubReleases += 1 }
        activate(suggestion)
      }
  }

  /// A quick downward drag on the results pulls the tray closed, like a sheet. Scrubbing through
  /// the rows starts with a press: hold, then slide.
  private var rowsPull: some Gesture {
    DragGesture(minimumDistance: 6, coordinateSpace: .global)
      .onChanged { value in
        decideRowsDrag(value.translation)
        if rowsDrag == .pull { pull.changed(value.translation.height) }
      }
      .onEnded { value in
        if rowsDrag == .pull { pull.ended(value.translation.height, value.velocity.height) }
      }
  }

  private func decideRowsDrag(_ translation: CGSize) {
    guard rowsDrag == .undecided, abs(translation.height) > 6 || abs(translation.width) > 6 else { return }
    let quick = Date.now.timeIntervalSince(scrubStartTime) < RowsDrag.holdToScrub
    if quick, translation.height > abs(translation.width) {
      rowsDrag = .pull
      withAnimation(Motion.press) { highlightedID = nil }
    } else {
      rowsDrag = .scrub
    }
  }

  private func hitTest(_ point: CGPoint, rows: [SearchSuggestion]) -> String? {
    guard point.y <= rowsBudget else { return nil }
    return rows.first { suggestion in
      guard let frame = rowFrames[suggestion.id] else { return false }
      return frame.minY <= point.y && point.y < frame.maxY && frame.minX - 8 <= point.x && point.x <= frame.maxX + 8
    }?.id
  }

  private func start() {
    if model == nil { rebuildModel() }
    text = request.initialText
    model?.update(request.initialText)
    if mayFocus { isFocused = true }
  }

  private var mayFocus: Bool {
    !app.settings.isShowingOnboarding && !app.browse.isVoicePresented
  }

  private func rebuildModel() {
    let fresh = app.makeSuggestionsModel()
    model = fresh
    fresh.update(text)
    Task { await fresh.prepare() }
  }

  private func submit(_ value: String) {
    let model = model
    Task {
      let resolution = await model?.resolve(value)
      guard resolution != nil || SearchInput.resolve(value) != nil else { return }
      isSubmitting = true
      text = value
      leave()
      app.submitSearch(value, resolution: resolution)
    }
  }

  private func activate(_ suggestion: SearchSuggestion) {
    if case .calculation = suggestion.kind {} else { leave() }
    app.activate(suggestion)
  }

  private func leave() {
    isFocused = false
    app.browse.dismissSearch()
  }
}

/// Hands a drag that a surface has decided is a pull to the tray's dismiss handling.
struct TrayPull {
  let changed: (CGFloat) -> Void
  let ended: (_ translation: CGFloat, _ velocity: CGFloat) -> Void
}

private enum RowsDrag {
  case undecided, scrub, pull
  static let holdToScrub: TimeInterval = 0.2
}
