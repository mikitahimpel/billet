import SwiftUI

/// Builds the app again from what is on the phone, after the account is deleted, so it opens on the first screen.
struct StartOver {
    let action: () -> Void

    func callAsFunction() { action() }
}

private struct StartOverKey: EnvironmentKey {
    static let defaultValue = StartOver {}
}

extension EnvironmentValues {
    var startOver: StartOver {
        get { self[StartOverKey.self] }
        set { self[StartOverKey.self] = newValue }
    }
}
