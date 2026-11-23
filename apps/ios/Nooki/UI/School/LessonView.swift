import Design
import FeatureSchool
import SchoolInterface
import SwiftUI

/// One lesson: the cue runs along a bar, and a tap while it crosses a lit part is a hit.
struct LessonView: View {
    let lesson: LessonMachine.State
    let cat: String
    let saving: SchoolMachine.Saving
    let store: SchoolStore

    private var run: LessonMachine.Run { lesson.run }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("\(run.plan.trick.title), star \(run.plan.star)", symbol: "graduationcap")
            Text("Round \(run.round + 1) of \(run.plan.rounds.count). \(run.hits) of \(run.plan.needed) good ones.")
                .font(.ourioCallout)
                .foregroundStyle(Ink.textSecondary)
            switch lesson {
            case .cue(let run):
                CueBar(round: run.current, taps: run.taps.count, store: store)
                    .id(run.round)
            case .judged(_, let hit):
                Text(hit ? "Yes! \(cat) did it." : "\(cat) had other plans.")
                    .font(.ourioValue)
                    .foregroundStyle(Ink.text)
                PrimaryButton("Next", symbol: "arrow.forward") { store.send(.lesson(.next)) }
                    .accessibilityIdentifier("schoolNext")
            case .passed:
                Text("\(cat) earned a star for \(run.plan.trick.title).")
                    .font(.ourioValue)
                    .foregroundStyle(Ink.text)
                if case .failed = saving {
                    ErrorLine("The star was not saved.")
                    RetryButton { store.send(.retrySave) }
                }
                PrimaryButton("Back to the tricks", symbol: "chevron.backward") { store.send(.back) }
                    .accessibilityIdentifier("schoolLessonDone")
            case .missed:
                Text("Not this time. Nothing is lost: \(cat) can practise whenever you like.")
                    .font(.ourioCallout)
                    .foregroundStyle(Ink.text)
                PrimaryButton("Back to the tricks", symbol: "chevron.backward") { store.send(.back) }
            }
        }
    }
}

/// The running cue of one round and its button. The round ends itself when the cue reaches the end.
private struct CueBar: View {
    let round: LessonPlan.Round
    let taps: Int
    let store: SchoolStore

    @State private var began = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func progress(_ now: Date) -> Double { min(1, max(0, now.timeIntervalSince(began) / round.seconds)) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            TimelineView(.animation) { timeline in
                let at = progress(timeline.date)
                Canvas { context, size in
                    let track = Path(roundedRect: CGRect(origin: .zero, size: size), cornerSize: CGSize(width: size.height / 2, height: size.height / 2))
                    context.fill(track, with: .color(Ink.well))
                    for (index, window) in round.windows.enumerated() {
                        let lit = CGRect(x: size.width * window.lowerBound, y: 0, width: size.width * (window.upperBound - window.lowerBound), height: size.height)
                        context.fill(Path(lit), with: .color(index < taps ? Ink.honeyDeep : Ink.sage))
                    }
                    let mark = CGRect(x: size.width * at - size.height / 4, y: 0, width: size.height / 2, height: size.height)
                    context.fill(Path(ellipseIn: mark), with: .color(Ink.text))
                }
                .frame(height: Size.pill)
                .clipShape(.capsule)
            }
            .accessibilityHidden(true)
            PrimaryButton(round.windows.count > 1 ? "Now! (\(taps + 1) of \(round.windows.count))" : "Now!", symbol: "hand.tap") {
                store.send(.lesson(.tapped(progress(.now))))
            }
            .accessibilityHint("Tap while the mark crosses the lit part of the bar")
            .accessibilityIdentifier("schoolTap")
        }
        .task {
            began = .now
            try? await Task.sleep(for: .seconds(round.seconds))
            guard !Task.isCancelled else { return }
            store.send(.lesson(.cueEnded))
        }
    }
}
