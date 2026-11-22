import ArdiaBrowser
import BackgroundTasks
import UIKit

@MainActor
final class DownloadKeeper {
  static let identifierPrefix = "com.jacobmaynard.ardia.download"

  weak var manager: DownloadManager?
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
  private var continued: BGContinuedProcessingTask?
  private var submitted: String?
  private var poll: Task<Void, Never>?
  private var hadFailure = false

  func update(running: Bool, fraction: Double?) {
    if running {
      hold()
      report(fraction)
    } else {
      release()
    }
  }

  func noteFailure() {
    hadFailure = true
  }

  private func hold() {
    if backgroundTask == .invalid {
      backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Ardia Downloads") { [weak self] in
        self?.endBackgroundTask()
      }
    }
    if submitted == nil, UIApplication.shared.applicationState == .active { submitContinuedTask() }
    guard poll == nil else { return }
    poll = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        guard let self, let manager else { return }
        report(manager.summary.fraction)
      }
    }
  }

  private func submitContinuedTask() {
    let identifier = "\(Self.identifierPrefix).\(UUID().uuidString.prefix(8))"
    let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
      MainActor.assumeIsolated {
        guard let task = task as? BGContinuedProcessingTask else {
          task.setTaskCompleted(success: false)
          return
        }
        guard let self, self.submitted == identifier, self.manager?.hasRunningTransfers == true else {
          task.setTaskCompleted(success: true)
          return
        }
        HarnessProbe.mark("keeper.run")
        task.progress.totalUnitCount = 100
        task.expirationHandler = { [weak self] in
          DispatchQueue.main.async { MainActor.assumeIsolated { self?.expired(identifier) } }
        }
        self.continued = task
        self.report(self.manager?.summary.fraction)
      }
    }
    guard registered else { return }
    HarnessProbe.mark("keeper.submit")
    let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: subtitle)
    request.strategy = .fail
    submitted = identifier
    Task { [weak self] in
      do {
        try await BGTaskScheduler.shared.submitTaskRequest(request)
      } catch {
        if self?.submitted == identifier { self?.submitted = nil }
      }
    }
  }

  private var title: String {
    manager?.running.allSatisfy(\.isVideo) == false ? String(localized: "Downloading") : String(localized: "Downloading Video")
  }

  private var subtitle: String {
    let running = manager?.transfers.filter(\.isRunning) ?? []
    if running.count == 1, let name = running.first?.fileName { return name }
    return String(localized: "\(running.count) downloads")
  }

  private func report(_ fraction: Double?) {
    guard let continued else { return }
    if let fraction {
      continued.progress.completedUnitCount = Int64((min(max(fraction, 0), 1) * 100).rounded())
    }
    continued.updateTitle(continued.title, subtitle: subtitle)
  }

  private func expired(_ identifier: String) {
    guard submitted == identifier, let task = continued else { return }
    continued = nil
    submitted = nil
    task.setTaskCompleted(success: false)
    HarnessProbe.mark("keeper.expired")
    guard let manager else { return }
    for transfer in manager.running { manager.cancel(transfer) }
  }

  private func release() {
    poll?.cancel()
    poll = nil
    let succeeded = !hadFailure
    hadFailure = false
    if let continued {
      if succeeded { continued.progress.completedUnitCount = continued.progress.totalUnitCount }
      continued.setTaskCompleted(success: succeeded)
      HarnessProbe.mark("keeper.complete", succeeded ? "success" : "failure")
    }
    if submitted != nil || backgroundTask != .invalid { HarnessProbe.mark("keeper.release") }
    continued = nil
    submitted = nil
    endBackgroundTask()
  }

  private func endBackgroundTask() {
    guard backgroundTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
  }
}
