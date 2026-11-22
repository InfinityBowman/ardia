import ArdiaDesign
import SwiftUI

struct PageMenuPanel: View {
  @Environment(AppModel.self) private var app
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.profileLook) private var look
  @State private var shownID: UUID?
  @State private var rise: CGFloat = 0
  @State private var dimmed = false
  @State private var drag: CGFloat = 0
  @State private var panelHeight: CGFloat = 560
  @State private var generation = 0

  var body: some View {
    GeometryReader { proxy in
      let safeBottom = proxy.safeAreaInsets.bottom
      let travel = PageMenuLayout.travel(panelHeight: panelHeight, safeBottom: safeBottom)
      ZStack(alignment: .bottom) {
        if let shownID {
          Color.black
            .opacity(dimmed ? PageMenuLayout.dim : 0)
            .contentShape(.rect)
            .onTapGesture { app.browse.isToolbarPresented = false }
            .accessibilityLabel("Close Menu")
            .accessibilityAddTraits(.isButton)
          panel(shownID, safeBottom: safeBottom, maxHeight: proxy.size.height - PageMenuLayout.topGap)
            .offset(y: (1 - rise) * travel + drag)
            .environment(\.pageMenuRise, rise)
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
  }

  private func panel(_ id: UUID, safeBottom: CGFloat, maxHeight: CGFloat) -> some View {
    ToolbarSheet(tabID: id, panelMaxHeight: maxHeight - safeBottom, onClose: { app.browse.isToolbarPresented = false })
      .padding(.bottom, safeBottom)
      .background(alignment: .top) {
        fill
          .clipShape(UnevenRoundedRectangle(topLeadingRadius: PageMenuLayout.panelRadius, topTrailingRadius: PageMenuLayout.panelRadius, style: .continuous))
          .padding(.bottom, -PageMenuLayout.overhang)
          .allowsHitTesting(false)
      }
      .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
      .highPriorityGesture(pull, isEnabled: panelHeight - safeBottom < maxHeight - safeBottom)
      .simultaneousGesture(pull, isEnabled: panelHeight - safeBottom >= maxHeight - safeBottom)
      .id(generation)
  }

  @ViewBuilder
  private var fill: some View {
    if reduceTransparency {
      look.surface
    } else {
      ZStack {
        BarBackdropBlur()
        BrowsePalette.barBandTop
      }
    }
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
    var instant = Transaction()
    instant.disablesAnimations = true
    withTransaction(instant) {
      if shownID == nil { generation += 1 }
      shownID = id
      drag = 0
      if reduceMotion { rise = 1 }
    }
    DispatchQueue.main.async {
      withAnimation(reduceMotion ? Motion.surfaceFade : PageMenuLayout.open) { rise = 1 }
      withAnimation(Motion.trayDim) { dimmed = true }
    }
  }

  private func close() {
    guard shownID != nil else { return }
    HarnessProbe.mark("menu.close")
    let closing = generation
    withAnimation(Motion.trayDim) { dimmed = false }
    withAnimation(reduceMotion ? Motion.surfaceFade : PageMenuLayout.close) {
      rise = 0
    } completion: {
      guard closing == generation, !app.browse.isToolbarPresented else { return }
      shownID = nil
      drag = 0
    }
  }
}

extension EnvironmentValues {
  @Entry var pageMenuRise: CGFloat = 1
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
