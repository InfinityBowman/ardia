import ArdiaBrowser
import ArdiaDesign
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct DownloadedFile: Identifiable, Hashable {
  var url: URL
  var size: Int64
  var modified: Date

  var id: URL { url }
  var name: String { url.lastPathComponent }

  var symbol: String { Self.symbol(for: url) }
  var isVideo: Bool { VideoSaving.isVideo(url) }

  static func symbol(for url: URL) -> String {
    guard let type = UTType(filenameExtension: url.pathExtension) else { return "doc" }
    if type.conforms(to: .image) { return "photo" }
    if type.conforms(to: .movie) || type.conforms(to: .video) { return "film" }
    if type.conforms(to: .audio) { return "waveform" }
    if type.conforms(to: .pdf) { return "doc.richtext" }
    if type.conforms(to: .archive) { return "doc.zipper" }
    return "doc"
  }
}

enum DownloadThumbLayout {
  static let size = CGSize(width: 52, height: 38)
}

enum DownloadStatusText {
  static func percent(_ fraction: Double) -> String {
    fraction.formatted(.percent.precision(.fractionLength(0)))
  }

  static func bytes(_ value: Int64) -> String {
    value.formatted(.byteCount(style: .file))
  }

  static func remaining(_ seconds: Double) -> String {
    let rounded = max(Int(seconds.rounded()), 1)
    if rounded < 60 { return String(localized: "\(rounded) s left") }
    let minutes = Int((Double(rounded) / 60).rounded())
    if minutes < 60 { return String(localized: "\(minutes) min left") }
    return String(localized: "\(minutes / 60) h \(minutes % 60) min left")
  }

  static func stage(_ transfer: DownloadTransfer) -> String? {
    switch transfer.stage {
    case .preparing: String(localized: "Finding the best quality…")
    case .assembling: String(localized: "Putting the video together…")
    case .downloading: nil
    }
  }

  static func amount(_ transfer: DownloadTransfer) -> String {
    let received = bytes(transfer.receivedBytes)
    if let expected = transfer.expectedBytes, expected > 0 {
      return String(localized: "\(received) of \(bytes(expected))")
    }
    return received
  }

  static func menu(_ transfer: DownloadTransfer) -> String {
    if let stage = stage(transfer) { return stage }
    var parts: [String] = []
    if let fraction = transfer.fraction { parts.append(percent(fraction)) }
    if transfer.receivedBytes > 0 { parts.append(amount(transfer)) }
    if let left = transfer.secondsRemaining { parts.append(remaining(left)) }
    return parts.isEmpty ? String(localized: "Starting…") : parts.joined(separator: " · ")
  }

  static func list(_ transfer: DownloadTransfer, includesSpeed: Bool) -> String {
    if let stage = stage(transfer) { return stage }
    var parts = [amount(transfer)]
    if transfer.expectedBytes == nil, let fraction = transfer.fraction { parts.insert(percent(fraction), at: 0) }
    if includesSpeed, let speed = transfer.bytesPerSecond, speed > 0 { parts.append(String(localized: "\(bytes(Int64(speed)))/s")) }
    if let left = transfer.secondsRemaining { parts.append(remaining(left)) }
    return parts.joined(separator: " · ")
  }

  static func summaryTitle(_ summary: DownloadSummary) -> String {
    let count = String(localized: "\(summary.count) downloads")
    return summary.fraction.map { "\(count) · \(percent($0))" } ?? count
  }

  static func summaryBytes(_ summary: DownloadSummary) -> String {
    let received = bytes(summary.receivedBytes)
    return summary.expectedBytes.map { String(localized: "\(received) of \(bytes($0))") } ?? received
  }
}

@MainActor
@Observable
final class DownloadsModel {
  private(set) var files: [DownloadedFile] = []
  private(set) var hasLoaded = false

  func reload(from directory: URL) {
    let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
    let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
    files = urls.compactMap { url in
      guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return nil }
      return DownloadedFile(url: url, size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate ?? .distantPast)
    }
    .sorted { $0.modified > $1.modified }
    hasLoaded = true
  }

  func delete(_ file: DownloadedFile) {
    try? FileManager.default.removeItem(at: file.url)
    files.removeAll { $0.id == file.id }
  }

  func deleteAll() {
    for file in files { try? FileManager.default.removeItem(at: file.url) }
    files = []
  }
}

struct DownloadsList: View {
  let model: DownloadsModel

  @Environment(AppModel.self) private var app
  @State private var previewing: URL?

  private var transfers: [DownloadTransfer] { app.web.downloads.transfers }

  var body: some View {
    Group {
      if model.hasLoaded, model.files.isEmpty, transfers.isEmpty {
        ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle", description: Text("Files you download show up here."))
      } else {
        LibraryList {
          ForEach(transfers) { transfer in
            TransferRow(transfer: transfer)
              .libraryRowChrome()
          }
          ForEach(model.files) { file in
            DownloadRow(file: file) {
              previewing = file.url
            }
            .libraryRowChrome()
            .swipeActions {
              Button("Delete", role: .destructive) {
                withAnimation(Motion.snappy) { model.delete(file) }
              }
              ShareLink(item: file.url) { Text("Share") }
                .tint(Palette.formAccent)
            }
            .contextMenu {
              DownloadFileActions(file: file.url)
              Button("Delete", systemImage: "trash", role: .destructive) { model.delete(file) }
            }
          }
        }
      }
    }
    .quickLookPreview($previewing, in: model.files.map(\.url))
    .task {
      app.downloadActivity.clearRecent()
      model.reload(from: app.web.downloads.directory)
    }
    .refreshable { model.reload(from: app.web.downloads.directory) }
    .onChange(of: app.web.downloads.finishedCount) { _, _ in
      withAnimation(Motion.snappy) { model.reload(from: app.web.downloads.directory) }
      app.downloadActivity.clearRecent()
    }
  }
}

struct DownloadFileActions: View {
  let file: URL

  var body: some View {
    if VideoSaving.isVideo(file) {
      VideoFileActions(file: file)
    } else {
      ShareLink(item: file) { Label("Share…", systemImage: "square.and.arrow.up") }
    }
  }
}

struct VideoFileActions: View {
  let file: URL

  @Environment(AppModel.self) private var app

  var body: some View {
    if VideoSaving.canSaveToPhotos(file) {
      Button("Save to Photos", systemImage: "photo.badge.plus") { app.saveVideoToPhotos(file) }
    }
    Button("Save to Files", systemImage: "folder") { VideoSaving.saveToFiles(file) }
    ShareLink(item: file) { Label("Share…", systemImage: "square.and.arrow.up") }
  }
}

private struct DownloadRowIconButton: View {
  let symbol: String
  let label: LocalizedStringKey
  var tint: Color = Palette.formAccent
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.title2)
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(tint)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
  }
}

private struct TransferRow: View {
  let transfer: DownloadTransfer

  @Environment(AppModel.self) private var app

  private var failure: String? {
    if case .failed(let message) = transfer.state { return message }
    return nil
  }

  var body: some View {
    HStack(alignment: .center, spacing: Spacing.small) {
      if failure == nil {
        DownloadThumbnail(url: nil, art: app.downloadActivity.art[transfer.id], symbol: transfer.isVideo ? "film" : "doc", size: DownloadThumbLayout.size)
      } else {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.title3)
          .foregroundStyle(Color.orange)
          .frame(width: DownloadThumbLayout.size.width, height: DownloadThumbLayout.size.height)
          .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 6, style: .continuous))
          .accessibilityHidden(true)
      }
      VStack(alignment: .leading, spacing: 4) {
        Text(verbatim: transfer.fileName)
          .lineLimit(1)
          .truncationMode(.middle)
          .foregroundStyle(.primary)
        if let failure {
          Text(failure)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else {
          ProgressView(value: transfer.stage == .preparing ? 0 : (transfer.fraction ?? 0))
            .tint(Palette.formAccent)
            .opacity(transfer.fraction == nil || transfer.stage == .preparing ? 0.5 : 1)
          ViewThatFits(in: .horizontal) {
            statusText(includesSpeed: true)
            statusText(includesSpeed: false)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if failure == nil {
        DownloadRowIconButton(symbol: "xmark.circle.fill", label: "Cancel Download", tint: .secondary) {
          app.web.downloads.cancel(transfer)
        }
      } else {
        HStack(spacing: 0) {
          if transfer.canRetry {
            DownloadRowIconButton(symbol: "arrow.clockwise.circle.fill", label: "Try Again") {
              app.web.downloads.retry(transfer)
            }
          }
          DownloadRowIconButton(symbol: "xmark.circle.fill", label: "Remove", tint: .secondary) {
            withAnimation(Motion.snappy) { app.web.downloads.dismiss(transfer) }
          }
        }
      }
    }
    .padding(.vertical, Spacing.small)
    .accessibilityElement(children: .contain)
    .accessibilityValue(failure ?? DownloadStatusText.list(transfer, includesSpeed: true))
  }

  private func statusText(includesSpeed: Bool) -> some View {
    Text(DownloadStatusText.list(transfer, includesSpeed: includesSpeed))
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .monospacedDigit()
      .lineLimit(1)
      .contentTransition(.numericText())
  }
}

private struct DownloadRow: View {
  var file: DownloadedFile
  var onOpen: () -> Void

  @Environment(AppModel.self) private var app

  var body: some View {
    HStack(alignment: .center, spacing: Spacing.small) {
      Button(action: onOpen) {
        HStack(alignment: .center, spacing: Spacing.small) {
          DownloadThumbnail(url: file.url, symbol: file.symbol, size: DownloadThumbLayout.size)
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: file.name)
              .lineLimit(1)
              .truncationMode(.middle)
              .foregroundStyle(.primary)
            Text(verbatim: "\(file.size.formatted(.byteCount(style: .file))) · \(file.modified.formatted(date: .abbreviated, time: .shortened))")
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Spacing.small)
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      if file.isVideo {
        if VideoSaving.canSaveToPhotos(file.url) {
          DownloadRowIconButton(symbol: "photo.badge.plus", label: "Save to Photos") { app.saveVideoToPhotos(file.url) }
        }
        Menu {
          VideoFileActions(file: file.url)
        } label: {
          Image(systemName: "ellipsis.circle")
            .font(.title2)
            .foregroundStyle(Palette.formAccent)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("More Actions")
      } else {
        ShareLink(item: file.url) {
          Image(systemName: "square.and.arrow.up")
            .font(.title3)
            .foregroundStyle(Palette.formAccent)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share")
      }
    }
  }
}
