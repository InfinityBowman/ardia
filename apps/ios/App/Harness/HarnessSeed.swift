import ArdiaBrowser
import Foundation

enum HarnessSeed {
  @MainActor
  static func seedIfRequested(_ app: AppModel, arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
    func value(_ key: String) -> String? {
      guard let index = arguments.firstIndex(of: key), index + 1 < arguments.count else { return nil }
      return arguments[index + 1]
    }
    guard let base = value("-ArdiaHarnessSeed") else { return false }
    let count = value("-ArdiaHarnessTabs").flatMap(Int.init) ?? 6
    let tabs = app.tabs
    guard tabs.openTabs.isEmpty else { return true }
    let now = Date.now
    var last: BrowserTab?
    for index in 1...max(count, 1) {
      guard let url = URL(string: "\(base.hasSuffix("/") ? base : base + "/")page-\(index).html") else { continue }
      let tab = tabs.open(.url(url, origin: .typed), selecting: false)
      tabs.update(tab.id, title: "Fixture \(index)")
      tab.lastActive = now.addingTimeInterval(Double(index - count) * 60)
      last = tab
    }
    if let last { tabs.select(last.id) }
    try? tabs.context.save()
    HarnessProbe.mark("seed.done", "\(count)")
    return true
  }
}
