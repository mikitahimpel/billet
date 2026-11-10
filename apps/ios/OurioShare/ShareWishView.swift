import MomentsInterface
import OurioShared
import Persistence
import ProfileInterface
import SwiftUI
import Design
import UsInterface

/// The wish a shared page becomes: its title and picture fetched from the page, then the holder's price and details.
/// Saved to the Us store in the app group; the app picks it up when it comes back, and sends it to the pair's room.
struct ShareWishView: View {
    let link: () async -> URL?
    let done: () -> Void

    @State private var url: URL?
    @State private var loading = true
    @State private var title = ""
    @State private var price = ""
    @State private var note = ""
    @State private var mostWanted = false
    @State private var image: UIImage?
    @State private var imageData: Data?
    @State private var saved = false

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                VStack(spacing: 2) {
                    Text("Add to my wishlist")
                        .font(.ourioHeadline)
                        .foregroundStyle(Ink.text)
                    if let host = url?.host().map({ $0.replacingOccurrences(of: "www.", with: "") }) {
                        Text(host)
                            .font(.ourioCaption)
                            .foregroundStyle(Ink.textSecondary)
                    }
                }
                HStack {
                    Spacer()
                    GlassIconButton(label: String(localized: "Close"), action: done) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Ink.text)
                    }
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.vertical, Space.m)
            if saved {
                savedNote
            } else {
                form
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Ink.screen)
        .task { await start() }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if loading || image != nil { picture }
                UsField(placeholder: String(localized: "What would you love?"), text: $title)
                UsField(placeholder: String(localized: "Price (optional)"), text: $price)
                UsField(placeholder: String(localized: "Colour, size, details (optional)"), text: $note)
                Toggle(isOn: $mostWanted) {
                    Label {
                        Text("Most wanted")
                            .font(.ourioCallout.weight(.semibold))
                            .foregroundStyle(Ink.text)
                    } icon: {
                        Image(systemName: mostWanted ? "star.fill" : "star")
                            .foregroundStyle(mostWanted ? Color.blushPink : Ink.textTertiary)
                    }
                }
                .tint(.blushPink)
                .fieldSurface()
                PrimaryButton(String(localized: "Add wish"), symbol: "gift.fill") { save() }
                    .opacity(trimmedTitle.isEmpty ? 0.45 : 1)
                    .disabled(trimmedTitle.isEmpty)
                    .padding(.top, Space.xs)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .softScrollEdges()
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private var picture: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Ink.surfaceRaised
                ProgressView()
            }
        }
        .frame(height: 160)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
        .accessibilityHidden(true)
    }

    private var savedNote: some View {
        VStack(spacing: Space.m) {
            Image(systemName: "heart.fill")
                .font(.system(.largeTitle, weight: .semibold))
                .foregroundStyle(Color.blushPink)
            Text("On your wishlist")
                .font(.ourioTitle)
                .foregroundStyle(Ink.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func start() async {
        url = await link()
        defer { loading = false }
        guard let url, let preview = await LinkPreview.fetch(url) else { return }
        if trimmedTitle.isEmpty, let fetched = preview.title { title = fetched }
        if let data = preview.image, let fetched = UIImage(data: data) {
            image = fetched
            imageData = data
        }
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        let owner = CoupleStore.saved()?.viewer ?? Couple.starter().viewer
        let wish = WishItem(owner: owner, title: trimmedTitle, link: url?.absoluteString ?? "",
                            price: price.trimmingCharacters(in: .whitespacesAndNewlines),
                            note: note.trimmingCharacters(in: .whitespacesAndNewlines), mostWanted: mostWanted)
        if let imageData { WishImage.save(imageData, for: wish.id) }
        UsStore().upsertWish(wish)
        SharedFile.flush()
        withAnimation(.snappy(duration: 0.25)) { saved = true }
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            done()
        }
    }
}
