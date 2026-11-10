import OurioShared
import ProfileInterface

// The app's own types where Wire has one of the same name, as when Shared's sources were compiled into each target:
// a name declared in the target wins over both imports.
typealias CatProfile = ProfileInterface.CatProfile
typealias DateIdea = OurioShared.DateIdea
typealias GiftPlan = OurioShared.GiftPlan
typealias ListItem = OurioShared.ListItem
typealias ListKind = OurioShared.ListKind
typealias Note = OurioShared.Note
