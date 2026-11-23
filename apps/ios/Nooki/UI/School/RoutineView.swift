import Design
import FeatureSchool
import SchoolInterface
import SwiftUI

/// A routine being picked, tried in the room and sent to the partner as it went.
struct RoutineView: View {
    let routine: RoutineMachine.State
    let book: SchoolBook
    let cat: String
    let partner: String
    let store: SchoolStore

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("A routine for \(partner)", symbol: "list.number")
            switch routine {
            case .picking(let picks): picking(picks)
            case .tried(let take):
                TakeLines(take: take)
                PrimaryButton("Send to \(partner)", symbol: "paperplane.fill") { store.send(.routine(.send)) }
                    .accessibilityIdentifier("schoolSend")
                SecondaryButton("Change it", symbol: "arrow.uturn.backward") { store.send(.routine(.again)) }
            case .sending(let take):
                TakeLines(take: take)
                PrimaryButton("Sending…", symbol: "paperplane.fill") {}
                    .disabled(true)
            case .failed(let take):
                TakeLines(take: take)
                ErrorLine("It was not sent.")
                RetryButton { store.send(.routine(.send)) }
            case .sent(let take):
                TakeLines(take: take)
                Text("Sent. \(partner) will see \(cat) do it just like this.")
                    .font(.ourioCallout)
                    .foregroundStyle(Ink.textSecondary)
                PrimaryButton("Back to the tricks", symbol: "chevron.backward") { store.send(.back) }
            }
        }
    }

    @ViewBuilder private func picking(_ picks: [SchoolTrick]) -> some View {
        Text(picks.isEmpty ? "Pick three to five tricks, in order." : picks.map(\.title).joined(separator: " → "))
            .font(.ourioCallout)
            .foregroundStyle(picks.isEmpty ? Ink.textSecondary : Ink.text)
            .accessibilityIdentifier("schoolPicks")
        FlowRow(spacing: Space.s) {
            ForEach(book.known, id: \.self) { trick in
                PillButton(trick.title, symbol: "plus") { store.send(.routine(.pick(trick))) }
                    .disabled(picks.count >= RoutineTake.length.upperBound)
                    .accessibilityIdentifier("schoolPick-\(trick.rawValue)")
            }
            if !picks.isEmpty {
                PillButton("Undo", symbol: "delete.backward") { store.send(.routine(.removeLast)) }
            }
        }
        PrimaryButton("Try it", symbol: "play.fill") {
            let stars = Dictionary(uniqueKeysWithValues: book.skills.map { ($0.key, $0.value.stars) })
            store.send(.routine(.tryIt(rolls: picks.map { _ in .random(in: 0..<1) }, stars: stars, at: .now)))
        }
        .disabled(!RoutineTake.length.contains(picks.count))
        .accessibilityIdentifier("schoolTry")
    }
}
