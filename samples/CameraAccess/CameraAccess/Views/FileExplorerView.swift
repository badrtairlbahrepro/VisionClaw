/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// FileExplorerView.swift
//
// Browse, view, share, and delete photos captured from Meta wearable devices.
// Photos are displayed in a two-column grid sorted newest-first.
//

import SwiftUI

struct FileExplorerView: View {
  @ObservedObject var viewModel: FileExplorerViewModel
  @Environment(\.dismiss) private var dismiss

  private let columns = [
    GridItem(.flexible(), spacing: 2),
    GridItem(.flexible(), spacing: 2),
  ]

  var body: some View {
    NavigationView {
      ZStack {
        Color.black.edgesIgnoringSafeArea(.all)

        if viewModel.savedPhotos.isEmpty {
          EmptyExplorerView()
        } else {
          ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
              ForEach(viewModel.savedPhotos) { photo in
                PhotoThumbnailCell(photo: photo) {
                  viewModel.openPhoto(photo)
                } onDelete: {
                  viewModel.deletePhoto(photo)
                }
              }
            }
          }
        }
      }
      .navigationTitle("Captured Photos")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button("Done") { dismiss() }
            .foregroundColor(.white)
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          if !viewModel.savedPhotos.isEmpty {
            Text("\(viewModel.savedPhotos.count) photo\(viewModel.savedPhotos.count == 1 ? "" : "s")")
              .font(.system(size: 13))
              .foregroundColor(.white.opacity(0.6))
          }
        }
      }
      .toolbarBackground(Color.black, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbarColorScheme(.dark, for: .navigationBar)
    }
    .sheet(isPresented: $viewModel.showPhotoDetail) {
      if let photo = viewModel.selectedPhoto {
        PhotoDetailView(photo: photo, onDelete: {
          viewModel.deletePhoto(photo)
          viewModel.dismissPhotoDetail()
        }, onDismiss: {
          viewModel.dismissPhotoDetail()
        })
      }
    }
  }
}

// MARK: - PhotoThumbnailCell

private struct PhotoThumbnailCell: View {
  let photo: SavedPhoto
  let onTap: () -> Void
  let onDelete: () -> Void

  @State private var showDeleteConfirm = false

  var body: some View {
    Button(action: onTap) {
      ZStack(alignment: .topTrailing) {
        if let thumb = photo.thumbnail {
          Image(uiImage: thumb)
            .resizable()
            .aspectRatio(1, contentMode: .fill)
            .clipped()
        } else {
          Rectangle()
            .fill(Color.white.opacity(0.1))
            .aspectRatio(1, contentMode: .fill)
            .overlay(
              Image(systemName: "photo")
                .foregroundColor(.white.opacity(0.4))
            )
        }

        // Timestamp badge
        Text(photo.createdAt.formatted(.dateTime.hour().minute()))
          .font(.system(size: 10, weight: .medium))
          .foregroundColor(.white)
          .padding(.horizontal, 5)
          .padding(.vertical, 3)
          .background(Color.black.opacity(0.55))
          .cornerRadius(4)
          .padding(5)
      }
    }
    .contextMenu {
      Button(role: .destructive) {
        showDeleteConfirm = true
      } label: {
        Label("Delete", systemImage: "trash")
      }
    }
    .confirmationDialog("Delete this photo?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
      Button("Delete", role: .destructive) { onDelete() }
      Button("Cancel", role: .cancel) {}
    }
  }
}

// MARK: - PhotoDetailView

struct PhotoDetailView: View {
  let photo: SavedPhoto
  let onDelete: () -> Void
  let onDismiss: () -> Void

  @State private var showShareSheet = false
  @State private var showDeleteConfirm = false
  @State private var fullImage: UIImage?

  var body: some View {
    NavigationView {
      ZStack {
        Color.black.edgesIgnoringSafeArea(.all)

        if let img = fullImage {
          Image(uiImage: img)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ProgressView()
            .tint(.white)
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button(action: onDismiss) {
            Image(systemName: "xmark")
              .foregroundColor(.white)
          }
        }
        ToolbarItem(placement: .principal) {
          Text(photo.createdAt.formatted(.dateTime.month().day().year().hour().minute()))
            .font(.system(size: 13))
            .foregroundColor(.white.opacity(0.7))
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          HStack(spacing: 16) {
            Button {
              showShareSheet = true
            } label: {
              Image(systemName: "square.and.arrow.up")
                .foregroundColor(.white)
            }
            Button(role: .destructive) {
              showDeleteConfirm = true
            } label: {
              Image(systemName: "trash")
                .foregroundColor(.red)
            }
          }
        }
      }
      .toolbarBackground(Color.black, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbarColorScheme(.dark, for: .navigationBar)
    }
    .sheet(isPresented: $showShareSheet) {
      if let img = fullImage {
        ShareSheet(photo: img)
      }
    }
    .confirmationDialog("Delete this photo?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
      Button("Delete", role: .destructive) { onDelete() }
      Button("Cancel", role: .cancel) {}
    }
    .onAppear {
      loadFullImage()
    }
  }

  private func loadFullImage() {
    guard let data = try? Data(contentsOf: photo.url),
          let img = UIImage(data: data)
    else { return }
    fullImage = img
  }
}

// MARK: - EmptyExplorerView

private struct EmptyExplorerView: View {
  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "photo.on.rectangle.angled")
        .font(.system(size: 56))
        .foregroundColor(.white.opacity(0.3))

      Text("No captured photos")
        .font(.system(size: 18, weight: .semibold))
        .foregroundColor(.white.opacity(0.6))

      Text("Photos taken from your glasses will appear here.")
        .font(.system(size: 14))
        .foregroundColor(.white.opacity(0.4))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
    }
  }
}
