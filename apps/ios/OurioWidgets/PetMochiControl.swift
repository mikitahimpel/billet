import MomentsInterface
import WidgetInterface
import WidgetUI
import ProfileInterface
import SwiftUI
import UsInterface
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
