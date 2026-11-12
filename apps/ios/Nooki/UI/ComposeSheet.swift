import MomentsInterface
import WidgetInterface
import WidgetUI
import PetScene
import PhotosUI
import SwiftUI
import Design
import UIKit
import UsInterface
import Wire

// MARK: - Compose

struct ComposeSheet: View {
    let image: UIImage
    var onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var caption = ""
    @State private var film: UIImage?
    @FocusState private var focused: Bool
    @State private var sheetWidth: CGFloat = 0

    /// Most of the sheet's width on a phone, held back on a wide one so the print stays a print. Before the first
    /// measure it is about what an SE gives, so the fitted sheet doesn't open around a sliver.
    private var printWidth: CGFloat { sheetWidth > 0 ? min(sheetWidth * 0.78, 320) : 260 }

    static let captionLimit = 40

    var body: some View {
        BilletSheet("New moment", size: .fit) {
            VStack(spacing: Space.gutter) {
                // The print as it will hang in the feed, the caption written straight onto its strip.
                Polaroid(width: printWidth, caption: caption, byline: Date.now.formatted(.dateTime.month(.abbreviated).day()),
                         captionEditor: $caption, captionFocus: $focused) {
                    Image(uiImage: film ?? image).resizable().scaledToFill()
                }
                .rotationEffect(.degrees(focused ? 0 : -2))
                .animation(Motion.spring(0.25), value: focused)
                .onChange(of: caption) { _, text in
                    if text.count > Self.captionLimit { caption = String(text.prefix(Self.captionLimit)) }
                }

                LimitCounter(count: caption.count, limit: Self.captionLimit)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                PrimaryButton("Add to Moments · +10") {
                    onSave(caption.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
            }
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { sheetWidth = $0 }
        }
        .task {
            let image = image
            film = await Task.detached(priority: .userInitiated) { InstantFilm.develop(image) }.value
        }
    }
}
