import Foundation
import Design
import SwiftUI
import Testing
import UIKit
@testable import Billet

@Suite struct WidgetShowcaseTests {
    @Test func idsAreUniqueAndEveryGroupHasItems() {
        let ids = WidgetShowcase.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for group in WidgetShowcase.Group.allCases {
            #expect(!WidgetShowcase.items(in: group).isEmpty, "\(group.title) lists nothing")
        }
    }

    @Test func onlyControlsHaveNoPreview() {
        for item in WidgetShowcase.all {
            #expect((item.preview == nil) == (item.group == .controls), "\(item.id)")
        }
    }
}

@MainActor
@Suite struct WidgetPreviewRenderTests {
    /// Draws every preview as the gallery does, at the card's width and 3x, for review in `BILLET_SAMPLES`.
    @Test func rendersEveryPreview() throws {
        var rendered = 0
        for item in WidgetShowcase.all {
            guard let preview = item.preview else { continue }
            for scheme in [ColorScheme.light, .dark] {
                let view = WidgetPreview(preview: preview)
                    .frame(width: 320)
                    .padding(Space.l)
                    .background(Ink.surface)
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 3
                let image = try #require(renderer.uiImage)
                #expect(image.size.width == 352)
                #expect(image.size.height > 100, "\(item.id) drew nothing")
                rendered += 1
                guard let folder = ProcessInfo.processInfo.environment["BILLET_SAMPLES"] else { continue }
                let directory = URL(fileURLWithPath: folder, isDirectory: true).appending(path: "gallery")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let format = UIGraphicsImageRendererFormat()
                format.scale = image.scale
                let png = UIGraphicsImageRenderer(size: image.size, format: format).pngData { _ in image.draw(at: .zero) }
                try png.write(to: directory.appending(path: "\(item.id)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
        #expect(rendered == WidgetShowcase.all.filter { $0.preview != nil }.count * 2)
    }
}
