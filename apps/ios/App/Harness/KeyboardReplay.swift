import QuartzCore
import UIKit

enum KeyboardReplay {
  struct Step: Equatable, Sendable {
    var height: CGFloat
    var at: TimeInterval
    var duration: TimeInterval
  }

  nonisolated static let notification = Notification.Name("ArdiaHarnessKeyboard")
  nonisolated static let hidesKey = "ArdiaHarnessKeyboardHides"
  nonisolated static let steps: [Step]? = parse(ProcessInfo.processInfo.arguments)
  nonisolated static let hideDuration: TimeInterval = value(after: "-ArdiaKeyboardHide", in: ProcessInfo.processInfo.arguments).flatMap(Double.init) ?? 0.25
  nonisolated static var isActive: Bool { steps != nil }

  nonisolated static func parse(_ arguments: [String]) -> [Step]? {
    guard let spec = value(after: "-ArdiaKeyboardReplay", in: arguments) else { return nil }
    return spec.split(separator: ",").compactMap { token in
      let parts = token.split(separator: "@")
      guard parts.count == 2, let height = Double(parts[0]) else { return nil }
      let timing = parts[1].split(separator: ":")
      guard let at = timing.first.flatMap({ Double($0) }) else { return nil }
      let duration = timing.count > 1 ? Double(timing[1]) ?? 0.25 : 0.25
      return Step(height: CGFloat(height), at: at, duration: duration)
    }
  }

  nonisolated private static func value(after key: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: key), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
  }

  @MainActor private static var observers: [NSObjectProtocol] = []
  @MainActor private static var run = 0
  @MainActor private static weak var stand: UIView?

  @MainActor static func start() {
    guard isActive, observers.isEmpty else { return }
    let center = NotificationCenter.default
    observers.append(center.addObserver(forName: UITextField.textDidBeginEditingNotification, object: nil, queue: .main) { note in
      let window = (note.object as? CompletingTextField)?.window
      MainActor.assumeIsolated { begin(in: window) }
    })
    observers.append(center.addObserver(forName: UITextField.textDidEndEditingNotification, object: nil, queue: .main) { note in
      let window = (note.object as? CompletingTextField)?.window
      MainActor.assumeIsolated { end(in: window) }
    })
  }

  @MainActor private static func begin(in window: UIWindow?) {
    guard let window, let steps else { return }
    run += 1
    let current = run
    for step in steps {
      DispatchQueue.main.asyncAfter(deadline: .now() + step.at) {
        guard run == current else { return }
        post(step, in: window)
      }
    }
  }

  @MainActor private static func end(in window: UIWindow?) {
    guard let window else { return }
    run += 1
    post(Step(height: 0, at: 0, duration: hideDuration), in: window)
  }

  @MainActor private static func post(_ step: Step, in window: UIWindow) {
    let bounds = window.screen.bounds
    let hides = step.height <= 0
    let frame = CGRect(x: 0, y: bounds.height - max(step.height, 0), width: bounds.width, height: max(step.height, 0))
    let info: [AnyHashable: Any] = [
      UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: frame),
      UIResponder.keyboardAnimationDurationUserInfoKey: step.duration,
      UIResponder.keyboardAnimationCurveUserInfoKey: 7,
      hidesKey: hides,
    ]
    HarnessProbe.mark("keyboard.replay", "\(Int(step.height))")
    NotificationCenter.default.post(name: notification, object: nil, userInfo: info)
    show(frame, over: step.duration, in: window)
  }

  @MainActor private static func show(_ frame: CGRect, over duration: TimeInterval, in window: UIWindow) {
    let view: UIView
    if let stand, stand.window === window {
      view = stand
    } else {
      view = UIView(frame: CGRect(x: 0, y: window.bounds.height, width: window.bounds.width, height: 0))
      view.backgroundColor = UIColor(white: 0.24, alpha: 1)
      view.isUserInteractionEnabled = false
      window.addSubview(view)
      stand = view
    }
    window.bringSubviewToFront(view)
    let target = window.convert(frame, from: window.screen.coordinateSpace)
    guard duration > 0 else {
      view.layer.removeAllAnimations()
      view.frame = target
      return
    }
    UIView.animate(withDuration: duration, delay: 0, options: [.beginFromCurrentState, UIView.AnimationOptions(rawValue: 7 << 16)]) {
      view.frame = target
    }
  }
}
