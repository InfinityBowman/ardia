import ArdiaBrowser
import ArdiaDesign
import SwiftUI

struct VideoPickerSheet: View {
  let choices: VideoChoices

  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  @State private var thumbnails: [String: UIImage] = [:]

  private var page: WebTab? { app.web.existingWebTab(choices.tabID) }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.small) {
          PageMenuGroup {
            ForEach(Array(choices.scan.savable.enumerated()), id: \.element.id) { offset, video in
              Button {
                guard let page else { return }
                app.startVideoDownload(video, from: page, scan: choices.scan)
                dismiss()
              } label: {
                VideoChoiceRow(video: video, number: offset + 1, thumbnail: thumbnails[video.id])
              }
              .buttonStyle(PageMenuRowStyle())
              .foregroundStyle(.primary)
            }
          }
          if !choices.scan.unsavable.isEmpty {
            Text(unsavableNote)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .padding(.horizontal, Spacing.page)
          }
        }
        .padding(PageMenuLayout.inset)
      }
      .navigationTitle("Download Video")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
    .tint(Palette.formAccent)
    .presentationDetents([.medium, .large])
    .presentationBackground(Palette.menuSheet)
    .task { await loadThumbnails() }
  }

  private var unsavableNote: String {
    let count = choices.scan.unsavable.count
    return count == 1
      ? String(localized: "One more video on this page can’t be saved because of how the site streams it.")
      : String(localized: "\(count) more videos on this page can’t be saved because of how the site streams them.")
  }

  private func loadThumbnails() async {
    guard let page else { return }
    for video in choices.scan.savable.prefix(8) {
      if let image = await page.thumbnail(for: video) { thumbnails[video.id] = image }
    }
  }
}

private struct VideoChoiceRow: View {
  let video: DetectedVideo
  let number: Int
  let thumbnail: UIImage?

  @ScaledMetric(relativeTo: .body) private var thumbWidth: CGFloat = 96

  var body: some View {
    HStack(spacing: Spacing.small) {
      preview
        .frame(width: thumbWidth, height: thumbWidth * 9 / 16)
        .clipShape(.rect(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(video.isPlaying ? String(localized: "Playing Video") : String(localized: "Video \(number)"))
          .font(.callout.weight(.medium))
        if !details.isEmpty {
          Text(details)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Image(systemName: "arrow.down.circle")
        .font(.title3)
        .foregroundStyle(Palette.formAccent)
        .accessibilityHidden(true)
    }
    .padding(.horizontal, Spacing.page)
    .padding(.vertical, Spacing.small)
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
    .accessibilityHint("Downloads this video.")
  }

  @ViewBuilder
  private var preview: some View {
    if let thumbnail {
      Image(uiImage: thumbnail).resizable().scaledToFill()
    } else if let poster = video.element?.poster.flatMap(URL.init(string:)) {
      AsyncImage(url: poster) { image in
        image.resizable().scaledToFill()
      } placeholder: {
        placeholder
      }
    } else {
      placeholder
    }
  }

  private var placeholder: some View {
    ZStack {
      Color(.tertiarySystemFill)
      Image(systemName: "film").foregroundStyle(.secondary)
    }
  }

  private var details: String {
    var parts: [String] = []
    if let duration = video.duration {
      parts.append(Duration.seconds(duration).formatted(.time(pattern: duration >= 3600 ? .hourMinuteSecond : .minuteSecond)))
    }
    if case .file = video.kind, let width = video.element?.width, let height = video.element?.height, width > 0, height > 0 {
      parts.append("\(width)×\(height)")
    }
    return parts.joined(separator: " · ")
  }
}
