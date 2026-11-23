import ArdiaBrowser
import ArdiaDesign
import ArdiaSync
import SwiftUI

struct PendingFollowUp {
  let action: PageMenuFollowUp
  let tabID: UUID
}

struct ToolbarSheet: View {
  let tabID: UUID?
  var panelMaxHeight: CGFloat?
  var onClose: (() -> Void)?

  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.colorScheme) private var colorScheme
  @State private var copies = 0
  @State private var confirmsTranslation = false
  @State private var contentHeight: CGFloat = 560
  @State private var bottomInset: CGFloat = 0
  @State private var windowRoom: CGFloat = .greatestFiniteMagnitude
  @State private var followUp: PendingFollowUp?
  @AppStorage("pageMenu.displayOptionsExpanded") private var showsDisplay = false
  @State private var showsMore = false
  @State private var scrollPosition = ScrollPosition(edge: .top)
  @ScaledMetric(relativeTo: .body) private var capsuleHeight: CGFloat = PageMenuLayout.addressHeight
  @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = PageMenuLayout.tile

  private var tab: BrowserTab? { tabID.flatMap(app.tabs.tab) }
  private var page: WebTab? { tabID.flatMap { app.web.existingWebTab($0) } }
  private var isWebPage: Bool { tab.map { BrowserURL.isSyncable($0.url) } ?? false }

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        VStack(spacing: PageMenuLayout.barSpacing) {
          navigationCapsule
          actionButtons
            .modifier(PageMenuContentFade())
        }
        VStack(spacing: PageMenuLayout.groupSpacing) {
          PageMenuDownloads { close(then: .sheet(.downloads)) }
          PageMenuGroup {
            PageMenuDisclosureRow(title: "Display Options", icon: "doc.text.image", isExpanded: $showsDisplay)
            if showsDisplay, let page {
              translateRow
              nightShadeRow(page)
              zoomRow(page)
              desktopRow(page)
            }
          }
          PageMenuGroup {
            PageMenuRow("Download Video", icon: "square.and.arrow.down", enabled: isWebPage && page?.isLive == true) {
              app.downloadRing.expectDownload()
              close(then: .downloadVideo)
            }
            PageMenuRow("Site Settings", icon: "gearshape") { close(then: .siteSettings) }
          }
          if let page {
            PageMenuGroup {
              blockingRow(page)
            }
          }
          PageMenuGroup {
            PageMenuDisclosureRow(title: "More", icon: "ellipsis.circle", isExpanded: $showsMore)
            if showsMore {
              sendRow
              printRow
              PageMenuRow("History", icon: "clock") { close(then: .sheet(.history)) }
              PageMenuRow("Bookmarks", icon: "book") { close(then: .sheet(.bookmarks)) }
              PageMenuRow("Downloads", icon: "arrow.down.circle") { close(then: .sheet(.downloads)) }
              if let page, !app.defaultBrowser.isDefault {
                PageMenuRow("Open in Default Browser", icon: "safari") {
                  app.openInDefaultBrowser(page)
                  leave()
                }
              }
            }
          }
        }
        .padding(.top, PageMenuLayout.groupSpacing)
        .modifier(PageMenuContentFade())
      }
      .padding(PageMenuLayout.inset)
      .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? Spacing.large : 0)
    }
    .scrollPosition($scrollPosition)
    .scrollBounceBehavior(.basedOnSize)
    .scrollDisabled(panelMaxHeight.map { contentHeight <= $0 } ?? false)
    .frame(height: panelMaxHeight.map { min(contentHeight, $0) })
    .ignoresSafeArea(.container, edges: panelMaxHeight == nil ? .bottom : .all)
    .onScrollGeometryChange(for: CGFloat.self) { geometry in
      geometry.contentSize.height + (panelMaxHeight == nil ? geometry.contentInsets.top : 0)
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
    .onDisappear(perform: finishClosing)
    .modifier(PageMenuShownWatcher {
      showsMore = false
      scrollPosition.scrollTo(edge: .top)
    } onHide: {
      finishClosing()
    })
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

  private func finishClosing() {
    app.downloadActivity.menuClosed()
    guard let followUp else { return }
    self.followUp = nil
    app.perform(followUp.action, on: followUp.tabID)
  }

  private var menuDetent: PresentationDetent {
    let height = max(contentHeight - bottomInset, 200)
    return height < windowRoom ? .height(height) : .large
  }

  private func close(then next: PageMenuFollowUp) {
    followUp = tabID.map { PendingFollowUp(action: next, tabID: $0) }
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
    .modifier(PageMenuAddressFade(isLarge: isLarge))
    .background {
      if isLarge {
        RoundedRectangle(cornerRadius: PageMenuLayout.groupRadius, style: .continuous).fill(Palette.menuGroup)
      } else {
        PageMenuAddressBackdrop()
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
      if let tabID { app.pinToMac(tabID) }
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
        if let tabID { app.browse.readerTabID = tabID }
        leave()
      }
      Spacer(minLength: 0)
      actionButton("link", label: "Copy Link") {
        if let tabID, app.copyLink(of: tabID) { copies += 1 }
      }
      Spacer(minLength: 0)
      actionButton("square.and.arrow.up", label: "Share") {
        leave()
        if let tabID { app.sharePage(tabID) }
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
    PageMenuRow("Print", icon: "printer", enabled: isWebPage && page?.isLive == true) { close(then: .print) }
  }

  private var translateRow: some View {
    PageMenuRow("Translate", icon: "translate", enabled: isWebPage) {
      confirmsTranslation = true
    }
  }

  @ViewBuilder
  private var sendRow: some View {
    let devices = tab.map(app.sendTargets(for:)) ?? []
    if !devices.isEmpty, let tab, isWebPage {
      if devices.count == 1, let device = devices.first {
        PageMenuRow("Send to \(device.name)", icon: "paperplane") {
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
          PageMenuRowLabel(icon: "paperplane", title: Text("Send to Device")) {
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
    PageMenuToggleRow(title: "Night Shade", icon: "moon", isOn: Binding(
      get: { nightShadeIsOn(page) },
      set: { app.setNightShade($0, for: page) }
    ))
    .disabled(!isWebPage)
  }

  private func desktopRow(_ page: WebTab) -> some View {
    PageMenuToggleRow(title: "Request Desktop Site", icon: "desktopcomputer", isOn: Binding(
      get: { app.browse.desktopTabs.contains(page.id) },
      set: { wanted in
        guard wanted != app.browse.desktopTabs.contains(page.id) else { return }
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
      icon: "shield.lefthalf.filled",
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
      HStack(spacing: PageMenuLayout.rowIconGap) {
        PageMenuRowIcon(symbol: "plus.magnifyingglass")
        Text("Page Zoom")
          .font(.body)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
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
      .background(Palette.menuTile, in: .rect(cornerRadius: PageMenuLayout.zoomRadius, style: .continuous))
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
