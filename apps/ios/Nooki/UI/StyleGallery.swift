import SwiftUI

/// Settings → Labs → Style: every token and shared component from apps/ios/docs/style.md, drawn by the same code the
/// screens use, so the guide can be checked on a device in either appearance.
struct StyleGallery: View {
    @State private var dark = true
    @State private var chip = 0
    @State private var level = 0.6

    var body: some View {
        NookiForm {
            NookiSection(header: "Colour", inset: Space.m + 2, padsRows: true) {
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

            NookiSection(header: "Type", inset: Space.m + 2, padsRows: true) {
                Text("Large title").font(.nookiLargeTitle)
                Text("Title").font(.nookiTitle)
                Text("Headline").font(.nookiHeadline)
                Text("Body text for reading, in SF Pro.").font(.nookiBody)
                Text("Callout").font(.nookiCallout)
                Text("Caption").font(.nookiCaption).foregroundStyle(Ink.textSecondary)
                Text("MICRO 128").font(.nookiMicro).monospacedDigit()
            }
            .foregroundStyle(Ink.text)

            NookiSection(header: "Buttons", inset: Space.m + 2, padsRows: true) {
                Button {} label: { Text("Primary").frame(maxWidth: .infinity) }
                    .nookiPrimary()
                secondary
                Button("Tertiary") {}
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.accentText)
                Button("Erase All Data", role: .destructive) {}
            }

            NookiSection(header: "Rows") {
                NookiRowLabel(title: "A row that opens a screen", symbol: "person.2.fill", tint: .sky) { RowChevron() }
                NookiToggleRow(title: "A switch", symbol: "hand.tap.fill", tint: .honey, isOn: .constant(true))
                NookiRowLabel(title: "Erase All Data", symbol: "trash.fill", tint: .coral, destructive: true)
            }

            NookiSection(header: "Shape and chips", inset: Space.m + 2, padsRows: true) {
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

            NookiSection(header: "Materials",
                         footer: "Glass only over the room. Screens, forms and lists are clay cards on the screen.",
                         padsRows: true) {
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
            }

            NookiSection(header: "Symbols and motion", inset: Space.m + 2, padsRows: true) {
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

            NookiSection(header: "Empty state", inset: Space.m + 2, padsRows: true) {
                ContentUnavailableView {
                    Label("No moments yet", systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text("Your first photo together will live here.")
                } actions: {
                    Button("Add a moment") {}.nookiPrimary()
                }
            }
        }
        .navigationTitle("Style")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(dark ? "Light" : "Dark") { dark.toggle() }
            }
        }
        // Previews the guide in either appearance; the app itself stays dark until it switches as a whole.
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    private var secondary: some View {
        Button("Secondary") {}
            .buttonStyle(NookiSecondaryStyle())
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
