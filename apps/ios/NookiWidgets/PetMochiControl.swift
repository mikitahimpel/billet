import SwiftUI
import WidgetKit

/// Control Center and Lock Screen button: Mochi purrs without opening the app.
struct PetMochiControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.mikitahimpel.billet.pet") {
            ControlWidgetButton(action: PetMochiIntent()) {
                Label("Pet Mochi", systemImage: "pawprint.fill")
            }
        }
        .displayName("Pet Mochi")
        .description("Mochi purrs, no need to open Billet.")
    }
}
