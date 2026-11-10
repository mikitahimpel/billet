import OurioShared
import SwiftUI
import Design
import Wire

extension NoteStamp {
    var art: StampArt {
        switch self {
        case .heart: .heart
        case .moon: .moon
        case .bloom: .bloom
        case .paw: .paw
        case .sun: .sun
        }
    }
}

extension NoteSeal {
    var art: SealArt {
        switch self {
        case .rose: .rose
        case .night: .night
        case .meadow: .meadow
        case .honey: .honey
        case .plum: .plum
        }
    }
}

extension View {
    /// The note's stamp and seal, if the sender chose any, on a face `width` points wide.
    func postage(of note: Note, width: CGFloat) -> some View {
        postage(stamp: note.stamp?.art, seal: note.seal?.art, width: width)
    }
}

/// Stamp and seal are each optional, and both are free.
struct PostagePicker: View {
    @Binding var stamp: NoteStamp?
    @Binding var seal: NoteSeal?

    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            Group {
                if let stamp {
                    PostageStamp(stamp.art, width: 22)
                } else if let seal {
                    WaxSeal(seal.art, size: 26)
                } else {
                    Image(systemName: "envelope")
                        .font(.ourioCallout.weight(.semibold))
                        .foregroundStyle(Ink.text)
                }
            }
            .frame(width: Size.control, height: Size.control)
            .background(Ink.surface, in: .circle)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Stamp and seal")
        .accessibilityValue(summary)
        .accessibilityIdentifier("composerPostage")
        .popover(isPresented: $open) {
            tray.presentationCompactAdaptation(.popover)
        }
    }

    private var summary: String {
        [stamp.map { "\($0.art.name) stamp" }, seal.map { "\($0.art.name) seal" }]
            .compactMap(\.self).joined(separator: ", ").nonEmpty ?? "None"
    }

    private var tray: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("Stamp")
            HStack(spacing: Space.s) {
                none(selected: stamp == nil) { stamp = nil }
                ForEach(NoteStamp.allCases, id: \.self) { option in
                    choice(option.art.name + " stamp", selected: stamp == option) { stamp = option } label: {
                        PostageStamp(option.art, width: 26)
                    }
                }
            }
            SectionHeader("Seal")
            HStack(spacing: Space.s) {
                none(selected: seal == nil) { seal = nil }
                ForEach(NoteSeal.allCases, id: \.self) { option in
                    choice(option.art.name + " seal", selected: seal == option) { seal = option } label: {
                        WaxSeal(option.art, size: 32)
                    }
                }
            }
        }
        .padding(Space.l)
        .haptic(.selection, trigger: stamp)
        .haptic(.selection, trigger: seal)
    }

    private func none(selected: Bool, action: @escaping () -> Void) -> some View {
        choice("None", selected: selected, action: action) {
            Image(systemName: "circle.slash")
                .font(.ourioCallout)
                .foregroundStyle(Ink.textSecondary)
        }
    }

    private func choice<Label: View>(
        _ name: String, selected: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .frame(width: Size.control, height: Size.control)
                .background(selected ? Color.honey.opacity(0.22) : .clear, in: .circle)
                .overlay { Circle().strokeBorder(selected ? Color.honey : .clear, lineWidth: 2) }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
