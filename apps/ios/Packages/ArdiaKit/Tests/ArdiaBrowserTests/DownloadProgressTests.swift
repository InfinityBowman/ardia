import Foundation
import Testing
@testable import ArdiaBrowser

@MainActor
struct DownloadProgressTests {
  private func transfer(stage: VideoDownloadStage = .downloading, fraction: Double?, received: Int64, expected: Int64?) -> DownloadTransfer {
    let transfer = DownloadTransfer(fileName: "clip", isVideo: true, stage: stage)
    transfer.apply(VideoDownloadProgress(stage: stage, fraction: fraction, receivedBytes: received, expectedBytes: expected))
    return transfer
  }

  @Test func summaryWeighsKnownSizesByBytes() {
    let small = transfer(fraction: 0.5, received: 50, expected: 100)
    let large = transfer(fraction: 0.1, received: 100, expected: 1000)
    let summary = DownloadSummary([small, large])
    #expect(summary.count == 2)
    #expect(summary.expectedBytes == 1100)
    #expect(summary.receivedBytes == 150)
    #expect(abs((summary.fraction ?? 0) - 150.0 / 1100.0) < 0.0001)
  }

  @Test func summaryAveragesFractionsWhenASizeIsUnknown() {
    let sized = transfer(fraction: 0.6, received: 60, expected: 100)
    let segmented = transfer(fraction: 0.2, received: 400, expected: nil)
    let summary = DownloadSummary([sized, segmented])
    #expect(summary.expectedBytes == nil)
    #expect(abs((summary.fraction ?? 0) - 0.4) < 0.0001)
  }

  @Test func summaryIsIndeterminateWhileAnyTransferIsPreparing() {
    let running = transfer(fraction: 0.6, received: 60, expected: 100)
    let preparing = transfer(stage: .preparing, fraction: nil, received: 0, expected: nil)
    let summary = DownloadSummary([running, preparing])
    #expect(summary.fraction == nil)
    #expect(summary.isIndeterminate)
    #expect(DownloadSummary([]).isIndeterminate == false)
  }

  @Test func rateNeedsASpanBeforeItGuesses() {
    var rate = TransferRate()
    let start = ContinuousClock.now
    rate.add(bytes: 0, fraction: 0, at: start)
    rate.add(bytes: 500, fraction: 0.05, at: start + .milliseconds(300))
    #expect(rate.bytesPerSecond == nil)
    rate.add(bytes: 2000, fraction: 0.2, at: start + .seconds(2))
    #expect(abs((rate.bytesPerSecond ?? 0) - 1000) < 0.001)
    let left = rate.secondsRemaining(received: 2000, expected: 10000, fraction: 0.2)
    #expect(abs((left ?? 0) - 8) < 0.001)
  }

  @Test func rateFallsBackToFractionsWithoutASize() {
    var rate = TransferRate()
    let start = ContinuousClock.now
    rate.add(bytes: 0, fraction: 0.1, at: start)
    rate.add(bytes: 0, fraction: 0.3, at: start + .seconds(2))
    let left = rate.secondsRemaining(received: 0, expected: nil, fraction: 0.3)
    #expect(abs((left ?? 0) - 7) < 0.001)
  }

  @Test func rateForgetsSamplesOutsideItsWindowAndRestarts() {
    var rate = TransferRate()
    let start = ContinuousClock.now
    rate.add(bytes: 0, fraction: nil, at: start)
    rate.add(bytes: 1000, fraction: nil, at: start + .seconds(1))
    rate.add(bytes: 11000, fraction: nil, at: start + .seconds(6))
    rate.add(bytes: 21000, fraction: nil, at: start + .seconds(7))
    #expect(abs((rate.bytesPerSecond ?? 0) - 10000) < 0.001)
    rate.add(bytes: 100, fraction: nil, at: start + .seconds(8))
    #expect(rate.bytesPerSecond == nil)
  }

  @Test func transferDropsRateOutsideTheDownloadingStage() {
    let transfer = transfer(fraction: 0.5, received: 500, expected: 1000)
    transfer.apply(VideoDownloadProgress(stage: .assembling, fraction: 0.9, receivedBytes: 900, expectedBytes: 1000))
    #expect(transfer.bytesPerSecond == nil)
    #expect(transfer.secondsRemaining == nil)
  }
}
