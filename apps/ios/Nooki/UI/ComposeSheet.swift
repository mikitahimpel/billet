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

    static let captionLimit = 40

    var body: some View {
        BilletSheet("New moment", size: .fit) {
            VStack(spacing: Space.gutter) {
                VStack(alignment: .leading, spacing: Space.m) {
                    Image(uiImage: film ?? image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 220, height: 220)
                        .clipped()
                    TextField("", text: $caption, prompt: Text("Write a little note…").foregroundStyle(PolaroidPaper.byline))
                        .font(.custom("Noteworthy-Bold", size: 17))
                        .foregroundStyle(PolaroidPaper.ink)
                        .focused($focused)
                        .submitLabel(.done)
                        .frame(width: 220)
                        .onChange(of: caption) { _, text in
                            if text.count > Self.captionLimit { caption = String(text.prefix(Self.captionLimit)) }
                        }
                }
                .padding(Space.m)
                .padding(.bottom, Space.l)
                .background { PaperSheet(lift: PaperSheet.Lift(radius: 12, y: 8, opacity: 0.3)) }
                .rotationEffect(.degrees(-2))

                LimitCounter(count: caption.count, limit: Self.captionLimit)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, -Space.m)

                PrimaryButton("Add to Moments · +10") {
                    onSave(caption.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .task {
            let image = image
            film = await Task.detached(priority: .userInitiated) { InstantFilm.develop(image) }.value
        }
    }
}
