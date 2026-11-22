import ArdiaDesign
import SwiftUI

struct ToastView: View {
  let toast: Toast
  var onAction: (ToastAction) -> Void = { _ in }

  var body: some View {
    HStack(spacing: Spacing.tight) {
      Image(systemName: toast.symbol)
        .font(.subheadline.weight(.semibold))
        .symbolRenderingMode(.hierarchical)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text(toast.message)
          .font(.subheadline.weight(.semibold))
          .multilineTextAlignment(.leading)
          .lineLimit(toast.actions.isEmpty ? 3 : 1)
        if let detail = toast.detail {
          Text(verbatim: detail)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
      .layoutPriority(1)
      if !toast.actions.isEmpty {
        Spacer(minLength: 0)
        HStack(spacing: Spacing.hairline) {
          ForEach(toast.actions) { action in
            actionButton(action)
          }
        }
        .fixedSize()
      }
    }
    .foregroundStyle(.primary)
    .padding(.leading, Spacing.page)
    .padding(.trailing, toast.actions.isEmpty ? Spacing.page : 6)
    .padding(.vertical, toast.actions.isEmpty ? 11 : 6)
    .frame(minHeight: toast.actions.isEmpty ? 44 : 52)
    .frame(maxWidth: toast.actions.isEmpty ? nil : .infinity)
    .background(Palette.toast, in: .capsule(style: .continuous))
    .chromeSurface(in: .capsule(style: .continuous), interactive: false)
    .contentShape(Capsule())
    .accessibilityElement(children: toast.actions.isEmpty ? .combine : .contain)
    .accessibilityAddTraits(toast.onTap == nil ? .isStaticText : .isButton)
  }

  @ViewBuilder
  private func actionButton(_ action: ToastAction) -> some View {
    if action.isProminent {
      Button {
        onAction(action)
      } label: {
        Text(action.title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.white)
          .lineLimit(1)
          .padding(.horizontal, 14)
          .frame(height: 38)
          .background(Palette.formAccent, in: .capsule)
          .contentShape(.capsule)
      }
      .buttonStyle(PressableStyle())
    } else {
      Button {
        onAction(action)
      } label: {
        Image(systemName: action.symbol)
          .font(.subheadline.weight(.semibold))
          .frame(width: 38, height: 38)
          .background(Color(.tertiarySystemFill), in: .circle)
          .contentShape(.circle)
      }
      .buttonStyle(PressableStyle())
      .accessibilityLabel(action.title)
    }
  }
}

struct ToastOverlay: ViewModifier {
  static let barClearance: CGFloat = 59
  static let sheetClearance: CGFloat = 12

  let center: ToastCenter
  var clearance: () -> CGFloat = { ToastOverlay.barClearance }
  var onInteractiveFrame: (CGRect) -> Void = { _ in }
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var dragOffset: CGFloat = 0

  func body(content: Content) -> some View {
    content
      .overlay(alignment: center.isKeyboardVisible ? .top : .bottom) {
        ZStack {
          if let toast = center.current {
            ToastView(toast: toast) { center.perform($0) }
              .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onInteractiveFrame($0) }
              .padding(.horizontal, toast.actions.isEmpty ? Spacing.page * 2 : Spacing.page)
              .padding(.bottom, center.isKeyboardVisible ? 0 : clearance())
              .padding(.top, center.isKeyboardVisible ? 4 : 0)
              .offset(y: max(dragOffset, dragOffset / 4))
              .onDisappear { onInteractiveFrame(.null) }
              .gesture(dismissDrag)
              .onTapGesture { center.activate() }
              .transition(transition)
              .id(toast.id)
          }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Motion.snappy, value: center.current?.id)
      }
  }

  private var transition: AnyTransition {
    reduceMotion
      ? .opacity
      : .asymmetric(
          insertion: .offset(y: 24).combined(with: .opacity).combined(with: .scale(scale: 0.92, anchor: .bottom)),
          removal: .offset(y: 16).combined(with: .opacity)
        )
  }

  private var dismissDrag: some Gesture {
    DragGesture(minimumDistance: 6)
      .onChanged { value in
        center.hold(true)
        dragOffset = value.translation.height
      }
      .onEnded { value in
        let flungDown = value.predictedEndTranslation.height > 40 || value.translation.height > 24
        if flungDown {
          center.dismiss()
          dragOffset = 0
        } else {
          withAnimation(Motion.snappy) { dragOffset = 0 }
          center.hold(false)
        }
      }
  }
}

extension View {
  func toastOverlay(
    _ center: ToastCenter,
    clearance: @escaping () -> CGFloat = { ToastOverlay.barClearance },
    onInteractiveFrame: @escaping (CGRect) -> Void = { _ in }
  ) -> some View {
    modifier(ToastOverlay(center: center, clearance: clearance, onInteractiveFrame: onInteractiveFrame))
  }

  func toastHost(_ center: ToastCenter) -> some View {
    toastWindow(center)
      .modifier(ReceivedTabsAnnouncer(center: center))
  }
}

#Preview("Toasts") {
  @Previewable @State var center = ToastCenter()
  VStack(spacing: Spacing.small) {
    Button("Copied URL") { center.show(.copiedURL) }
    Button("Cleared Browsing Data") { center.show(.clearedBrowsingData) }
    Button("Tab From Mac") { center.show(.tabReceived(from: "Luke's MacBook Pro")) }
  }
  .buttonStyle(.bordered)
  .frame(maxWidth: .infinity, maxHeight: .infinity)
  .toastOverlay(center)
}

#Preview("Toast Styles") {
  VStack(spacing: Spacing.small) {
    ToastView(toast: .copiedURL)
    ToastView(toast: .clearedBrowsingData)
    ToastView(toast: .tabReceived(from: "Luke's MacBook Pro"))
  }
  .padding()
}
