//
//  AppIconView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI

/// The icon Finder shows for an app, a file or a bundle.
struct AppIconView: View {
    let path: String
    let size: CGFloat

    var body: some View {
        IconThumbnailView(source: .workspace(path: path), size: size) { $0.resizable() }
            .frame(width: size, height: size)
    }
}

/// Draws a cached thumbnail in the same pass; one that is not cached is made off the main thread and shown when ready.
struct IconThumbnailView<Content: View>: View {
    let source: IconSource
    let size: CGFloat
    /// For a view drawn once by an `ImageRenderer`, where nothing loaded later would ever show.
    var waitsForImage = false
    @ViewBuilder let content: (Image) -> Content

    @Environment(\.displayScale) private var displayScale
    @State private var loaded: LoadedIcon?

    private struct Wanted: Hashable {
        let key: IconKey
        let isMissing: Bool
    }

    var body: some View {
        let cache = IconThumbnailCache.shared
        let key = IconKey(source: source, points: size, scale: displayScale)
        let image = cache.image(for: key) ?? loaded?.image(for: key) ?? (waitsForImage ? cache.imageRenderingNow(for: key) : nil)
        Group {
            if let image {
                content(Image(decorative: image, scale: displayScale))
            } else {
                Color.clear
            }
        }
        // Missing is part of the identity, so an icon the cache dropped while its row was showing loads again.
        .task(id: Wanted(key: key, isMissing: image == nil)) {
            guard image == nil, let made = await cache.load(key), !Task.isCancelled else { return }
            loaded = LoadedIcon(key: key, image: made)
        }
    }
}
