import DesignSystem
import SwiftUI

/// A closed envelope with a wax seal, in the app's own colours.
struct EnvelopeShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.addRoundedRect(in: rect, cornerSize: CGSize(width: 4, height: 4))
    path.move(to: CGPoint(x: rect.minX, y: rect.minY + 1))
    path.addLine(to: CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.1))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 1))
    return path
  }
}

struct SealedEnvelope: View {
  var body: some View {
    ZStack {
      EnvelopeShape().fill(Palette.paper.color)
      EnvelopeShape().stroke(Palette.inkGold.color, lineWidth: 1.2)
      Circle().fill(Palette.clay.color).frame(width: 12, height: 12).offset(y: 2)
    }
    .frame(width: 40, height: 28)
    .accessibilityHidden(true)
  }
}

/// Home's rows for the sealed notes: the ones waiting for this phone's partner, the ones waiting
/// for this phone, and a switch to seal the next note.
public struct SealedNoteSection: View {
  private let store: SealedBoxStore
  private let catName: String?

  public init(store: SealedBoxStore, catName: String?) {
    self.store = store
    self.catName = catName
  }

  public var body: some View {
    VStack(spacing: Spacing.small) {
      ForEach(store.box.notes) { note in
        row(note)
      }
      ToggleRow(
        "Seal the next note",
        subtitle: store.sealNext
          ? "It opens for your partner tomorrow at 8, and goes then."
          : "Hold it until tomorrow morning.",
        isOn: Binding(get: { store.sealNext }, set: { store.sealNext = $0 })
      )
      .card()
    }
    .calmAnimation(value: store.box.notes.map(\.id))
  }

  private func row(_ note: SealedNote) -> some View {
    let incoming = note.direction == .incoming
    return ListRow(
      incoming ? "A sealed note for you" : "Your note is sealed",
      subtitle: incoming
        ? "\(catName ?? "The cat") is sitting on it."
        : "\(catName ?? "The cat") keeps it until morning."
    ) {
      SealedEnvelope()
    } trailing: {
      Text(timerInterval: Date.now...max(note.opensAt, Date.now), countsDown: true)
        .billetType(.label)
        .monospacedDigit()
        .foregroundStyle(Palette.gold.color)
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: 80)
    }
    .card()
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("sealedNote")
  }
}
