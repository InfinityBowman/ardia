import Photos
import UIKit
import UniformTypeIdentifiers

enum VideoSaving {
  enum PhotosResult: Sendable {
    case saved
    case denied
    case failed
  }

  static func isVideo(_ url: URL) -> Bool {
    guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
    return type.conforms(to: .movie) || type.conforms(to: .video)
  }

  static func canSaveToPhotos(_ url: URL) -> Bool {
    isVideo(url) && UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(url.path(percentEncoded: false))
  }

  nonisolated static func saveToPhotos(_ url: URL) async -> PhotosResult {
    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    guard status == .authorized || status == .limited else { return .denied }
    do {
      try await PHPhotoLibrary.shared().performChanges { @Sendable in
        let request = PHAssetCreationRequest.forAsset()
        let options = PHAssetResourceCreationOptions()
        options.originalFilename = url.lastPathComponent
        request.addResource(with: .video, fileURL: url, options: options)
      }
      return .saved
    } catch {
      return .failed
    }
  }

  @MainActor
  static func saveToFiles(_ url: URL) {
    guard let presenter = topViewController() else { return }
    let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    presenter.present(picker, animated: true)
  }

  @MainActor
  static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
    return top
  }
}

extension AppModel {
  func saveVideoToPhotos(_ url: URL) {
    Task { [weak self] in
      let result = await VideoSaving.saveToPhotos(url)
      guard let self else { return }
      switch result {
      case .saved:
        toasts.show(Toast(String(localized: "Saved to Photos"), symbol: "photo.on.rectangle.angled"))
      case .denied:
        toasts.show(Toast(String(localized: "Allow Ardia to Add to Photos in Settings"), symbol: "exclamationmark.triangle.fill", duration: .seconds(3.2)) {
          if let settings = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(settings) }
        })
      case .failed:
        toasts.show(Toast(String(localized: "Couldn’t Save to Photos"), symbol: "exclamationmark.triangle.fill"))
      }
    }
  }
}
