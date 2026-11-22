import Foundation
import os
import QuartzCore
import UIKit

@MainActor
final class HarnessProbe {
  static let shared: HarnessProbe? = ProcessInfo.processInfo.arguments.contains("-ArdiaProbe") ? HarnessProbe() : nil

  static func start() { _ = shared }

  static func mark(_ name: String, _ detail: String? = nil) {
    guard let shared else { return }
    shared.signposter.emitEvent("mark", "\(name, privacy: .public)")
    var line = "{\"k\":\"m\",\"t\":\(shared.time()),\"name\":\"\(name)\""
    if let detail { line += ",\"detail\":\"\(detail.replacingOccurrences(of: "\"", with: "'"))\"" }
    shared.append(line + "}")
  }

  private let signposter = OSSignposter(subsystem: "com.ardia.harness", category: .pointsOfInterest)
  private let file: URL
  private let writer = DispatchQueue(label: "harness.probe.writer")
  private var buffer: [String] = []
  private var link: CADisplayLink?
  private var observer: CFRunLoopObserver?
  private var passStart: CFTimeInterval = 0
  private var flushTimer: Timer?

  private init() {
    let directory = URL.documentsDirectory.appending(path: "harness", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    file = directory.appending(path: "probe.jsonl")
    try? FileManager.default.removeItem(at: file)
    FileManager.default.createFile(atPath: file.path, contents: nil)
    append("{\"k\":\"start\",\"t\":\(time()),\"wall\":\(String(format: "%.6f", Date().timeIntervalSince1970)),\"scale\":\(UIScreen.main.scale),\"maxFPS\":\(UIScreen.main.maximumFramesPerSecond)}")
    startDisplayLink()
    KeyboardReplay.start()
    startRunLoopObserver()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
      self?.watchTouches()
      Self.applyAnimationSpeed()
    }
    flushTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.flush() }
    }
    NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.flush() }
    }
    NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { _ in
      MainActor.assumeIsolated { HarnessProbe.mark("keyboard.willShow") }
    }
    NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
      MainActor.assumeIsolated { HarnessProbe.mark("keyboard.willHide") }
    }
  }

  private static func applyAnimationSpeed() {
    let arguments = ProcessInfo.processInfo.arguments
    guard let index = arguments.firstIndex(of: "-ArdiaAnimationSpeed"), arguments.indices.contains(index + 1),
          let speed = Float(arguments[index + 1]), speed > 0 else { return }
    for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
      for window in scene.windows { window.layer.speed = speed }
    }
  }

  private func time() -> String { String(format: "%.6f", CACurrentMediaTime()) }

  private func append(_ line: String) { buffer.append(line) }

  private func flush() {
    guard !buffer.isEmpty else { return }
    let data = Data((buffer.joined(separator: "\n") + "\n").utf8)
    buffer.removeAll(keepingCapacity: true)
    let file = file
    writer.async {
      guard let handle = try? FileHandle(forWritingTo: file) else { return }
      handle.seekToEndOfFile()
      handle.write(data)
      try? handle.close()
    }
  }

  private func startDisplayLink() {
    let link = CADisplayLink(target: DisplayLinkTarget { [weak self] link in self?.tick(link) }, selector: #selector(DisplayLinkTarget.fire(_:)))
    let maximum = Float(UIScreen.main.maximumFramesPerSecond)
    link.preferredFrameRateRange = CAFrameRateRange(minimum: maximum, maximum: maximum, preferred: maximum)
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  private func tick(_ link: CADisplayLink) {
    append(String(format: "{\"k\":\"f\",\"ts\":%.6f,\"due\":%.6f,\"now\":%.6f}", link.timestamp, link.targetTimestamp, CACurrentMediaTime()))
  }

  private func startRunLoopObserver() {
    let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
    let observer = CFRunLoopObserverCreateWithHandler(nil, activities, true, Int.max) { [weak self] _, activity in
      MainActor.assumeIsolated { self?.runLoop(activity) }
    }
    CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    self.observer = observer
  }

  private func runLoop(_ activity: CFRunLoopActivity) {
    let now = CACurrentMediaTime()
    if activity == .afterWaiting {
      passStart = now
    } else if activity == .beforeWaiting, passStart > 0 {
      let busy = now - passStart
      if busy > 0.004 { append(String(format: "{\"k\":\"busy\",\"s\":%.6f,\"e\":%.6f}", passStart, now)) }
      passStart = 0
    }
  }
}

extension HarnessProbe {
  fileprivate func watchTouches() {
    let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
    guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
      self?.watchTouches()
      Self.applyAnimationSpeed()
    }
      return
    }
    window.addGestureRecognizer(TouchWatcher { [weak self] phase, touch in self?.logTouch(phase, touch, in: window) })
  }

  private func logTouch(_ phase: String, _ touch: UITouch, in window: UIWindow) {
    let point = touch.location(in: window)
    var chain: [String] = []
    if phase == "began" {
      var view: UIView? = touch.view
      while let current = view, chain.count < 5 {
        chain.append(String(NSStringFromClass(type(of: current)).prefix(40)))
        view = current.superview
      }
    }
    let recognizers = (touch.gestureRecognizers ?? []).filter { !($0 is TouchWatcher) }.map { "\(NSStringFromClass(type(of: $0)).prefix(30)):\($0.state.rawValue)" }
    append(String(format: "{\"k\":\"touch\",\"t\":%.6f,\"phase\":\"%@\",\"x\":%.0f,\"y\":%.0f,\"view\":\"%@\",\"grs\":\"%@\"}", CACurrentMediaTime(), phase, point.x, point.y, chain.joined(separator: "<"), recognizers.joined(separator: " ")))
  }
}

private final class TouchWatcher: UIGestureRecognizer, UIGestureRecognizerDelegate {
  let handler: (String, UITouch) -> Void
  init(_ handler: @escaping (String, UITouch) -> Void) {
    self.handler = handler
    super.init(target: nil, action: nil)
    cancelsTouchesInView = false
    delaysTouchesBegan = false
    delaysTouchesEnded = false
    delegate = self
  }
  private var moved: Set<ObjectIdentifier> = []
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { touches.forEach { handler("began", $0) } }
  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
    for touch in touches where moved.insert(ObjectIdentifier(touch)).inserted { handler("moved", touch) }
  }
  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
    touches.forEach { handler("ended", $0) }
    moved.removeAll()
    state = .failed
  }
  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
    moved.removeAll()
    touches.forEach { handler("cancelled", $0) }
    state = .failed
  }
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

private final class DisplayLinkTarget: NSObject {
  let handler: (CADisplayLink) -> Void
  init(_ handler: @escaping (CADisplayLink) -> Void) { self.handler = handler }
  @objc func fire(_ link: CADisplayLink) { handler(link) }
}
