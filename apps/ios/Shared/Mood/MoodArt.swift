import Design
import SwiftUI

extension PartnerMood {
    /// The mood's cat face in `Moods.xcassets`.
    var artName: String {
        switch self {
        case .happy: "mood-happy"
        case .sleepy: "mood-sleepy"
        case .missing: "mood-missing"
        case .busy: "mood-busy"
        }
    }
}

/// A mood as the app draws it: a clay cat face, or the plain one when nobody has shared a mood.
/// Decorative: the words beside it, or the control holding it, say the mood to VoiceOver.
struct MoodArt: View {
    static let neutralName = "mood-none"

    let mood: PartnerMood?
    var size: CGFloat = 40

    var body: some View {
        Image(mood?.artName ?? Self.neutralName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#Preview("Moods") {
    VStack(spacing: Space.l) {
        ForEach([28, 48], id: \.self) { size in
            HStack(spacing: Space.l) {
                ForEach(PartnerMood.allCases, id: \.self) { MoodArt(mood: $0, size: CGFloat(size)) }
                MoodArt(mood: nil, size: CGFloat(size))
            }
        }
    }
    .padding(Space.gutter)
    .background(Ink.screen)
}
