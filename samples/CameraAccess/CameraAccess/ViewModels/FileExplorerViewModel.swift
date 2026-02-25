/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// FileExplorerViewModel.swift
//
// Manages persistent storage of photos captured from Meta wearable devices.
// Photos are saved to the app's Documents directory with ISO 8601 timestamps
// and surfaced to the FileExplorerView as a time-sorted list.
//

import SwiftUI

/// A single saved photo with associated metadata.
struct SavedPhoto: Identifiable, Equatable {
  let id: UUID
  let url: URL
  let createdAt: Date
  let thumbnail: UIImage?

  static func == (lhs: SavedPhoto, rhs: SavedPhoto) -> Bool {
    lhs.id == rhs.id
  }
}

@MainActor
class FileExplorerViewModel: ObservableObject {
  @Published var savedPhotos: [SavedPhoto] = []
  @Published var selectedPhoto: SavedPhoto?
  @Published var showPhotoDetail: Bool = false

  private let fileManager = FileManager.default

  /// Directory where captured photos are persisted.
  private var photosDirectory: URL {
    let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return docs.appendingPathComponent("CapturedPhotos", isDirectory: true)
  }

  init() {
    createDirectoryIfNeeded()
    loadPhotos()
  }

  // MARK: - Public API

  /// Saves a captured UIImage to disk and inserts it at the front of the list.
  func savePhoto(_ image: UIImage) {
    let fileName = fileNameForNow()
    let fileURL = photosDirectory.appendingPathComponent(fileName)

    guard let data = image.jpegData(compressionQuality: 0.85) else {
      NSLog("[FileExplorer] Failed to encode photo as JPEG")
      return
    }

    do {
      try data.write(to: fileURL)
      let photo = makeSavedPhoto(url: fileURL, image: image)
      savedPhotos.insert(photo, at: 0)
      NSLog("[FileExplorer] Saved photo: %@", fileName)
    } catch {
      NSLog("[FileExplorer] Failed to write photo: %@", error.localizedDescription)
    }
  }

  /// Removes a photo from disk and from the in-memory list.
  func deletePhoto(_ photo: SavedPhoto) {
    do {
      try fileManager.removeItem(at: photo.url)
      savedPhotos.removeAll { $0.id == photo.id }
      NSLog("[FileExplorer] Deleted photo: %@", photo.url.lastPathComponent)
    } catch {
      NSLog("[FileExplorer] Failed to delete photo: %@", error.localizedDescription)
    }
  }

  /// Opens the detail view for the given photo.
  func openPhoto(_ photo: SavedPhoto) {
    selectedPhoto = photo
    showPhotoDetail = true
  }

  func dismissPhotoDetail() {
    showPhotoDetail = false
    selectedPhoto = nil
  }

  // MARK: - Private helpers

  private func createDirectoryIfNeeded() {
    guard !fileManager.fileExists(atPath: photosDirectory.path) else { return }
    do {
      try fileManager.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
    } catch {
      NSLog("[FileExplorer] Failed to create directory: %@", error.localizedDescription)
    }
  }

  private func loadPhotos() {
    do {
      let files = try fileManager.contentsOfDirectory(
        at: photosDirectory,
        includingPropertiesForKeys: [.creationDateKey],
        options: .skipsHiddenFiles
      )
      let jpegFiles = files.filter { $0.pathExtension.lowercased() == "jpg" }
      savedPhotos = jpegFiles
        .compactMap { url -> SavedPhoto? in
          guard let data = try? Data(contentsOf: url),
                let image = UIImage(data: data)
          else { return nil }
          let createdAt = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
          return SavedPhoto(
            id: UUID(),
            url: url,
            createdAt: createdAt,
            thumbnail: image.thumbnail(maxDimension: 200)
          )
        }
        .sorted { $0.createdAt > $1.createdAt }
      NSLog("[FileExplorer] Loaded %d photos", savedPhotos.count)
    } catch {
      NSLog("[FileExplorer] Failed to load photos: %@", error.localizedDescription)
    }
  }

  private func makeSavedPhoto(url: URL, image: UIImage) -> SavedPhoto {
    SavedPhoto(
      id: UUID(),
      url: url,
      createdAt: Date(),
      thumbnail: image.thumbnail(maxDimension: 200)
    )
  }

  private func fileNameForNow() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
    let timestamp = formatter.string(from: Date())
      .replacingOccurrences(of: ":", with: "-")
    return "photo_\(timestamp).jpg"
  }
}

// MARK: - UIImage thumbnail helper

private extension UIImage {
  func thumbnail(maxDimension: CGFloat) -> UIImage {
    let scale = min(maxDimension / size.width, maxDimension / size.height)
    guard scale < 1 else { return self }
    let newSize = CGSize(width: size.width * scale, height: size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: newSize)
    return renderer.image { _ in
      draw(in: CGRect(origin: .zero, size: newSize))
    }
  }
}
