import SwiftUI

public struct TabsBackdrop: View {
  private let look: ProfileLook

  public init(look: ProfileLook = .plum) {
    self.look = look
  }

  public var body: some View {
    LinearGradient(
      colors: [Color(hex: TabsPalette.deckBackdropTop), Color(hex: TabsPalette.deckBackdropBottom)],
      startPoint: .top,
      endPoint: .bottom
    )
    .ignoresSafeArea()
    .accessibilityHidden(true)
  }
}
