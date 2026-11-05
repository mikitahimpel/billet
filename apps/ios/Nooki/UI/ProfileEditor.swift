import PhotosUI
import SwiftUI

/// Editing the couple's profile: each partner's photo and name, who is holding the phone, and the day they got
/// together. Pushed from the profile; Cancel goes back without saving.
struct ProfileEditor: View {
    let profile: CoupleStore
    @Environment(\.dismiss) private var dismiss
    @State private var names: [String: String] = [:]
    @State private var since = Date.now
    @State private var photoFor: String?
    @State private var pick: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(spacing: Space.m + 2) {
                ForEach(profile.couple.partners, id: \.self) { partner in
                    partnerCard(partner)
                }
                togetherCard
            }
            .padding(.horizontal, Space.gutter)
            .padding(.vertical, Space.s)
        }
        .scrollIndicators(.hidden)
        .background(Ink.screen.ignoresSafeArea())
        .tint(.honey)
        .navigationTitle("Edit profile")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    profile.update(names: names, togetherSince: since)
                    dismiss()
                }
                .fontWeight(.semibold)
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
        HStack(spacing: 14) {
            Menu {
                Button("Choose photo", systemImage: "photo") { photoFor = partner }
                if profile.photos[partner] != nil {
                    Button("Remove photo", systemImage: "trash", role: .destructive) { profile.setPhoto(nil, for: partner) }
                }
            } label: {
                Monogram(partner: partner, profile: profile, size: 64)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill")
                            .font(.nookiMicro)
                            .foregroundStyle(Ink.heroInk)
                            .frame(width: 24, height: 24)
                            .background(.honeyGradient, in: .circle)
                            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("Name", text: Binding(get: { names[partner] ?? "" }, set: { names[partner] = $0 }))
                    .font(.nookiHeadline)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(Ink.surfaceRaised, in: .rect(cornerRadius: Radius.control))

                if profile.couple.viewer == partner {
                    Label("This phone", systemImage: "iphone")
                        .font(.nookiCaption)
                        .foregroundStyle(Ink.accentText)
                } else if profile.couple.pair == nil {
                    Button("This is me") { profile.setViewer(partner) }
                        .font(.nookiCaption)
                        .foregroundStyle(Ink.textSecondary)
                }
            }
        }
        .padding(Space.m + 2)
        .nookiCard()
    }

    private var togetherCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            DatePicker("Together since", selection: $since, in: ...Date.now, displayedComponents: .date)
                .font(.nookiHeadline)
                .foregroundStyle(Ink.text)
            Text("Day \(Couple(partners: profile.couple.partners, togetherSince: since, viewer: profile.couple.viewer).daysTogether()) together")
                .font(.nookiCaption)
                .foregroundStyle(Ink.textSecondary)
        }
        .padding(Space.m + 2)
        .nookiCard()
    }
}
