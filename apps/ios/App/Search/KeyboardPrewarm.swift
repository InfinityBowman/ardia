import UIKit

@MainActor
enum KeyboardPrewarm {
  private static var done = false

  static func schedule(after delay: TimeInterval = 0.6) {
    guard !done else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { run() }
  }

  private static func run() {
    guard !done else { return }
    let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
    guard let window = windows.first(where: \.isKeyWindow), UIApplication.shared.applicationState == .active else {
      schedule(after: 0.5)
      return
    }
    guard window.firstResponderIfText == nil else { return }
    done = true
    HarnessProbe.mark("keyboard.prewarm")
    let field = UITextField(frame: CGRect(x: -400, y: -400, width: 200, height: 40))
    field.keyboardType = .webSearch
    field.returnKeyType = .go
    field.autocorrectionType = .no
    field.autocapitalizationType = .none
    field.spellCheckingType = .no
    field.smartQuotesType = .no
    field.smartDashesType = .no
    field.alpha = 0
    field.inputView = UIView(frame: .zero)
    field.inputAssistantItem.leadingBarButtonGroups = []
    field.inputAssistantItem.trailingBarButtonGroups = []
    (window.rootViewController?.view ?? window).addSubview(field)
    field.becomeFirstResponder()
    field.resignFirstResponder()
    field.removeFromSuperview()
  }
}

private extension UIView {
  var firstResponderIfText: UIView? {
    if isFirstResponder, self is UITextInput { return self }
    for subview in subviews {
      if let found = subview.firstResponderIfText { return found }
    }
    return nil
  }
}
