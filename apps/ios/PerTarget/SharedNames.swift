import MomentsInterface
import ProfileInterface
import UsInterface

// The app's own types where Wire has one of the same name, as when Shared's sources were compiled into each target:
// a name declared in the target wins over both imports.
typealias CatProfile = ProfileInterface.CatProfile
typealias DateIdea = UsInterface.DateIdea
typealias GiftPlan = UsInterface.GiftPlan
typealias ListItem = UsInterface.ListItem
typealias ListKind = UsInterface.ListKind
typealias Note = MomentsInterface.Note
