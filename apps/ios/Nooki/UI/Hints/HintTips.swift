import SwiftUI
import TipKit

/// The hints after the onboarding, one at a time and in this order: each waits for the one before it to be done or
/// closed (its `done` event). Copy is short and warm, at most two lines.
nonisolated protocol HintTip: Tip {
    /// The id sent with the hint's analytics events and used as the TipKit id.
    static var hintId: String { get }
    /// Donated once the hint is done or closed; the next hint waits for it.
    static var done: Tips.Event<Tips.EmptyDonation> { get }
}

nonisolated extension HintTip {
    var id: String { Self.hintId }
}

/// 1. Mochi herself, on her portrait in the room's corner. Waits for the onboarding.
nonisolated struct PetHint: HintTip {
    static let hintId = "pet"
    static let done = Tips.Event(id: "hint.pet.done")
    /// The onboarding has ended; no hint shows over it.
    @Parameter static var onboarded: Bool = false

    var title: Text { Text("Say hi to \(CatProfile.name())") }
    var message: Text? { Text("Tap her in the room to pet her. Her portrait opens her card.") }
    var image: Image? { Image(systemName: "hand.wave.fill") }
    var rules: [Rule] { [#Rule(Self.$onboarded) { $0 == true }] }
}

/// 2. The "+" beside the tab bar.
nonisolated struct AddHint: HintTip {
    static let hintId = "add"
    static let done = Tips.Event(id: "hint.add.done")

    var title: Text { Text("Leave something for your partner") }
    var message: Text? { Text("Notes, photos, wishes and plans start here. Each one earns coins.") }
    var image: Image? { Image(systemName: "heart.text.square.fill") }
    var rules: [Rule] { [#Rule(PetHint.done) { $0.donations.count >= 1 }] }
}

/// 3. The Moments tab.
nonisolated struct MomentsHint: HintTip {
    static let hintId = "moments"
    static let done = Tips.Event(id: "hint.moments.done")

    var title: Text { Text("Everything you two add") }
    var message: Text? { Text("Your notes and photos, as a feed or pinned on \(CatProfile.name())'s board.") }
    var image: Image? { Image(systemName: "photo.on.rectangle.angled") }
    var rules: [Rule] { [#Rule(AddHint.done) { $0.donations.count >= 1 }] }
}

/// 4. The Shop tab.
nonisolated struct ShopHint: HintTip {
    static let hintId = "shop"
    static let done = Tips.Event(id: "hint.shop.done")

    var title: Text { Text("Coins for cosy things") }
    var message: Text? { Text("Notes and photos earn coins. Spend them on furniture, decor and treats.") }
    var image: Image? { Image(systemName: "bag.fill") }
    var rules: [Rule] { [#Rule(MomentsHint.done) { $0.donations.count >= 1 }] }
}

/// 5. The Room/City switch.
nonisolated struct RoomsHint: HintTip {
    static let hintId = "rooms"
    static let done = Tips.Event(id: "hint.rooms.done")

    var title: Text { Text("\(CatProfile.name()) has a city flat too") }
    var message: Text? { Text("Switch rooms here to visit her other place.") }
    var image: Image? { Image(systemName: "building.2.fill") }
    var rules: [Rule] { [#Rule(ShopHint.done) { $0.donations.count >= 1 }] }
}

/// 6. Treats, on her portrait again: the Treat button lives in the card it opens.
nonisolated struct TreatHint: HintTip {
    static let hintId = "treat"
    static let done = Tips.Event(id: "hint.treat.done")

    var title: Text { Text("A treat goes further") }
    var message: Text? { Text("Her card has treats: one fills her bar more than a pet, for \(HomeState.treatPrice) coins.") }
    var image: Image? { Image(systemName: "fork.knife") }
    var rules: [Rule] { [#Rule(RoomsHint.done) { $0.donations.count >= 1 }] }
}

/// 7. The partner, on the couple's avatars, while there is someone to invite.
nonisolated struct InviteHint: HintTip {
    static let hintId = "invite"
    static let done = Tips.Event(id: "hint.invite.done")
    static let inviteAction = "invite"
    /// Signed in and not paired yet.
    @Parameter static var canInvite: Bool = false

    var title: Text { Text("Nooki is better with two") }
    var message: Text? { Text("Invite your partner to share \(CatProfile.name()), notes and coins.") }
    var image: Image? { Image(systemName: "heart.circle.fill") }
    var actions: [Action] { [Action(id: Self.inviteAction, title: "Invite")] }
    var rules: [Rule] {
        [#Rule(TreatHint.done) { $0.donations.count >= 1 }, #Rule(Self.$canInvite) { $0 == true }]
    }
}
