import ArdiaBrowser
import ArdiaDesign
import SwiftUI
import UIKit

final class DeckCardView: UIView {
  let tabID: UUID
  private let content = UIView()
  private let imageView = UIImageView()
  private let placeholder = DeckCardPlaceholderView()
  private let shade = UIView()
  private var liveSnapshot: UIView?
  private(set) var hasImage = false
  private var topExtension: CGFloat = 0
  private var reveal: CGFloat = 0

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
    shade.backgroundColor = .black
    shade.alpha = 0
    shade.isUserInteractionEnabled = false
    content.addSubview(placeholder)
    content.addSubview(imageView)
    content.addSubview(shade)
    addSubview(content)
    isAccessibilityElement = true
    accessibilityTraits = .button
    resize(to: size)
  }

  required init?(coder: NSCoder) { nil }

  func resize(to size: CGSize) {
    let transform = self.transform
    self.transform = .identity
    bounds = CGRect(origin: .zero, size: size)
    self.transform = transform
    layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: TabsLayout.cardRadius).cgPath
    layoutContent()
  }

  func setTop(extension height: CGFloat, reveal amount: CGFloat) {
    guard height != topExtension || amount != reveal else { return }
    topExtension = height
    reveal = amount
    layoutContent()
  }

  private var revealedTop: CGFloat { topExtension * reveal }

  private var imageTop: CGFloat { revealedTop - topExtension }

  private func layoutContent() {
    content.frame = CGRect(x: 0, y: -revealedTop, width: bounds.width, height: bounds.height + revealedTop)
    placeholder.frame = CGRect(x: 0, y: revealedTop, width: bounds.width, height: bounds.height)
    shade.frame = content.bounds
    layoutImage()
    layoutLive()
  }

  private var configuredKey = ""

  func configure(tab: BrowserTab, image: UIImage?) {
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

  func setLive(_ snapshot: UIView?) {
    liveSnapshot?.removeFromSuperview()
    liveSnapshot = snapshot
    if let snapshot {
      snapshot.layer.anchorPoint = .zero
      snapshot.isUserInteractionEnabled = false
      content.insertSubview(snapshot, belowSubview: shade)
    }
    placeholder.isHidden = hasImage || snapshot != nil
    layoutLive()
  }

  var isShowingLive: Bool { liveSnapshot != nil }

  func setCorner(_ radius: CGFloat, edge: CGFloat) {
    content.layer.cornerRadius = radius
    content.layer.borderWidth = edge
  }

  func setDim(_ amount: CGFloat) {
    if shade.alpha != amount { shade.alpha = amount }
  }


  private func layoutImage() {
    guard let image = imageView.image, image.size.width > 0 else { return }
    let width = bounds.width
    imageView.frame = CGRect(x: 0, y: imageTop, width: width, height: width * image.size.height / image.size.width)
  }

  private func layoutLive() {
    guard let snapshot = liveSnapshot, snapshot.bounds.width > 0 else { return }
    let scale = bounds.width / snapshot.bounds.width
    snapshot.layer.position = CGPoint(x: 0, y: imageTop)
    snapshot.transform = CGAffineTransform(scaleX: scale, y: scale)
  }

  override func traitCollectionDidChange(_ previous: UITraitCollection?) {
    super.traitCollectionDidChange(previous)
    content.layer.borderColor = UIColor(TabsPalette.cardEdge).resolvedColor(with: traitCollection).cgColor
  }
}

final class DeckCardHeaderView: UIView {
  private let icon: UIHostingController<AnyView>
  private let label = UILabel()
  private var iconKey = ""

  static let titleHiddenRoom: CGFloat = 40
  static let titleRevealSpan: CGFloat = 30

  override init(frame: CGRect) {
    icon = UIHostingController(rootView: AnyView(EmptyView()))
    super.init(frame: frame)
    icon.view.backgroundColor = .clear
    icon.view.isUserInteractionEnabled = false
    icon.view.frame = CGRect(x: 0, y: 0, width: TabsLayout.faviconSize, height: TabsLayout.faviconSize)
    if #available(iOS 16.4, *) { icon.safeAreaRegions = [] }
    label.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 12.5, weight: .medium), maximumPointSize: 20)
    label.textColor = .white
    label.lineBreakMode = .byTruncatingTail
    addSubview(icon.view)
    addSubview(label)
    isUserInteractionEnabled = false
    isAccessibilityElement = false
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

  func layout(width available: CGFloat, scale: CGFloat) {
    let iconSize = TabsLayout.faviconSize
    let leading = TabsDeckGeometry.headerInset * scale
    let titleLeading = leading + iconSize + TabsLayout.headerSpacing
    let room = available - titleLeading
    let reveal = min(max((room - Self.titleHiddenRoom) / Self.titleRevealSpan, 0), 1)
    let titleWidth = min(label.intrinsicContentSize.width, max(room, 0))
    let height = bounds.height
    icon.view.frame = CGRect(x: leading, y: (height - iconSize) / 2, width: iconSize, height: iconSize)
    icon.view.alpha = DeckHeaderMetrics.iconReveal(width: available - leading, icon: iconSize)
    label.frame = CGRect(x: titleLeading, y: 0, width: titleWidth, height: height)
    label.alpha = reveal
  }
}

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
