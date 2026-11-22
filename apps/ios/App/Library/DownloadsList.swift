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

  var symbol: String {
    guard let type = UTType(filenameExtension: url.pathExtension) else { return "doc" }
    if type.conforms(to: .image) { return "photo" }
    if type.conforms(to: .movie) || type.conforms(to: .video) { return "film" }
    if type.conforms(to: .audio) { return "waveform" }
    if type.conforms(to: .pdf) { return "doc.richtext" }
    if type.conforms(to: .archive) { return "doc.zipper" }
    return "doc"
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
            Button {
              previewing = file.url
            } label: {
              DownloadRow(file: file)
            }
            .buttonStyle(.plain)
            .libraryRowChrome()
            .swipeActions {
              Button("Delete", role: .destructive) {
                withAnimation(Motion.snappy) { model.delete(file) }
              }
              ShareLink(item: file.url) { Text("Share") }
                .tint(Palette.formAccent)
            }
            .contextMenu {
              if VideoSaving.isVideo(file.url) {
                VideoFileActions(file: file.url)
              } else {
                ShareLink(item: file.url)
              }
              Button("Delete", systemImage: "trash", role: .destructive) { model.delete(file) }
            }
          }
        }
      }
    }
    .quickLookPreview($previewing, in: model.files.map(\.url))
    .task { model.reload(from: app.web.downloads.directory) }
    .refreshable { model.reload(from: app.web.downloads.directory) }
    .onChange(of: app.web.downloads.finishedCount) { _, _ in
      withAnimation(Motion.snappy) { model.reload(from: app.web.downloads.directory) }
    }
  }
}

struct VideoFileActions: View {
  let file: URL

  @Environment(AppModel.self) private var app

  var body: some View {
    if VideoSaving.canSaveToPhotos(file) {
      Button("Save to Photos", systemImage: "photo.on.rectangle.angled") { app.saveVideoToPhotos(file) }
    }
    Button("Save to Files", systemImage: "folder") { VideoSaving.saveToFiles(file) }
    ShareLink(item: file) { Label("Share…", systemImage: "square.and.arrow.up") }
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
      Image(systemName: failure == nil ? (transfer.isVideo ? "film" : "arrow.down.circle") : "exclamationmark.triangle.fill")
        .font(.system(size: SiteRow.libraryFavicon * 0.8))
        .foregroundStyle(failure == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
        .frame(width: SiteRow.libraryFavicon, height: SiteRow.libraryFavicon)
        .accessibilityHidden(true)
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
          if let fraction = transfer.fraction, transfer.stage != .preparing {
            ProgressView(value: fraction)
              .tint(Palette.formAccent)
          } else {
            ProgressView(value: 0)
              .tint(Palette.formAccent)
              .opacity(0.5)
          }
          Text(status)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .contentTransition(.numericText())
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if failure == nil {
        Button {
          app.web.downloads.cancel(transfer)
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.title2)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel Download")
      } else {
        HStack(spacing: 0) {
          if transfer.canRetry {
            Button {
              app.web.downloads.retry(transfer)
            } label: {
              Image(systemName: "arrow.clockwise.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Palette.formAccent)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Try Again")
          }
          Button {
            withAnimation(Motion.snappy) { app.web.downloads.dismiss(transfer) }
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.title2)
              .symbolRenderingMode(.hierarchical)
              .foregroundStyle(.secondary)
              .frame(minWidth: 44, minHeight: 44)
              .contentShape(.rect)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Remove")
        }
      }
    }
    .padding(.vertical, Spacing.small)
    .accessibilityElement(children: .contain)
    .accessibilityValue(failure ?? status)
  }

  private var status: String {
    let received = transfer.receivedBytes.formatted(.byteCount(style: .file))
    switch transfer.stage {
    case .preparing:
      return String(localized: "Finding the best quality…")
    case .assembling:
      return String(localized: "Putting the video together…")
    case .downloading:
      if let expected = transfer.expectedBytes, expected > 0 {
        return String(localized: "\(received) of \(expected.formatted(.byteCount(style: .file)))")
      }
      if let fraction = transfer.fraction {
        return transfer.receivedBytes > 0 ? "\(fraction.formatted(.percent.precision(.fractionLength(0)))) · \(received)" : fraction.formatted(.percent.precision(.fractionLength(0)))
      }
      return received
    }
  }
}

private struct DownloadRow: View {
  var file: DownloadedFile

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.small) {
      Image(systemName: file.symbol)
        .font(.system(size: SiteRow.libraryFavicon * 0.8))
        .foregroundStyle(.secondary)
        .frame(width: SiteRow.libraryFavicon, height: SiteRow.libraryFavicon)
        .padding(.top, 2)
        .accessibilityHidden(true)
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
}
