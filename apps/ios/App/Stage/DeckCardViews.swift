import ArdiaBrowser
import ArdiaDesign
import SwiftUI
import UIKit

/// One tab card in the deck stage: a plain UIView whose position, scale, corners and opacity are
/// animated by Core Animation, so a busy main thread never drops a frame of a transition.
final class DeckCardView: UIView {
  let tabID: UUID
  private let content = UIView()
  private let imageView = UIImageView()
  private let placeholder = DeckCardPlaceholderView()
  private var liveSnapshot: UIView?
  private(set) var hasImage = false

  init(tabID: UUID, size: CGSize) {
    self.tabID = tabID
    super.init(frame: CGRect(origin: .zero, size: size))
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.18
    layer.shadowRadius = 18
    layer.shadowOffset = CGSize(width: -2, height: 4)
    content.clipsToBounds = true
    content.layer.cornerCurve = .continuous
    content.layer.cornerRadius = TabsLayout.cardRadius
    content.layer.borderColor = UIColor(TabsPalette.cardEdge).cgColor
    content.layer.borderWidth = 0.5
    imageView.contentMode = .scaleToFill
    content.addSubview(placeholder)
    content.addSubview(imageView)
    addSubview(content)
    isAccessibilityElement = true
    accessibilityTraits = .button
    resize(to: size)
  }

  required init?(coder: NSCoder) { nil }

  /// Card size changes only with the container (rotation, archive card); never mid-animation.
  func resize(to size: CGSize) {
    let transform = self.transform
    self.transform = .identity
    bounds = CGRect(origin: .zero, size: size)
    self.transform = transform
    content.frame = bounds
    placeholder.frame = bounds
    layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: TabsLayout.cardRadius).cgPath
    layoutImage()
    layoutLive()
  }

  private var configuredKey = ""

  func configure(tab: BrowserTab, image: UIImage?) {
    // Re-setting identical text and colours still invalidates layers; skip when nothing changed.
    let key = "\(tab.title)|\(tab.url)|\(tab.isPrivate)|\(tab.themeColorHex ?? "")"
    if key != configuredKey {
      configuredKey = key
      applyIdentity(tab)
    }
    if image !== imageView.image { setImage(image) }
  }

  private func applyIdentity(_ tab: BrowserTab) {
    accessibilityLabel = TabText.title(for: tab)
    accessibilityValue = tab.isPrivate ? String(localized: "Incognito, \(TabText.host(for: tab))") : TabText.host(for: tab)
    content.backgroundColor = tab.isPrivate
      ? UIColor(TabsPalette.incognitoCard)
      : (tab.themeColorHex.flatMap { Color(hexString: $0) }.map(UIColor.init) ?? .systemBackground)
    placeholder.configure(tab: tab)
  }

  func setImage(_ image: UIImage?) {
    imageView.image = image
    hasImage = image != nil
    imageView.isHidden = image == nil
    placeholder.isHidden = image != nil || liveSnapshot != nil
    layoutImage()
  }

  /// A GPU snapshot of the live page (`snapshotView(afterScreenUpdates: false)`): free to make,
  /// pixel-identical to the page, and drawn at the page's size scaled down to the card.
  func setLive(_ snapshot: UIView?) {
    liveSnapshot?.removeFromSuperview()
    liveSnapshot = snapshot
    if let snapshot {
      snapshot.layer.anchorPoint = .zero
      snapshot.isUserInteractionEnabled = false
      content.addSubview(snapshot)
    }
    placeholder.isHidden = hasImage || snapshot != nil
    layoutLive()
  }

  var isShowingLive: Bool { liveSnapshot != nil }

  func setCorner(_ radius: CGFloat, edge: CGFloat) {
    content.layer.cornerRadius = radius
    content.layer.borderWidth = edge
  }

  private func layoutImage() {
    guard let image = imageView.image, image.size.width > 0 else { return }
    let width = bounds.width
    imageView.frame = CGRect(x: 0, y: 0, width: width, height: width * image.size.height / image.size.width)
  }

  private func layoutLive() {
    guard let snapshot = liveSnapshot, snapshot.bounds.width > 0 else { return }
    let scale = bounds.width / snapshot.bounds.width
    snapshot.layer.position = .zero
    snapshot.transform = CGAffineTransform(scaleX: scale, y: scale)
  }

  override func traitCollectionDidChange(_ previous: UITraitCollection?) {
    super.traitCollectionDidChange(previous)
    content.layer.borderColor = UIColor(TabsPalette.cardEdge).resolvedColor(with: traitCollection).cgColor
  }
}

/// The favicon and title above a card. Plain UIKit so moving it costs nothing per frame.
final class DeckCardHeaderView: UIView {
  private let icon: UIHostingController<AnyView>
  private let label = UILabel()
  private var iconKey = ""

  override init(frame: CGRect) {
    icon = UIHostingController(rootView: AnyView(EmptyView()))
    super.init(frame: frame)
    icon.view.backgroundColor = .clear
    icon.view.isUserInteractionEnabled = false
    icon.view.frame = CGRect(x: 0, y: 0, width: TabsLayout.faviconSize, height: TabsLayout.faviconSize)
    if #available(iOS 16.4, *) { icon.safeAreaRegions = [] }
    label.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 13, weight: .medium), maximumPointSize: 22)
    label.textColor = UIColor(TabsPalette.headerText)
    label.lineBreakMode = .byTruncatingTail
    addSubview(icon.view)
    addSubview(label)
    isUserInteractionEnabled = false
    isAccessibilityElement = false
    // The deck is always dark (see DeckStageController), so its labels are light.
    overrideUserInterfaceStyle = .dark
  }

  required init?(coder: NSCoder) { nil }

  func configure(tab: BrowserTab) {
    let text = tab.isPrivate ? String(localized: "Incognito") : TabText.title(for: tab)
    if label.text != text { label.text = text }
    let key = "\(tab.isPrivate)|\(tab.faviconURL ?? "")|\(tab.url)"
    if key != iconKey {
      iconKey = key
      icon.rootView = AnyView(DeckCardIcon(tab: tab, isIncognito: tab.isPrivate))
    }
  }

  /// Lays the icon and title out centred in the visible strip of the card, revealing the title only
  /// when there is room, the way the SwiftUI deck header did.
  func layout(width available: CGFloat) {
    let iconSize = TabsLayout.faviconSize
    let reveal = DeckHeaderMetrics.titleReveal(width: available)
    let titleWidth = min(label.intrinsicContentSize.width, max(available - iconSize - TabsLayout.headerSpacing, 0))
    // Pinned to the card's leading edge, the way Arc labels its cards.
    let leading: CGFloat = 2
    let height = bounds.height
    icon.view.frame = CGRect(x: leading, y: (height - iconSize) / 2, width: iconSize, height: iconSize)
    icon.view.alpha = DeckHeaderMetrics.iconReveal(width: available, icon: iconSize)
    label.frame = CGRect(x: leading + iconSize + TabsLayout.headerSpacing, y: 0, width: titleWidth, height: height)
    label.alpha = reveal
  }
}

/// The title card shown on a card with no screenshot yet.
final class DeckCardPlaceholderView: UIView {
  private let title = UILabel()
  private let host = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)
    title.font = .preferredFont(forTextStyle: .headline)
    title.numberOfLines = 4
    host.font = .preferredFont(forTextStyle: .subheadline)
    host.textColor = .secondaryLabel
    addSubview(title)
    addSubview(host)
  }

  required init?(coder: NSCoder) { nil }

  func configure(tab: BrowserTab) {
    title.text = TabText.title(for: tab)
    host.text = TabText.host(for: tab)
    let tints = traitCollection.userInterfaceStyle == .dark ? TabsPalette.placeholderTintsDark : TabsPalette.placeholderTints
    let tint = tints[abs(tab.id.hashValue) % tints.count]
    backgroundColor = tab.isPrivate ? UIColor(TabsPalette.incognitoCard) : UIColor(Color(hex: tint))
    title.textColor = tab.isPrivate ? .white : .label
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let width = bounds.width - 32
    let titleSize = title.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    title.frame = CGRect(x: 16, y: 64, width: width, height: titleSize.height)
    host.frame = CGRect(x: 16, y: title.frame.maxY + 6, width: width, height: 20)
  }
}
