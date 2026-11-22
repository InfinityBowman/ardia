import ArdiaBrowser
import ArdiaDesign
import ArdiaSync
import SwiftUI

struct ToolbarSheet: View {
  let tabID: UUID
  var panelMaxHeight: CGFloat?
  var onClose: (() -> Void)?

  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.pageMenuRise) private var rise
  @State private var copies = 0
  @State private var confirmsTranslation = false
  @State private var contentHeight: CGFloat = 560
  @State private var bottomInset: CGFloat = 0
  @State private var windowRoom: CGFloat = .greatestFiniteMagnitude
  @State private var followUp: PageMenuFollowUp?
  @State private var showsDisplay = false
  @State private var showsMore = false
  @ScaledMetric(relativeTo: .body) private var capsuleHeight: CGFloat = PageMenuLayout.addressHeight
  @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = PageMenuLayout.tile

  private var tab: BrowserTab? { app.tabs.tab(tabID) }
  private var page: WebTab? { app.web.existingWebTab(tabID) }
  private var isWebPage: Bool { tab.map { BrowserURL.isSyncable($0.url) } ?? false }

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        VStack(spacing: PageMenuLayout.barSpacing) {
          navigationCapsule
          actionButtons
        }
        VStack(spacing: PageMenuLayout.groupSpacing) {
          PageMenuGroup {
            PageMenuDisclosureRow(title: "Display Options", isExpanded: $showsDisplay)
            if showsDisplay, let page {
              nightShadeRow(page)
              zoomRow(page)
              desktopRow(page)
              translateRow
            }
          }
          PageMenuGroup {
            PageMenuRow("Site Settings") { close(then: .siteSettings) }
          }
          if let page {
            PageMenuGroup {
              blockingRow(page)
            }
          }
          PageMenuGroup {
            PageMenuDisclosureRow(title: "More", isExpanded: $showsMore)
            if showsMore {
              sendRow
              printRow
              PageMenuRow("History") { close(then: .sheet(.history)) }
              PageMenuRow("Bookmarks") { close(then: .sheet(.bookmarks)) }
              PageMenuRow("Downloads") { close(then: .sheet(.downloads)) }
              if let page, !app.defaultBrowser.isDefault {
                PageMenuRow("Open in Default Browser") {
                  app.openInDefaultBrowser(page)
                  leave()
                }
              }
            }
          }
        }
        .padding(.top, PageMenuLayout.groupSpacing)
      }
      .padding(PageMenuLayout.inset)
      .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? Spacing.large : 0)
    }
    .scrollBounceBehavior(.basedOnSize)
    .scrollDisabled(panelMaxHeight.map { contentHeight <= $0 } ?? false)
    .frame(height: panelMaxHeight.map { min(contentHeight, $0) })
    .ignoresSafeArea(.container, edges: .bottom)
    .onScrollGeometryChange(for: CGFloat.self) { geometry in
      geometry.contentSize.height + geometry.contentInsets.top
    } action: { _, height in
      contentHeight = height.rounded(.up)
    }
    .background {
      Color.clear.onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
      WindowRoomReader { windowRoom = $0 }
        .accessibilityHidden(true)
    }
    .tint(Palette.formAccent)
    .presentationDetents([menuDetent])
    .presentationCornerRadius(MenuLayout.sheetRadius)
    .presentationBackground(Palette.menuSheet)
    .presentationDragIndicator(.hidden)
    .sensoryFeedback(.success, trigger: copies)
    .onDisappear {
      guard let followUp else { return }
      self.followUp = nil
      app.perform(followUp, on: tabID)
    }
    .alert("Translate with Google?", isPresented: $confirmsTranslation) {
      Button("Translate") {
        if let page { app.translate(page) }
        leave()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Google will see this page’s address.")
    }
  }

  private var menuDetent: PresentationDetent {
    let height = max(contentHeight - bottomInset, 200)
    return height < windowRoom ? .height(height) : .large
  }

  private func close(then next: PageMenuFollowUp) {
    followUp = next
    leave()
  }

  private func leave() {
    if let onClose { onClose() } else { dismiss() }
  }

  private var navigationCapsule: some View {
    let isLarge = dynamicTypeSize.isAccessibilitySize
    return VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 0) {
        backButton
        forwardButton
        if isLarge {
          Spacer(minLength: 0)
        } else {
          titleLabel.lineLimit(1)
        }
        pinButton
        reloadButton
      }
      .frame(minHeight: capsuleHeight)
      if isLarge {
        Divider().padding(.horizontal, Spacing.page)
        titleLabel
          .lineLimit(3)
          .padding(.horizontal, Spacing.tight)
          .padding(.vertical, Spacing.small)
      }
    }
    .padding(.horizontal, Spacing.hairline)
    .opacity(isLarge ? 1 : Double(rise))
    .background {
      if isLarge {
        RoundedRectangle(cornerRadius: PageMenuLayout.groupRadius, style: .continuous).fill(Palette.menuGroup)
      } else {
        PageMenuAddressShape(rise: rise).fill(Palette.menuGroup)
      }
    }
    .overlay {
      if !isLarge, rise < 1 {
        Image(systemName: "plus")
          .font(.system(size: BrowseLayout.barPlusGlyph, weight: .medium))
          .foregroundStyle(BrowsePalette.barGlyph)
          .opacity(Double(1 - rise))
          .accessibilityHidden(true)
      }
    }
  }

  private var backButton: some View {
    capsuleButton("chevron.backward", label: "Back", enabled: page?.canGoBack ?? false) {
      page?.goBack()
      leave()
    }
  }

  private var forwardButton: some View {
    capsuleButton("chevron.forward", label: "Forward", enabled: page?.canGoForward ?? false) {
      page?.goForward()
      leave()
    }
  }

  private var pinButton: some View {
    let isPinned = tab.map(app.isPinnedToMac) ?? false
    return capsuleButton(isPinned ? "star.fill" : "star", label: isPinned ? "Pinned to Mac" : "Pin to Mac", enabled: isWebPage && tab?.isPrivate == false) {
      app.pinToMac(tabID)
    }
    .contentTransition(.symbolEffect(.replace))
    .sensoryFeedback(.success, trigger: isPinned) { _, pinned in pinned }
  }

  @ViewBuilder
  private var reloadButton: some View {
    if page?.isLoading == true {
      capsuleButton("xmark", label: "Stop", enabled: true) { page?.stopLoading() }
    } else {
      capsuleButton("arrow.clockwise", label: "Reload", enabled: isWebPage) {
        page?.reload()
        leave()
      }
    }
  }

  private var titleLabel: some View {
    ZStack {
      if let feedback = app.browse.titleFeedback {
        Text(feedback)
          .fontWeight(.semibold)
          .foregroundStyle(Color.ardiaAccentText)
          .frame(maxWidth: .infinity)
          .transition(.opacity)
      } else {
        HStack(spacing: Spacing.hairline) {
          if address.isInsecure {
            Text("Not Secure")
              .foregroundStyle(BrowsePalette.notSecure)
              .fixedSize()
          }
          Text(address.host)
            .foregroundStyle(.primary)
            .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center)
        .transition(.opacity)
      }
    }
    .font(.body.weight(.semibold))
    .padding(.horizontal, Spacing.hairline)
    .contentShape(.rect)
    .onTapGesture { editQuery() }
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel(app.browse.titleFeedback.map { Text($0) } ?? Text("Address"))
    .accessibilityValue(address.isInsecure ? Text("\(address.host), Not Secure") : Text(address.host))
    .accessibilityHint("Edits this page’s address.")
    .animation(.easeOut(duration: 0.15), value: app.browse.titleFeedback)
  }

  private var address: BarAddress {
    BarAddress(tab: tab, page: page)
  }

  private func capsuleButton(_ symbol: String, label: LocalizedStringKey, enabled: Bool, action: @escaping () -> Void) -> some View {
    Button {
      action()
    } label: {
      Image(systemName: symbol)
        .font(.body.weight(.medium))
        .frame(minWidth: 44, minHeight: capsuleHeight)
        .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? Spacing.hairline : 0)
        .contentShape(.rect)
    }
    .buttonStyle(PageMenuPressStyle())
    .foregroundStyle(enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(Color(.tertiaryLabel)))
    .disabled(!enabled)
    .accessibilityLabel(label)
  }

  private var actionButtons: some View {
    HStack(alignment: .top, spacing: 0) {
      actionButton("doc.text.magnifyingglass", label: "Find on Page") {
        close(then: .findOnPage)
      }
      Spacer(minLength: 0)
      actionButton("doc.plaintext", label: "Reader") {
        app.browse.readerTabID = tabID
        leave()
      }
      Spacer(minLength: 0)
      actionButton("link", label: "Copy Link") {
        if app.copyLink(of: tabID) { copies += 1 }
      }
      Spacer(minLength: 0)
      actionButton("square.and.arrow.up", label: "Share") {
        leave()
        app.sharePage(tabID)
      }
    }
  }

  private func actionButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(spacing: PageMenuLayout.tileLabelGap) {
        Image(systemName: symbol)
          .font(.title3.weight(.regular))
          .frame(width: tileSize, height: tileSize)
          .background(Palette.menuTile, in: .rect(cornerRadius: PageMenuLayout.tileRadius, style: .continuous))
        Text(label)
          .font(.subheadline)
          .foregroundStyle(Palette.menuTileLabel)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(width: tileSize + PageMenuLayout.tileLabelGap * 2)
      .contentShape(.rect)
    }
    .buttonStyle(PageMenuPressStyle())
    .foregroundStyle(isWebPage ? AnyShapeStyle(.primary) : AnyShapeStyle(Color(.tertiaryLabel)))
    .disabled(!isWebPage)
    .opacity(isWebPage ? 1 : 0.6)
  }

  private var printRow: some View {
    PageMenuRow("Print", enabled: isWebPage && page?.isLive == true) { close(then: .print) }
  }

  private var translateRow: some View {
    PageMenuRow("Translate", enabled: isWebPage) {
      confirmsTranslation = true
    }
  }

  @ViewBuilder
  private var sendRow: some View {
    let devices = tab.map(app.sendTargets(for:)) ?? []
    if !devices.isEmpty, let tab, isWebPage {
      if devices.count == 1, let device = devices.first {
        PageMenuRow("Send to \(device.name)") {
          app.send(tab, to: device)
          leave()
        }
      } else {
        Menu {
          ForEach(devices) { device in
            Button(device.name, systemImage: device.kind == .mac ? "laptopcomputer" : "iphone") {
              app.send(tab, to: device)
              leave()
            }
          }
        } label: {
          PageMenuRowLabel(title: Text("Send to Device")) {
            Image(systemName: "chevron.up.chevron.down")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(.tertiary)
              .accessibilityHidden(true)
          }
        }
        .foregroundStyle(.primary)
      }
    }
  }

  private func nightShadeIsOn(_ page: WebTab) -> Bool {
    switch app.preferences.nightShade(for: page.host, isPrivate: page.isPrivate) {
    case .disabled: false
    case .always: true
    case .automatic: colorScheme == .dark
    }
  }

  private func nightShadeRow(_ page: WebTab) -> some View {
    PageMenuToggleRow(title: "Night Shade", isOn: Binding(
      get: { nightShadeIsOn(page) },
      set: { app.setNightShade($0, for: page) }
    ))
    .disabled(!isWebPage)
  }

  private func desktopRow(_ page: WebTab) -> some View {
    PageMenuToggleRow(title: "Desktop Site", isOn: Binding(
      get: { app.browse.desktopTabs.contains(tabID) },
      set: { wanted in
        guard wanted != app.browse.desktopTabs.contains(tabID) else { return }
        app.toggleDesktopSite(for: page)
        leave()
      }
    ))
    .disabled(!isWebPage)
  }

  private func blockingRow(_ page: WebTab) -> some View {
    let count = page.blockedResources.count
    return PageMenuToggleRow(
      title: "Block Ads and Trackers",
      detail: page.blockersEnabled && count > 0 ? Text(count, format: .number) : nil,
      isOn: Binding(
        get: { page.blockersEnabled },
        set: { wanted in
          guard wanted != page.blockersEnabled else { return }
          app.toggleBlockers(for: page)
          leave()
        }
      )
    )
    .disabled(!isWebPage)
  }

  private func zoomRow(_ page: WebTab) -> some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.tight))
      : AnyLayout(HStackLayout(spacing: Spacing.small))
    let canZoomOut = page.pageZoom > (WebTab.zoomLevels.first ?? 0.5)
    let canZoomIn = page.pageZoom < (WebTab.zoomLevels.last ?? 3)
    return layout {
      Text("Page Zoom")
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
      HStack(spacing: 0) {
        Button {
          page.zoomOut()
        } label: {
          Image(systemName: "minus")
            .frame(width: PageMenuLayout.zoomButtonWidth, height: PageMenuLayout.zoomHeight)
            .contentShape(.rect)
        }
        .foregroundStyle(canZoomOut ? AnyShapeStyle(.primary) : AnyShapeStyle(Color(.tertiaryLabel)))
        .disabled(!canZoomOut)
        .accessibilityLabel("Zoom Out")
        Button {
          page.setPageZoom(1)
        } label: {
          Text(page.pageZoom, format: .percent.precision(.fractionLength(0)))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .fixedSize()
            .contentTransition(.numericText(value: page.pageZoom))
            .frame(minWidth: 48)
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("Reset Zoom")
        .accessibilityValue(Text(page.pageZoom, format: .percent.precision(.fractionLength(0))))
        Button {
          page.zoomIn()
        } label: {
          Image(systemName: "plus")
            .frame(width: PageMenuLayout.zoomButtonWidth, height: PageMenuLayout.zoomHeight)
            .contentShape(.rect)
        }
        .foregroundStyle(canZoomIn ? AnyShapeStyle(.primary) : AnyShapeStyle(Color(.tertiaryLabel)))
        .disabled(!canZoomIn)
        .accessibilityLabel("Zoom In")
      }
      .font(.body.weight(.medium))
      .background(Color(.tertiarySystemFill), in: .capsule)
    }
    .buttonStyle(.plain)
    .padding(.horizontal, Spacing.page)
    .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? Spacing.small : 0)
    .frame(minHeight: MenuLayout.rowHeight)
    .animation(.snappy(duration: 0.2), value: page.pageZoom)
    .disabled(!isWebPage)
  }

  private func editQuery() {
    guard let tab else { return }
    let text = app.currentQuery(for: tab)
    leave()
    app.browse.presentSearch(from: .page, text: text, selectsAll: true)
  }
}
