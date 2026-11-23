import ArdiaBrowser
import ArdiaDesign
import SwiftUI

enum PageMenuDownloadsLayout {
  static let thumb = CGSize(width: 32, height: 32)
  static let leading: CGFloat = 14
  static let gap: CGFloat = 6
  static let verticalPadding: CGFloat = 7
  static let control: CGFloat = 28
  static let shownFinished = 2
}

struct PageMenuDownloads: View {
  let onOpenList: () -> Void

  @Environment(AppModel.self) private var app
  @Environment(\.pageMenuShown) private var isShown

  var body: some View {
    if isShown { content }
  }

  @ViewBuilder
  private var content: some View {
    let running = app.web.downloads.running
    let recent = Array(app.downloadActivity.recent.prefix(PageMenuDownloadsLayout.shownFinished))
    let pending = app.downloadActivity.isPending
    if !running.isEmpty || !recent.isEmpty || pending {
      PageMenuGroup {
        if running.count == 1, let transfer = running.first {
          PageMenuRunningDownloadRow(transfer: transfer, onOpenList: onOpenList)
        } else if running.count > 1 {
          PageMenuDownloadSummaryRow(running: running, onOpenList: onOpenList)
        } else if pending {
          PageMenuPendingDownloadRow(onOpenList: onOpenList)
        }
        ForEach(recent) { item in
          PageMenuFinishedDownloadRow(item: item, onOpenList: onOpenList)
        }
      }
      .onChange(of: recent.map(\.url), initial: true) { _, urls in
        app.downloadActivity.menuShowed(urls)
      }
      .onAppear { HarnessProbe.mark("menu.downloads") }
    }
  }
}

private struct PageMenuDownloadRowLabel<Thumb: View>: View {
  var title: Text
  var subtitle: Text?
  @ViewBuilder var thumb: Thumb

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    HStack(spacing: PageMenuDownloadsLayout.gap) {
      thumb
        .frame(width: PageMenuDownloadsLayout.thumb.width, height: PageMenuDownloadsLayout.thumb.height)
      VStack(alignment: .leading, spacing: 1) {
        title
          .font(.body)
          .lineLimit(1)
          .truncationMode(.middle)
        if let subtitle {
          subtitle
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .contentTransition(.numericText())
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.leading, PageMenuDownloadsLayout.leading)
    .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? Spacing.small : PageMenuDownloadsLayout.verticalPadding)
    .frame(minHeight: PageMenuLayout.rowHeight)
    .contentShape(.rect)
  }
}

private struct PageMenuDownloadRow<Thumb: View, Trailing: View>: View {
  var title: Text
  var subtitle: Text?
  var accessibilityHint: Text = Text("Opens Downloads.")
  let onOpenList: () -> Void
  @ViewBuilder var thumb: Thumb
  @ViewBuilder var trailing: Trailing

  var body: some View {
    HStack(spacing: 0) {
      Button(action: onOpenList) {
        PageMenuDownloadRowLabel(title: title, subtitle: subtitle) { thumb }
      }
      .buttonStyle(.plain)
      .accessibilityElement(children: .combine)
      .accessibilityHint(accessibilityHint)
      trailing
        .padding(.trailing, Spacing.hairline)
    }
    .foregroundStyle(.primary)
  }
}

struct PageMenuRunningDownloadRow: View {
  let transfer: DownloadTransfer
  let onOpenList: () -> Void

  @Environment(AppModel.self) private var app

  var body: some View {
    PageMenuDownloadRow(title: Text(verbatim: transfer.fileName), subtitle: Text(DownloadStatusText.menu(transfer)), onOpenList: onOpenList) {
      DownloadThumbnail(url: nil, art: app.downloadActivity.art[transfer.id], symbol: transfer.isVideo ? "film" : "doc", size: PageMenuDownloadsLayout.thumb)
    } trailing: {
      DownloadStopButton(fraction: transfer.stage == .preparing ? nil : transfer.fraction) {
        app.web.downloads.cancel(transfer)
      }
    }
  }
}

struct PageMenuDownloadSummaryRow: View {
  let running: [DownloadTransfer]
  let onOpenList: () -> Void

  @Environment(AppModel.self) private var app

  var body: some View {
    let summary = DownloadSummary(running)
    PageMenuDownloadRow(title: Text(DownloadStatusText.summaryTitle(summary)), subtitle: Text(DownloadStatusText.summaryBytes(summary)), onOpenList: onOpenList) {
      ZStack {
        Color(.tertiarySystemFill)
        Image(systemName: "arrow.down.circle")
          .font(.body)
          .foregroundStyle(Palette.menuRowIcon)
      }
      .clipShape(.rect(cornerRadius: 6, style: .continuous))
      .accessibilityHidden(true)
    } trailing: {
      Image(systemName: "chevron.right")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
  }
}

struct PageMenuPendingDownloadRow: View {
  let onOpenList: () -> Void

  var body: some View {
    PageMenuDownloadRow(title: Text("Looking for the video…"), subtitle: nil, onOpenList: onOpenList) {
      ZStack {
        Color(.tertiarySystemFill)
        ProgressView().controlSize(.small)
      }
      .clipShape(.rect(cornerRadius: 6, style: .continuous))
      .accessibilityHidden(true)
    } trailing: {
      EmptyView()
    }
  }
}

struct PageMenuFinishedDownloadRow: View {
  let item: DownloadActivity.Finished
  let onOpenList: () -> Void

  @Environment(AppModel.self) private var app

  var body: some View {
    PageMenuDownloadRow(title: Text(verbatim: item.url.lastPathComponent), subtitle: Text(subtitle), onOpenList: onOpenList) {
      DownloadThumbnail(url: item.url, symbol: DownloadedFile.symbol(for: item.url), size: PageMenuDownloadsLayout.thumb)
    } trailing: {
      trailing
    }
  }

  private var subtitle: String {
    if item.savedToPhotos { return String(localized: "Saved to Photos") }
    let size = (try? item.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map { Int64($0).formatted(.byteCount(style: .file)) }
    return size.map { String(localized: "Downloaded · \($0)") } ?? String(localized: "Downloaded")
  }

  @ViewBuilder
  private var trailing: some View {
    if item.savedToPhotos {
      Image(systemName: "checkmark.circle.fill")
        .font(.title3)
        .foregroundStyle(Palette.success)
        .frame(width: 44, height: 44)
        .accessibilityLabel("Saved to Photos")
    } else if VideoSaving.canSaveToPhotos(item.url) {
      DownloadPillButton(title: "Save to Photos") { app.saveVideoToPhotos(item.url) }
    } else {
      DownloadPillButton(title: "Open") {
        app.browse.isToolbarPresented = false
        app.openDownloadedFile(item.url)
      }
    }
  }
}

struct DownloadPillButton: View {
  let title: LocalizedStringKey
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Palette.formAccent, in: .capsule)
        .frame(minHeight: 44)
        .padding(.trailing, Spacing.small - Spacing.hairline)
        .contentShape(.rect)
    }
    .buttonStyle(PageMenuPressStyle())
  }
}

struct DownloadStopButton: View {
  let fraction: Double?
  let action: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var spins = false

  var body: some View {
    Button(action: action) {
      ZStack {
        Circle()
          .stroke(Color.primary.opacity(0.15), lineWidth: 2.5)
        Circle()
          .trim(from: 0, to: fraction.map { CGFloat(max($0, 0.02)) } ?? 0.28)
          .stroke(Palette.formAccent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
          .rotationEffect(.degrees(-90 + (fraction == nil && spins ? 360 : 0)))
          .animation(fraction == nil && !reduceMotion ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .linear(duration: 0.15), value: spins)
          .animation(.linear(duration: 0.15), value: fraction)
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
          .fill(Palette.formAccent)
          .frame(width: 8, height: 8)
      }
      .frame(width: PageMenuDownloadsLayout.control, height: PageMenuDownloadsLayout.control)
      .frame(width: 44, height: 44)
      .contentShape(.rect)
    }
    .buttonStyle(PageMenuPressStyle())
    .accessibilityLabel("Cancel Download")
    .accessibilityValue(fraction.map { Text($0, format: .percent.precision(.fractionLength(0))) } ?? Text("In Progress"))
    .onAppear { spins = fraction == nil }
    .onChange(of: fraction == nil) { _, unknown in spins = unknown }
  }
}
