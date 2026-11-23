import Design
import FeatureSchool
import SchoolInterface
import SwiftUI

/// The cat school, over the room so the cat is seen doing what is asked: the tricks and their stars, a lesson,
/// a routine being made, or the partner's routine playing. Nothing here runs out or is lost.
struct SchoolSheet: View {
    let store: SchoolStore
    let cat: String
    let partner: String
    /// This phone's account, to say who taught a trick.
    let viewer: String?

    var body: some View {
        BilletSheet("Cat school", size: .fit) {
            if let desk = store.state.desk {
                VStack(alignment: .leading, spacing: Space.section) {
                    switch desk.screen {
                    case .closed, .list: list(desk)
                    case .lesson(let lesson): LessonView(lesson: lesson, cat: cat, saving: desk.saving, store: store)
                    case .routine(let routine): RoutineView(routine: routine, book: desk.book, cat: cat, partner: partner, store: store)
                    case .watching(let take): watching(take)
                    }
                }
            }
        }
        .accessibilityIdentifier("schoolSheet")
    }

    private func list(_ desk: SchoolMachine.Desk) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if let take = desk.book.partner {
                Card(warm: true) {
                    VStack(alignment: .leading, spacing: Space.m) {
                        Text("\(partner) sent a routine")
                            .font(.ourioValue)
                            .foregroundStyle(Ink.text)
                        Text("\(take.landed) of \(take.steps.count) tricks landed.")
                            .font(.ourioCallout)
                            .foregroundStyle(Ink.textSecondary)
                        SecondaryButton("Watch it", symbol: "play.fill") { store.send(.watchPartner) }
                            .accessibilityIdentifier("schoolWatch")
                    }
                }
            }
            ForEach(SchoolTrick.allCases, id: \.self) { trick in
                TrickRow(trick: trick, skill: desk.book.skills[trick], next: desk.book.nextStar(of: trick),
                         teacher: teacher(desk.book.skills[trick]), busy: desk.saving.isBusy, store: store)
            }
            if case .failed = desk.saving {
                ErrorLine("The last star was not saved.")
                RetryButton { store.send(.retrySave) }
            }
            PrimaryButton("Make a routine", symbol: "list.number") { store.send(.buildRoutine) }
                .disabled(!desk.book.canBuildRoutine)
                .accessibilityHint("String the tricks \(cat) knows together and send the take to \(partner)")
                .accessibilityIdentifier("schoolRoutine")
        }
    }

    private func teacher(_ skill: TrickSkill?) -> String? {
        guard let skill else { return nil }
        return skill.teacher == viewer ? "Taught by you" : "Taught by \(partner)"
    }

    private func watching(_ take: RoutineTake) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("\(partner)'s routine", symbol: "play.fill")
            TakeLines(take: take)
            PrimaryButton("Back to the tricks", symbol: "chevron.backward") { store.send(.back) }
        }
    }
}

private struct TrickRow: View {
    let trick: SchoolTrick
    let skill: TrickSkill?
    let next: Int?
    let teacher: String?
    let busy: Bool
    let store: SchoolStore

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(spacing: Space.s) {
                    Text(trick.title)
                        .font(.ourioValue)
                        .foregroundStyle(Ink.text)
                    Spacer()
                    Stars(count: skill?.stars ?? 0)
                }
                if let teacher {
                    Text(teacher)
                        .font(.ourioCaption)
                        .foregroundStyle(Ink.textSecondary)
                }
                HStack(spacing: Space.s) {
                    if skill != nil {
                        PillButton("Ask", symbol: "hand.wave") { store.send(.ask(trick, roll: .random(in: 0..<1))) }
                            .accessibilityIdentifier("schoolAsk-\(trick.rawValue)")
                    }
                    if next != nil {
                        PillButton(skill == nil ? "Teach" : "Practise", symbol: "graduationcap") {
                            store.send(.teach(trick, seed: .random(in: 0...UInt64.max)))
                        }
                        .disabled(busy)
                        .accessibilityIdentifier("schoolTeach-\(trick.rawValue)")
                    }
                }
            }
        }
    }
}

private struct Stars: View {
    let count: Int

    var body: some View {
        HStack(spacing: Space.xxs) {
            ForEach(1...TrickSkill.maxStars, id: \.self) { star in
                Image(systemName: star <= count ? "star.fill" : "star")
                    .foregroundStyle(star <= count ? Ink.honey : Ink.textTertiary)
            }
        }
        .font(.ourioCallout)
        .accessibilityElement()
        .accessibilityLabel("\(count) of \(TrickSkill.maxStars) stars")
    }
}

/// How a take went, one line a trick.
struct TakeLines: View {
    let take: RoutineTake

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(Array(take.steps.enumerated()), id: \.offset) { _, step in
                    Label(step.trick.title, systemImage: step.landed ? "checkmark.circle.fill" : "moon.zzz.fill")
                        .font(.ourioCallout)
                        .foregroundStyle(step.landed ? Ink.text : Ink.textSecondary)
                        .accessibilityLabel("\(step.trick.title), \(step.landed ? "landed" : "did something else")")
                }
            }
        }
    }
}
