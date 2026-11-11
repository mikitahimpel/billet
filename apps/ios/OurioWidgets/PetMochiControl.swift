import ProfileInterface
import SwiftUI
import WidgetKit

/// Control Center and Lock Screen button: Mochi purrs without opening the app.
struct PetMochiControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.ourio.app.pet") {
            ControlWidgetButton(action: PetMochiIntent()) {
                Label("Pet \(CatProfile.name())", systemImage: "pawprint.fill")
            }
        }
        .displayName("Pet Your Cat")
        .description("Your cat purrs, no need to open Ourio.")
    }
}

/// Control Center and Lock Screen button: dinner for Mochi.
struct FeedMochiControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.ourio.app.feed") {
            ControlWidgetButton(action: FeedMochiIntent()) {
                Label("Feed \(CatProfile.name())", systemImage: "fork.knife")
            }
        }
        .displayName("Feed Your Cat")
        .description("Dinner for your cat, no need to open Ourio.")
    }
}

/// Control Center and Lock Screen button: a hug for the partner.
struct SendHugControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.ourio.app.hug") {
            ControlWidgetButton(action: SendHugIntent()) {
                Label("Send a Hug", systemImage: "heart.fill")
            }
        }
        .displayName("Send a Hug")
        .description("Lets your partner know you are thinking of them.")
    }
}
