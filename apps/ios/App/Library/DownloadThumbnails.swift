import QuickLookThumbnailing
import SwiftUI
import UIKit

@MainActor
final class DownloadThumbnails {
  static let shared = DownloadThumbnails()

  private let cache = NSCache<NSURL, UIImage>()

  init() {
    cache.countLimit = 64
  }

  func cached(_ url: URL) -> UIImage? {
    cache.object(forKey: url as NSURL)
  }

  func store(_ image: UIImage, for url: URL) {
    cache.setObject(image, forKey: url as NSURL)
  }

  func image(for url: URL, side: CGFloat, scale: CGFloat) async -> UIImage? {
    if let cached = cached(url) { return cached }
    let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: scale, representationTypes: .thumbnail)
    guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
    let image = representation.uiImage
    store(image, for: url)
    return image
  }
}

struct DownloadThumbnail: View {
  let url: URL?
  var art: UIImage?
  var symbol: String
  let size: CGSize
  var radius: CGFloat = 6

  @Environment(\.displayScale) private var displayScale
  @State private var loaded: UIImage?

  var body: some View {
    ZStack {
      if let image = art ?? loaded ?? url.flatMap(DownloadThumbnails.shared.cached) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        Color(.tertiarySystemFill)
        Image(systemName: symbol)
          .font(.system(size: min(size.width, size.height) * 0.5))
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: size.width, height: size.height)
    .clipShape(.rect(cornerRadius: radius, style: .continuous))
    .accessibilityHidden(true)
    .task(id: url) {
      guard art == nil, let url else { return }
      loaded = await DownloadThumbnails.shared.image(for: url, side: max(size.width, size.height), scale: displayScale)
    }
  }
}
