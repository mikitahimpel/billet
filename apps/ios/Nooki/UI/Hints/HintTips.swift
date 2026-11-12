import MomentsInterface
import WidgetInterface
import WidgetUI
import ProfileInterface
import SwiftUI
import TipKit
import UsInterface

/// `HintPlan` puts the planned hint's id in `HintStage.current` and each tip's rule matches only that id, so
/// TipKit draws exactly the planned one. Copy is short and warm, at most two lines.
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

nonisolated struct PetHint: HintTip {
    static let hintId = "pet"

    var title: Text { Text("Say hi to \(CatProfile.name())") }
    var message: Text? { Text(CatProfile.pronouns().say(.tapToPet)) }
    var image: Image? { Image(systemName: "hand.wave.fill") }
    var rules: [Rule] { [#Rule(HintStage.$current) { $0 == "pet" }] }
}

/// On her portrait: the ring round it is her needs, and a tap opens them.
nonisolated struct NeedsHint: HintTip {
    static let hintId = "needs"

    var title: Text { Text("\(CatProfile.name())'s needs live here") }
    var message: Text? { Text(CatProfile.pronouns().say(.ringExplained)) }
    var image: Image? { Image(systemName: "chart.pie.fill") }
    var rules: [Rule] { [#Rule(HintStage.$current) { $0 == "needs" }] }
}

nonisolated struct AddHint: HintTip {
    static let hintId = "add"

    var title: Text { Text("Leave something for your partner") }
    var message: Text? { Text("Notes, photos, wishes and plans start here. Each one earns coins.") }
    var image: Image? { Image(systemName: "heart.text.square.fill") }
    var rules: [Rule] { [#Rule(HintStage.$current) { $0 == "add" }] }
}

nonisolated struct MomentsHint: HintTip {
    static let hintId = "moments"

    var title: Text { Text("Everything you two add") }
    var message: Text? { Text("Your notes and photos, as a feed or pinned on \(CatProfile.name())'s board.") }
    var image: Image? { Image(systemName: "photo.on.rectangle.angled") }
    var rules: [Rule] { [#Rule(HintStage.$current) { $0 == "moments" }] }
}

nonisolated struct ShopHint: HintTip {
    static let hintId = "shop"

    var title: Text { Text("Coins for cosy things") }
    var message: Text? { Text("Notes and photos earn coins. Spend them on furniture, decor and treats.") }
    var image: Image? { Image(systemName: "bag.fill") }
    var rules: [Rule] { [#Rule(HintStage.$current) { $0 == "shop" }] }
}

nonisolated struct RoomsHint: HintTip {
    static let hintId = "rooms"

    var title: Text { Text("\(CatProfile.name()) has a bedroom too") }
    var message: Text? { Text("Switch here between the living room and the bedroom.") }
    var image: Image? { Image(systemName: "building.2.fill") }
    var rules: [Rule] { [#Rule(HintStage.$current) { $0 == "rooms" }] }
}

/// On her portrait again: the Treat button lives in the sheet it opens.
nonisolated struct TreatHint: HintTip {
    static let hintId = "treat"

    var title: Text { Text("A treat goes further") }
    var message: Text? { Text(CatProfile.pronouns().say(.portraitTreats(price: ShopModel.treatPrice))) }
    var image: Image? { Image(systemName: "fork.knife") }
    var rules: [Rule] { [#Rule(HintStage.$current) { $0 == "treat" }] }
}
