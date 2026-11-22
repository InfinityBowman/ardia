import ArdiaDesign
import SwiftUI

extension Palette {
  static let menuSheet = Color(.systemBackground)
  static let menuGroup = Color.adaptive(light: .black.opacity(0.11), dark: .white.opacity(0.14))
  static let menuRow = Color.adaptive(light: .black.opacity(0.15), dark: .white.opacity(0.15))
  static let menuTile = Color.adaptive(light: .black.opacity(0.13), dark: .white.opacity(0.11))
  static let menuSeparator = Color.adaptive(light: .white.opacity(0.45), dark: .white.opacity(0.1))
  static let menuTileLabel = Color.adaptive(light: Color(hex: 0x6E6E73), dark: .white.opacity(0.6))
  static let menuPanel = Color.adaptive(light: Color(hex: 0xF0F0F0), dark: Color(hex: 0x282728))
  static let menuMaterialTint = Color.adaptive(light: Color(hex: 0xE4E4E6, opacity: 0.3), dark: Color(hex: 0x1E1D1F, opacity: 0.8))
  static let menuPanelEdge = Color.adaptive(light: .black.opacity(0.06), dark: .white.opacity(0.16))
  static let menuRowIcon = Color.adaptive(light: Color(hex: 0x3A3A3C), dark: .white.opacity(0.9))
}

enum PageMenuLayout {
  static let groupSpacing: CGFloat = 16.5
  static let barSpacing: CGFloat = 16.5
  static let inset: CGFloat = 16
  static let addressHeight: CGFloat = 47.5
  static let tile: CGFloat = 80
  static let tileRadius: CGFloat = 20
  static let tileLabelGap: CGFloat = 6
  static let rowHeight: CGFloat = 47.5
  static let rowIconSlot: CGFloat = 28
  static let rowIconGap: CGFloat = 8
  static let groupRadius: CGFloat = 16
  static let panelRadius: CGFloat = 30
  static let overhang: CGFloat = 600
  static let topGap: CGFloat = 12
  static let dim: Double = 0.22
  static let pullToClose: CGFloat = 90
  static let flingToClose: CGFloat = 160
  static let open = Animation.spring(response: 0.22, dampingFraction: 1)
  static let close = Animation.spring(response: 0.22, dampingFraction: 1)
  static let expand = Animation.spring(response: 0.3, dampingFraction: 1)
  static let contentShown: CGFloat = 0.45
  static let separator: CGFloat = 1

  static func contentOpacity(rise: CGFloat) -> Double {
    Double(min(max((rise - contentShown) / (1 - contentShown), 0), 1))
  }

  static func travel(panelHeight: CGFloat, safeBottom: CGFloat) -> CGFloat {
    max(panelHeight - BrowseLayout.barLine(safeBottom: safeBottom) - inset - addressHeight / 2, 0)
  }
  static let zoomHeight: CGFloat = 32
  static let zoomButtonWidth: CGFloat = 40
  static let zoomRadius: CGFloat = 8
}

struct WindowRoomReader: UIViewRepresentable {
  var onChange: (CGFloat) -> Void

  func makeUIView(context: Context) -> RoomView {
    let view = RoomView()
    view.onChange = onChange
    view.isUserInteractionEnabled = false
    return view
  }

  func updateUIView(_ view: RoomView, context: Context) {
    view.onChange = onChange
  }

  final class RoomView: UIView {
    var onChange: ((CGFloat) -> Void)?
    private var reported: CGFloat = 0

    override func didMoveToWindow() {
      super.didMoveToWindow()
      report()
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      report()
    }

    private func report() {
      guard let window else { return }
      let room = window.bounds.height - window.safeAreaInsets.top
      guard room > 0, room != reported else { return }
      reported = room
      let onChange = onChange
      DispatchQueue.main.async { onChange?(room) }
    }
  }
}

struct PageMenuGroup<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 0) {
      Group(subviews: content) { subviews in
        ForEach(subviews.indices, id: \.self) { index in
          if index > 0 {
            Palette.menuSeparator.frame(height: PageMenuLayout.separator)
          }
          subviews[index]
        }
      }
    }
    .background(Palette.menuRow, in: .rect(cornerRadius: PageMenuLayout.groupRadius, style: .continuous))
  }
}

struct PageMenuRowIcon: View {
  let symbol: String?

  var body: some View {
    if let symbol {
      Image(systemName: symbol)
        .font(.body)
        .foregroundStyle(Palette.menuRowIcon)
        .frame(width: PageMenuLayout.rowIconSlot)
        .accessibilityHidden(true)
    }
  }
}

struct PageMenuRowStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background(configuration.isPressed ? Color(.systemFill) : .clear)
      .animation(.easeOut(duration: configuration.isPressed ? 0 : 0.2), value: configuration.isPressed)
  }
}

struct PageMenuPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.94 : 1)
      .animation(Motion.snappy, value: configuration.isPressed)
  }
}

struct PageMenuRowLabel<Accessory: View>: View {
  var icon: String?
  var title: Text
  @ViewBuilder var accessory: Accessory

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    HStack(spacing: Spacing.small) {
      HStack(spacing: PageMenuLayout.rowIconGap) {
        PageMenuRowIcon(symbol: icon)
        title
          .font(.body)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      accessory
    }
    .padding(.horizontal, Spacing.page)
    .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? Spacing.small : 0)
    .frame(minHeight: PageMenuLayout.rowHeight)
    .contentShape(.rect)
  }
}

struct PageMenuRow: View {
  var title: LocalizedStringKey
  var icon: String?
  var enabled = true
  var action: () -> Void

  init(_ title: LocalizedStringKey, icon: String? = nil, enabled: Bool = true, action: @escaping () -> Void) {
    self.title = title
    self.icon = icon
    self.enabled = enabled
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      PageMenuRowLabel(icon: icon, title: Text(title)) { EmptyView() }
    }
    .buttonStyle(PageMenuRowStyle())
    .foregroundStyle(enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(Color(.tertiaryLabel)))
    .disabled(!enabled)
  }
}

struct PageMenuDisclosureRow: View {
  let title: LocalizedStringKey
  var icon: String?
  @Binding var isExpanded: Bool

  var body: some View {
    Button {
      withAnimation(PageMenuLayout.expand) { isExpanded.toggle() }
    } label: {
      PageMenuRowLabel(icon: icon, title: Text(title)) {
        Image(systemName: "chevron.right")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.secondary)
          .rotationEffect(.degrees(isExpanded ? 90 : 0))
          .accessibilityHidden(true)
      }
    }
    .buttonStyle(PageMenuRowStyle())
    .foregroundStyle(.primary)
    .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
  }
}

struct PageMenuToggleRow: View {
  var title: LocalizedStringKey
  var icon: String?
  var detail: Text?
  @Binding var isOn: Bool

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    Toggle(isOn: $isOn) {
      HStack(spacing: Spacing.small) {
        HStack(spacing: PageMenuLayout.rowIconGap) {
          PageMenuRowIcon(symbol: icon)
          Text(title)
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let detail {
          detail
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
            .accessibilityLabel(Text("Blocked"))
            .accessibilityValue(detail)
        }
      }
    }
    .toggleStyle(.switch)
    .tint(Palette.success)
    .padding(.horizontal, Spacing.page)
    .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? Spacing.small : 0)
    .frame(minHeight: PageMenuLayout.rowHeight)
  }
}
