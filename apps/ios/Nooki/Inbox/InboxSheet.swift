import Design
import DrawInterface
import FeatureInbox
import OurioShared
import SwiftUI
import UIKit
import Wire

/// FeatureInbox's sheet with what only the app knows: names, monograms, the cat's portrait, mood faces and the
/// delivery notice.
struct InboxSheet: View {
    let model: InboxModel
    let state: HomeState
    /// Called with a row's target after the sheet has closed.
    var open: (ActivityTarget) -> Void

    var body: some View {
        let partner = state.profile.name(of: state.otherPartner)
        InboxView(model: model, names: .app(partner: partner, cat: state.petName), open: open) { actor in
            InboxAvatar(actor: actor, state: state)
        } face: { mood in
            MoodArt(mood: PartnerMood(rawValue: mood.rawValue), size: 24)
        } notice: { insets in
            DeliveryNotice(partner: partner, insets: insets)
        }
    }
}

extension InboxLine.Names {
    /// The app's words and symbols: catalogue titles, mood names, list icons and reaction emoji.
    static func app(partner: String, cat: String) -> Self {
        Self(
            partner: partner, cat: cat, title: { Catalog.item($0)?.name },
            mood: { PartnerMood(rawValue: $0.rawValue)?.title ?? $0.rawValue },
            list: { ListKind($0).icon.symbol },
            reaction: { $0.emoji })
    }
}

private struct InboxAvatar: View {
    let actor: ActivityActor
    let state: HomeState

    var body: some View {
        switch actor {
        case .me: Monogram(partner: state.viewer, profile: state.profile, size: 40)
        case .partner: Monogram(partner: state.otherPartner, profile: state.profile, size: 40)
        case .cat:
            Group {
                if let image = UIImage(named: "MochiPortrait") {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "cat.fill").foregroundStyle(.white)
                }
            }
            .frame(width: 40, height: 40)
            .background(Color(hex: 0xF2C08A))
            .clipShape(.circle)
            .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
        case .store:
            Image(systemName: "applelogo")
                .font(.ourioHeadline)
                .foregroundStyle(Ink.text)
                .frame(width: 40, height: 40)
                .background(Ink.surfaceRaised, in: .circle)
        }
    }
}
