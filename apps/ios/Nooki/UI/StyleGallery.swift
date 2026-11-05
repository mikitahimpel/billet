import SwiftUI

/// Settings → Labs → Style: every token and shared component from apps/ios/docs/style.md, drawn by the same code the
/// screens use, so the guide can be checked on a device in either appearance.
struct StyleGallery: View {
    @State private var dark = true
    @State private var chip = 0
    @State private var level = 0.6

    var body: some View {
        List {
            Section("Colour") {
                swatch("screen", Ink.screen)
                swatch("surface", Ink.surface)
                swatch("surfaceRaised", Ink.surfaceRaised)
                swatch("separator", Ink.separator)
                swatch("text", Ink.text)
                swatch("textSecondary", Ink.textSecondary)
                swatch("textTertiary", Ink.textTertiary)
                swatch("accentText", Ink.accentText)
                swatch("honey", .honey)
                swatch("honeyDeep", .honeyDeep)
                swatch("blushPink", .blushPink)
            }
            .nookiRow()

            Section("Type") {
                Text("Large title").font(.nookiLargeTitle)
                Text("Title").font(.nookiTitle)
                Text("Headline").font(.nookiHeadline)
                Text("Body text for reading, in SF Pro.").font(.nookiBody)
                Text("Callout").font(.nookiCallout)
                Text("Caption").font(.nookiCaption).foregroundStyle(Ink.textSecondary)
                Text("MICRO 128").font(.nookiMicro).monospacedDigit()
            }
            .foregroundStyle(Ink.text)
            .nookiRow()

            Section("Buttons") {
                Button {} label: { Text("Primary").frame(maxWidth: .infinity) }
                    .nookiPrimary()
                secondary
                Button("Tertiary") {}
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.accentText)
                Button("Erase All Data", role: .destructive) {}
            }
            .nookiRow()

            Section("Shape and chips") {
                HStack(spacing: Space.m) {
                    ForEach([Radius.tag, Radius.control, Radius.card, Radius.hero], id: \.self) { radius in
                        RoundedRectangle(cornerRadius: radius)
                            .fill(Ink.surfaceRaised)
                            .frame(width: 56, height: 56)
                            .overlay { Text("\(Int(radius))").font(.nookiMicro).foregroundStyle(Ink.textSecondary) }
                    }
                }
                HStack(spacing: Space.s) {
                    ForEach(Array(["Cozy", "Playful", "Sleepy"].enumerated()), id: \.offset) { index, title in
                        Button(title) { withAnimation(.snappy(duration: 0.25)) { chip = index } }
                            .font(.nookiCallout)
                            .foregroundStyle(chip == index ? Ink.text : Ink.textSecondary)
                            .padding(.horizontal, Space.m)
                            .padding(.vertical, Space.s)
                            .background(chip == index ? Ink.surfaceRaised : .clear, in: .capsule)
                            .buttonStyle(.plain)
                    }
                }
                .sensoryFeedback(.selection, trigger: chip)
            }
            .nookiRow()

            Section {
                ZStack {
                    LinearGradient(colors: [Color(hex: 0x5B3A2A), Color(hex: 0xC9814F), Color(hex: 0x2F4A3A)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    GlassGroup(spacing: Space.s) {
                        HStack(spacing: Space.s) {
                            Image(systemName: "tray.fill")
                                .font(.nookiHeadline)
                                .foregroundStyle(Ink.primary)
                                .frame(width: 42, height: 42)
                                .warmGlass(.circle, interactive: true)
                            Text("Glass over the room")
                                .font(.nookiCallout)
                                .foregroundStyle(Ink.primary)
                                .padding(.horizontal, Space.l)
                                .frame(height: 42)
                                .warmGlass(.capsule)
                        }
                    }
                }
                .frame(height: 120)
                .clipShape(.rect(cornerRadius: Radius.card))
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Materials")
            } footer: {
                Text("Glass only over the room. Screens, forms and lists are solid surfaces.")
            }
            .nookiRow()

            Section("Symbols and motion") {
                HStack(spacing: Space.l) {
                    ForEach(["fork.knife", "moon.zzz.fill", "tennisball.fill", "heart.fill"], id: \.self) {
                        Image(systemName: $0)
                    }
                }
                .font(.nookiHeadline)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.honey)
                ProgressView(value: level).tint(.honey)
                Slider(value: $level.animation(.spring(duration: 0.6, bounce: 0.2)))
            }
            .nookiRow()

            Section("Empty state") {
                ContentUnavailableView {
                    Label("No moments yet", systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text("Your first photo together will live here.")
                } actions: {
                    Button("Add a moment") {}.nookiPrimary()
                }
            }
            .nookiRow()
        }
        .scrollContentBackground(.hidden)
        .background(Ink.screen)
        .tint(.honey)
        .navigationTitle("Style")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(dark ? "Light" : "Dark") { dark.toggle() }
            }
        }
        // Previews the guide in either appearance; the app itself stays dark until it switches as a whole.
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    @ViewBuilder
    private var secondary: some View {
        let label = Button {} label: { Text("Secondary").frame(maxWidth: .infinity) }
            .font(.nookiHeadline)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        if #available(iOS 26, *) {
            label.buttonStyle(.glass)
        } else {
            label.buttonStyle(.bordered)
        }
    }

    private func swatch(_ name: String, _ colour: Color) -> some View {
        HStack(spacing: Space.m) {
            RoundedRectangle(cornerRadius: Radius.tag)
                .fill(colour)
                .overlay { RoundedRectangle(cornerRadius: Radius.tag).stroke(Ink.separator) }
                .frame(width: 36, height: 28)
            Text(name).font(.nookiCallout).foregroundStyle(Ink.text)
        }
    }
}
