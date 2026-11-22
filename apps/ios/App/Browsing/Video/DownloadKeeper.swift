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

  func update(running: Bool, fraction: Double) {
    if running {
      hold()
      report(fraction)
    } else {
      release()
    }
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
        report(manager.overallFraction)
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
        task.progress.totalUnitCount = 100
        task.expirationHandler = { [weak self] in
          DispatchQueue.main.async { MainActor.assumeIsolated { self?.continued = nil } }
        }
        self.continued = task
        self.report(self.manager?.overallFraction ?? 0)
      }
    }
    guard registered else { return }
    let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: String(localized: "Downloading Video"), subtitle: subtitle)
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

  private var subtitle: String {
    let running = manager?.transfers.filter(\.isRunning) ?? []
    if running.count == 1, let name = running.first?.fileName { return name }
    return String(localized: "\(running.count) downloads")
  }

  private func report(_ fraction: Double) {
    guard let continued else { return }
    continued.progress.completedUnitCount = Int64((min(max(fraction, 0), 1) * 100).rounded())
    continued.updateTitle(continued.title, subtitle: subtitle)
  }

  private func release() {
    poll?.cancel()
    poll = nil
    continued?.progress.completedUnitCount = 100
    continued?.setTaskCompleted(success: true)
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
