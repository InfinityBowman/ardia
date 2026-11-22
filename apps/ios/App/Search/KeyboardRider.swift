import ArdiaDesign
import SwiftUI
import UIKit

struct RiderGrowth: Equatable {
  var panelHeight: CGFloat
  var lineAboveBottom: CGFloat
  var bandAboveBottom: CGFloat
  var fieldTop: CGFloat
  var fieldInset: CGFloat
  var fieldHeight: CGFloat
  var capsule: CGSize
  var glyphSize: CGFloat
  var capsuleFill: UIColor
  var fieldFill: UIColor
  var glyph: UIColor
  var dim: CGFloat
}

struct KeyboardRider<Content: View>: UIViewControllerRepresentable {
  var heldLift: CGFloat?
  var isVisible: Bool
  var isInteractive: Bool
  var growth: RiderGrowth?
  let content: Content

  func makeUIViewController(context: Context) -> KeyboardRiderController {
    KeyboardRiderController()
  }

  func updateUIViewController(_ controller: KeyboardRiderController, context: Context) {
    controller.update(content: AnyView(content), heldLift: heldLift, isVisible: isVisible, isInteractive: isInteractive, growth: growth)
  }
}

struct KeyboardRiderLayout<Dim: View, Rider: View>: View {
  let dim: Dim
  let rider: Rider

  var body: some View {
    GeometryReader { proxy in
      let half = proxy.size.height / 2
      ZStack(alignment: .top) {
        dim.frame(width: proxy.size.width, height: proxy.size.height)
        rider
          .frame(width: proxy.size.width, height: half, alignment: .bottom)
      }
    }
    .ignoresSafeArea()
  }
}

private final class RiderContainer: UIView {
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let hit = super.hitTest(point, with: event)
    return hit === self ? nil : hit
  }
}

final class KeyboardRiderController: UIViewController {
  private let host = UIHostingController(rootView: AnyView(EmptyView()))
  private var follow: NSLayoutConstraint?
  private var hold: NSLayoutConstraint?
  private var isVisible = false
  private var pendingReveal: DispatchWorkItem?
  private var growth: RiderGrowth?
  private var growthAnimator: UIViewPropertyAnimator?
  private var growthViews: [UIView] = []
  nonisolated(unsafe) private var keyboardObserver: NSObjectProtocol?

  override func loadView() {
    view = RiderContainer()
    view.backgroundColor = .clear
    view.isHidden = true
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    addChild(host)
    host.view.backgroundColor = .clear
    if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
    host.view.translatesAutoresizingMaskIntoConstraints = false
    host.view.alpha = 0
    view.addSubview(host.view)
    host.didMove(toParent: self)
    view.keyboardLayoutGuide.usesBottomSafeArea = true
    let follow = host.view.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: 0)
    let hold = host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    NSLayoutConstraint.activate([
      host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      host.view.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 2),
      follow,
    ])
    self.follow = follow
    self.hold = hold
    keyboardObserver = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.revealNow() }
    }
  }

  private func revealNow() {
    guard isVisible, let pending = pendingReveal else { return }
    pending.cancel()
    pendingReveal = nil
    UIView.performWithoutAnimation { host.view.layoutIfNeeded() }
    UIView.animate(withDuration: 0.05, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
      self.host.view.alpha = 1
      self.growthViews.forEach { $0.alpha = 1 }
    }
  }

  private func startGrowth() {
    endGrowth()
    guard let growth, !UIAccessibility.isReduceMotionEnabled else { return }
    let size = host.view.bounds.size
    guard size.width > 0, size.height > 0 else { return }
    let half = size.height / 2
    let trayTop = half - growth.panelHeight
    let bandTop = half - growth.bandAboveBottom

    let mask = UIView(frame: CGRect(origin: .zero, size: size))
    let above = UIView(frame: CGRect(x: 0, y: 0, width: size.width, height: max(trayTop, 0)))
    let below = UIView(frame: CGRect(x: 0, y: bandTop, width: size.width, height: size.height - bandTop))
    for part in [above, below] {
      part.backgroundColor = .black
      mask.addSubview(part)
    }
    host.view.mask = mask

    let cover = UIView()
    cover.backgroundColor = UIColor.black.withAlphaComponent(growth.dim)
    cover.isUserInteractionEnabled = false
    cover.alpha = host.view.alpha
    cover.translatesAutoresizingMaskIntoConstraints = false
    view.insertSubview(cover, belowSubview: host.view)
    NSLayoutConstraint.activate([
      cover.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
      cover.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
      cover.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
      cover.topAnchor.constraint(equalTo: host.view.topAnchor, constant: max(trayTop, 0)),
    ])

    let start = CGRect(
      x: (size.width - growth.capsule.width) / 2,
      y: half - growth.lineAboveBottom - growth.capsule.height / 2,
      width: growth.capsule.width,
      height: growth.capsule.height
    )
    let end = CGRect(x: growth.fieldInset, y: trayTop + growth.fieldTop, width: size.width - growth.fieldInset * 2, height: growth.fieldHeight)
    let ghost = UIView(frame: start)
    ghost.backgroundColor = growth.capsuleFill
    ghost.layer.cornerRadius = start.height / 2
    ghost.layer.cornerCurve = .continuous
    ghost.isUserInteractionEnabled = false
    let glyph = UIImageView(image: UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: growth.glyphSize, weight: .medium)))
    glyph.tintColor = growth.glyph
    glyph.contentMode = .center
    glyph.frame = ghost.bounds
    glyph.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    ghost.addSubview(glyph)
    host.view.addSubview(ghost)
    growthViews = [cover, ghost]

    let animator = UIViewPropertyAnimator(duration: 0, timingParameters: Self.growSpring)
    animator.addAnimations {
      below.frame = CGRect(x: 0, y: trayTop, width: size.width, height: size.height - trayTop)
      ghost.frame = end
      ghost.layer.cornerRadius = end.height / 2
      ghost.backgroundColor = growth.fieldFill
    }
    animator.addCompletion { [weak self] position in
      guard let self, position == .end, self.growthAnimator === animator else { return }
      self.host.view.mask = nil
      cover.removeFromSuperview()
      self.growthViews = [ghost]
      UIView.animate(withDuration: Self.ghostFade, delay: 0, options: [.curveEaseOut]) {
        ghost.alpha = 0
      } completion: { _ in
        ghost.removeFromSuperview()
        if self.growthViews.first === ghost { self.growthViews = [] }
      }
    }
    UIView.animate(withDuration: Self.glyphFade, delay: 0, options: [.curveEaseOut]) {
      glyph.alpha = 0
    }
    growthAnimator = animator
    animator.startAnimation()
  }

  private func endGrowth() {
    growthAnimator?.stopAnimation(true)
    growthAnimator = nil
    host.view.mask = nil
    growthViews.forEach { $0.removeFromSuperview() }
    growthViews = []
  }

  private static var growSpring: UISpringTimingParameters {
    let stiffness = pow(2 * .pi / growResponse, 2)
    return UISpringTimingParameters(mass: 1, stiffness: stiffness, damping: 2 * sqrt(stiffness), initialVelocity: .zero)
  }

  private static let growResponse: Double = 0.19
  private static let ghostFade: TimeInterval = 0.08
  private static let glyphFade: TimeInterval = 0.12

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let half = view.bounds.height
    if follow?.constant != half { follow?.constant = half }
  }

  func update(content: AnyView, heldLift: CGFloat?, isVisible visible: Bool, isInteractive: Bool, growth: RiderGrowth? = nil) {
    host.rootView = content
    self.growth = growth
    host.view.isUserInteractionEnabled = isInteractive

    if let heldLift {
      hold?.constant = view.bounds.height - heldLift
      if follow?.isActive == true {
        follow?.isActive = false
        hold?.isActive = true
      }
    } else if hold?.isActive == true {
      hold?.isActive = false
      follow?.isActive = true
    }

    guard visible != isVisible else { return }
    isVisible = visible
    if visible {
      view.isHidden = false
      UIView.performWithoutAnimation {
        view.layoutIfNeeded()
        host.view.layoutIfNeeded()
      }
      startGrowth()
      let reveal = DispatchWorkItem { [weak self] in self?.revealNow() }
      pendingReveal = reveal
      DispatchQueue.main.async(execute: reveal)
    } else {
      pendingReveal?.cancel()
      pendingReveal = nil
      endGrowth()
      UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
        self.host.view.alpha = 0
        self.growthViews.forEach { $0.alpha = 0 }
      } completion: { [weak self] _ in
        guard let self, !self.isVisible else { return }
        self.view.isHidden = true
      }
    }
  }
}
