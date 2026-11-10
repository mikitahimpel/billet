import OurioShared
import PhotosUI
import ProfileInterface
import SwiftUI
import Design

/// The back button leaves without saving.
struct ProfileEditor: View {
    let profile: CoupleStore
    @Environment(\.dismiss) private var dismiss
    @State private var names: [String: String] = [:]
    @State private var since = Date.now
    @State private var photoFor: String?
    @State private var pick: PhotosPickerItem?

    var body: some View {
        Page {
            ForEach(profile.couple.partners, id: \.self) { partner in
                partnerCard(partner)
            }
            togetherCard
        }
        .navigationTitle("Edit profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                ConfirmButton {
                    profile.update(names: names, togetherSince: since)
                    dismiss()
                }
            }
        }
        .onAppear {
            names = Dictionary(uniqueKeysWithValues: profile.couple.partners.map { ($0, profile.couple.names?[$0] ?? "") })
            since = profile.couple.togetherSince
        }
        .photosPicker(isPresented: Binding(get: { photoFor != nil }, set: { if !$0 { photoFor = nil } }),
                      selection: $pick, matching: .images)
        .onChange(of: pick) { _, item in
            guard let item, let partner = photoFor else { return }
            Task {
                // setPhoto crops a 400 px square, so the short side needs some headroom.
                if let image = await item.loadImage(maxPixels: 1024) {
                    profile.setPhoto(image, for: partner)
                }
                pick = nil
                photoFor = nil
            }
        }
    }

    private func partnerCard(_ partner: String) -> some View {
        HStack(spacing: Space.m) {
            Menu {
                Button("Choose photo", systemImage: "photo") { photoFor = partner }
                if profile.photos[partner] != nil {
                    Button("Remove photo", systemImage: "trash", role: .destructive) { profile.setPhoto(nil, for: partner) }
                }
            } label: {
                Monogram(partner: partner, profile: profile, size: 64)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill")
                            .font(.ourioMicro)
                            .foregroundStyle(Ink.heroInk)
                            .frame(width: 24, height: 24)
                            .background(.honeyGradient, in: .circle)
                            .overlay(Circle().strokeBorder(Ink.screen, lineWidth: 1.5))
                    }
            }

            VStack(alignment: .leading, spacing: Space.s) {
                Field("Name", text: Binding(get: { names[partner] ?? "" }, set: { names[partner] = $0 }),
                      font: .ourioHeadline)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)

                if profile.couple.viewer == partner {
                    Label("This phone", systemImage: "iphone")
                        .font(.ourioCaption)
                        .foregroundStyle(Ink.accentText)
                } else if profile.couple.pair == nil {
                    Button("This is me") { profile.setViewer(partner) }
                        .font(.ourioCaption)
                        .foregroundStyle(Ink.textSecondary)
                }
            }
        }
        .padding(CardMetrics.padding)
        .cardSurface()
    }

    private var togetherCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            DatePicker("Together since", selection: $since, in: ...Date.now, displayedComponents: .date)
                .font(.ourioHeadline)
                .foregroundStyle(Ink.text)
            Text("Day \(Couple(partners: profile.couple.partners, togetherSince: since, viewer: profile.couple.viewer).daysTogether()) together")
                .font(.ourioCaption)
                .foregroundStyle(Ink.textSecondary)
        }
        .padding(CardMetrics.padding)
        .cardSurface()
    }
}
