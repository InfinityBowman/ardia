import SwiftUI

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

public extension Color {
  static func adaptive(light: Color, dark: Color) -> Color {
    #if canImport(UIKit)
      Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    #elseif canImport(AppKit)
      Color(NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light) })
    #else
      light
    #endif
  }
}

public enum BrowsePalette {
  public static let foregroundPrimary = Color.adaptive(light: Color(hex: 0x0E0F10, opacity: 0.9), dark: .white.opacity(0.8))
  public static let foregroundSecondary = Color.adaptive(light: .black.opacity(0.5), dark: .white.opacity(0.5))
  public static let foregroundTertiary = Color.adaptive(light: .black.opacity(0.3), dark: .white.opacity(0.3))
  public static let popover = Palette.panel
  public static let loadingBorder = Palette.accent
  public static let findError = Color(hex: 0xC93333)
  public static let fieldFill = Color.adaptive(light: .black.opacity(0.06), dark: .white.opacity(0.12))
  public static let fieldStroke = Color.adaptive(light: .black.opacity(0.06), dark: .white.opacity(0.08))
  public static let searchAccent = Palette.formAccent
  public static let rowIcon = Color.adaptive(light: .black.opacity(0.42), dark: .white.opacity(0.5))
  public static let incognitoSheet = Color(hex: 0x151517)
  public static let incognitoField = Color.white.opacity(0.12)
  public static let incognitoCaption = Color.white.opacity(0.55)
  public static let toolbarTile = Color.adaptive(light: .black.opacity(0.05), dark: .white.opacity(0.08))
  public static let notSecure = Color.adaptive(light: Color(hex: 0xF7931E), dark: Color(hex: 0xFF9F0A))
  public static let searchField = Color.adaptive(light: .white, dark: .white.opacity(0.12))
  public static let classicBarShadow = Color.adaptive(light: .black.opacity(0.12), dark: .black.opacity(0.4))
  public static let barBandTop = Color.adaptive(light: Color(hex: 0x9D9D9D, opacity: 0), dark: Color(hex: 0x171717, opacity: 0.6))
  public static let barBandBottom = Color.adaptive(light: Color(hex: 0x888888, opacity: 0.28), dark: Color(hex: 0x0D0D0D, opacity: 0.48))
  public static let barBandEdge = Color.adaptive(light: .clear, dark: .white.opacity(0.08))
  public static let barPlusFill = Color.adaptive(light: Color(hex: 0x898989, opacity: 0.31), dark: .white.opacity(0.1))
  public static let barCircleFill = Color.adaptive(light: Color(hex: 0x8C8C8C, opacity: 0.25), dark: .white.opacity(0.095))
  public static let barControlEdge = Color.adaptive(light: .clear, dark: .white.opacity(0.12))
  public static let barGlyph = Color.adaptive(light: Color(hex: 0x2F2F2F), dark: .white)
}

public enum SearchPanelPalette {
  public static let fill = Color.adaptive(light: Color(hex: 0xF0F0F1), dark: Color(hex: 0x212023))
  public static let materialTint = Color(hex: 0x2B2A2D)
  public static let materialTintShare: Double = 0.63
  public static let incognitoFill = Color(hex: 0x151517)
  public static let edge = Color.adaptive(light: .black.opacity(0.06), dark: .white.opacity(0.24))
  public static let field = Color.adaptive(light: Color(hex: 0xD1D2D2), dark: .white.opacity(0.12))
  public static let incognitoField = Color(hex: 0x2C2C2F)
  public static let fieldEdge = Color.adaptive(light: .black.opacity(0.05), dark: .white.opacity(0.17))
  public static let text = Color.adaptive(light: Color(hex: 0x171717), dark: .white)
  public static let secondaryText = Color.adaptive(light: .black.opacity(0.5), dark: .white.opacity(0.6))
  public static let placeholder = Color.adaptive(light: Color(hex: 0x737374), dark: .white.opacity(0.51))
  public static let rowGlyph = Color.adaptive(light: Color(hex: 0x48484A), dark: .white.opacity(0.8))
  public static let accessory = Color.adaptive(light: Color(hex: 0x7A7A7C), dark: .white.opacity(0.5))
  public static let highlight = Color.adaptive(light: .black.opacity(0.05), dark: .white.opacity(0.08))
}

public enum BrowseLayout {
  public static let sheetTopRadius: CGFloat = 40
  public static let sheetTintShare: Double = 0.8
  public static let searchFieldHeight: CGFloat = 47.5
  public static let searchFieldInset: CGFloat = 15
  public static let suggestionPitch: CGFloat = 56
  public static let suggestionIcon: CGFloat = 15
  public static let sheetAboveKeyboard: CGFloat = 304
  public static let trayFieldTop: CGFloat = 15
  public static let trayDim: Double = 0.22
  public static let searchOpenResponse: Double = 0.3
  public static let searchWidenResponse: Double = 0.25
  public static let searchCloseResponse: Double = 0.3
  public static let logoSize: CGFloat = 132
  public static let barControl: CGFloat = 48
  public static let barGap: CGFloat = 8
  public static let barGlyph: CGFloat = 19
  public static let barMenuGlyph: CGFloat = 17
  public static let classicBarShadowRadius: CGFloat = 10
  public static let panelInset: CGFloat = 8
  public static let sheetPanelRadius: CGFloat = 30
  public static let sheetFieldInset: CGFloat = 16
  public static let sheetFieldTop: CGFloat = 17
  public static let sheetRowsGap: CGFloat = 6.5
  public static let sheetFieldLeading: CGFloat = 21
  public static let sheetFieldTrailing: CGFloat = 12
  public static let panelRowLeading: CGFloat = 10
  public static let panelRowGap: CGFloat = 9
  public static let panelRowGlyph: CGFloat = 17
  public static let panelFavicon: CGFloat = 22
  public static let sheetOverhang: CGFloat = 600
  public static let panelRadius: CGFloat = 26
  public static let panelFieldInset: CGFloat = 9
  public static let panelAboveKeyboard: CGFloat = 8
  public static let panelTintShare: Double = 0.55
  public static let panelIncognitoShare: Double = 0.85
  public static let tabStackRadius: CGFloat = 4
  public static let tabStackTile = CGSize(width: 24.5, height: 27)
  public static let tabStackFront = CGPoint(x: 54.3, y: -5.1)
  public static let tabStackBack = CGPoint(x: 40, y: 3)
  public static let tabStackFrontTilt: Double = 9
  public static let tabStackBackTilt: Double = -18
  public static let tabsButtonWidth: CGFloat = 64
  public static let barLineAboveHomeIndicator: CGFloat = 10.25
  public static let barLineWithoutHomeIndicator: CGFloat = 28.5
  public static let barBandAboveLine: CGFloat = 32.75
  public static let barBandAboveLineWithoutHomeIndicator: CGFloat = 24
  public static let barFade: CGFloat = 0
  public static let barPlus = CGSize(width: 75.5, height: 39.5)
  public static let barCircle: CGFloat = 33.5
  public static let barSide: CGFloat = 23.5
  public static let barPlusGlyph: CGFloat = 20
  public static let barChevronGlyph: CGFloat = 15
  public static let hitTarget: CGFloat = 44

  public static func barLine(safeBottom: CGFloat) -> CGFloat {
    max(safeBottom + barLineAboveHomeIndicator, barLineWithoutHomeIndicator)
  }

  public static func barHeight(safeBottom: CGFloat) -> CGFloat {
    barLine(safeBottom: safeBottom) + (safeBottom > 0 ? barBandAboveLine : barBandAboveLineWithoutHomeIndicator)
  }
  public static let progressHeight: CGFloat = 2.5
  public static let toolbarTile: CGFloat = 78
}

public extension Motion {
  static let searchRise = Animation.spring(response: 0.39, dampingFraction: 1)
  static let surfaceSwap = Animation.easeOut(duration: 0.3)
  static let surfaceFade = Animation.easeOut(duration: 0.2)
  static let trayDim = Animation.easeInOut(duration: 0.3)
  static let trayDismiss = Animation.spring(response: 0.32, dampingFraction: 1)
  static let traySettle = Animation.spring(response: 0.34, dampingFraction: 0.86)
  static let resultsIn = Animation.easeOut(duration: 0.14)
  static let pager = Animation.spring(response: 0.3, dampingFraction: 0.9)
  static let press = Animation.spring(response: 0.2, dampingFraction: 0.7)
  static let barCollapse = Animation.spring(duration: 0.4, bounce: 0)
  static let progressReveal = Animation.easeOut(duration: 0.2)
  static let progressAdvance = Animation.easeOut(duration: 0.45)
  static let progressFill = Animation.easeOut(duration: 0.2)
  static let progressFade = Animation.easeOut(duration: 0.25)
  static let progressRevealDelay: Duration = .milliseconds(150)
  static let placeholderDelay: Duration = .milliseconds(300)
  static let placeholderIn = Animation.easeOut(duration: 0.22)
  static let pagerCommit = Spring(response: 0.24, dampingRatio: 1)
  static let pagerSnapBack = Spring(response: 0.2, dampingRatio: 1)
  static let pagerFade = Animation.easeOut(duration: 0.2)
  static let barTone = Animation.easeOut(duration: 0.25)
  static let logoSpinDecay: Double = 2.2
}
