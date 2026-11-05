import SwiftUI
import TipKit

/// The hints after the onboarding. `HintPlan` picks which one a screen visit shows and puts its id in
/// `HintStage.current`; each tip's rule only matches that id, so TipKit draws exactly the planned one. Copy is short
/// and warm, at most two lines.
nonisolated protocol HintTip: Tip {
    /// The id sent with the hint's analytics events and used as the TipKit id.
    static var hintId: String { get }
}

/// The one hint the current screen visit shows; empty for none.
nonisolated struct HintStage {
    @Parameter static var current: String = ""
}

nonisolated extension HintTip {
    var id: String { Self.hintId }
    /// Once on screen, never again: a popover a sheet pushed away doesn't come back after it.
    var options: [any TipOption] { [Tips.MaxDisplayCount(1)] }
}

/// Mochi herself, on her portrait in the room's corner.
nonisolated struct PetHint: HintTip {
    static let hintId = "pet"

    var title: Text { Text("Say hi to \(CatProfile.name())") }
    var message: Text? { Text("Tap her in the room to pet her. Her portrait opens her card.") }
    var image: Image? { Image(systemName: "hand.wave.fill") }
    var rules: [Rule] { [#Rule(HintStage.$current) { $0 == "pet" }] }
}

/// The "+" beside the tab bar.
nonisolated struct AddHint: HintTip {
    static let hintId = "add"

    var title: Text { Text("Leave something for your partner") }
    var message: Text? { Text("Notes, photos, wishes and plans start here. Each one earns coins.") }
    var image: Image? { Image(systemName: "heart.text.square.fill") }
    var rules: [Rule] { [#Rule(HintStage.$current) { $0 == "add" }] }
}

/// The Moments tab.
nonisolated struct MomentsHint: HintTip {
    static let hintId = "moments"

    var title: Text { Text("Everything you two add") }
    var message: Text? { Text("Your notes and photos, as a feed or pinned on \(CatProfile.name())'s board.") }
    var image: Image? { Image(systemName: "photo.on.rectangle.angled") }
    var rules: [Rule] { [#Rule(HintStage.$current) { $0 == "moments" }] }
}

/// The Shop tab.
nonisolated struct ShopHint: HintTip {
    static let hintId = "shop"

    var title: Text { Text("Coins for cosy things") }
    var message: Text? { Text("Notes and photos earn coins. Spend them on furniture, decor and treats.") }
    var image: Image? { Image(systemName: "bag.fill") }
    var rules: [Rule] { [#Rule(HintStage.$current) { $0 == "shop" }] }
}

/// The Room/City switch.
nonisolated struct RoomsHint: HintTip {
    static let hintId = "rooms"

    var title: Text { Text("\(CatProfile.name()) has a city flat too") }
    var message: Text? { Text("Switch rooms here to visit her other place.") }
    var image: Image? { Image(systemName: "building.2.fill") }
    var rules: [Rule] { [#Rule(HintStage.$current) { $0 == "rooms" }] }
}

/// Treats, on her portrait again: the Treat button lives in the card it opens.
nonisolated struct TreatHint: HintTip {
    static let hintId = "treat"

    var title: Text { Text("A treat goes further") }
    var message: Text? { Text("Her card has treats: one fills her bar more than a pet, for \(ShopModel.treatPrice) coins.") }
    var image: Image? { Image(systemName: "fork.knife") }
    var rules: [Rule] { [#Rule(HintStage.$current) { $0 == "treat" }] }
}
