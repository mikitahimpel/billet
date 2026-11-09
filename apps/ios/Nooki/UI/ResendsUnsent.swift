import SwiftUI

/// Sends what the couple made here and the server doesn't have yet: photos, text notes and the cat's events. Each
/// goes again with `Resend`'s backoff while the server is out of reach, and at once when there is something new, when
/// the app comes to the front and when the network comes back.
struct ResendsUnsent: ViewModifier {
    /// Photos and notes go only to a partner, so pairing is a chance to send them too.
    let paired: Bool
    let photos: [UUID]
    let notes: [UUID]
    let sendPhotos: @MainActor () async -> Bool
    let sendNotes: @MainActor () async -> Bool
    let sendCatEvents: @MainActor () async -> Bool
    var resend = Resend()

    /// Bumped on each chance worth trying again at once; restarts every loop with a fresh backoff.
    @State private var round = 0
    @Environment(\.scenePhase) private var scenePhase

    private struct Key: Hashable {
        let round: Int
        var paired = false
        let ids: [UUID]
    }

    func body(content: Content) -> some View {
        content
            .task(id: Key(round: round, paired: paired, ids: photos)) { await resend.run(sendPhotos) }
            .task(id: Key(round: round, paired: paired, ids: notes)) { await resend.run(sendNotes) }
            .task(id: Key(round: round, ids: [])) { await resend.run(sendCatEvents) }
            .task {
                for await _ in NetworkReturns.stream() { round += 1 }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { round += 1 }
            }
    }
}
