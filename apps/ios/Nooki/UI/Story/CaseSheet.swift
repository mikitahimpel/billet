import Design
import FeatureStory
import StoryInterface
import SwiftUI

/// The case file, as a sheet over the board: the beats so far, one clue at a time, the naming and the ending.
struct CaseSheet: View {
    let store: CaseStore
    let cat: String
    let partner: String

    var body: some View {
        BilletSheet(title, size: .large) {
            VStack(alignment: .leading, spacing: Space.section) {
                switch store.state {
                case .file(let book): File(book: book, store: store, cat: cat, partner: partner)
                case .clue(let book, let beat, let sending):
                    Clue(book: book, beat: beat, sending: sending, store: store, cat: cat, partner: partner)
                case .naming(let book, let choice, let sending):
                    Naming(book: book, choice: choice, sending: sending, store: store, partner: partner)
                case .ending(let book, let sending):
                    Ending(book: book, sending: sending, cat: cat, partner: partner)
                case .unavailable, .loading, .closed: EmptyView()
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.section)
        }
    }

    private var title: String { store.state.book?.episode.title ?? "" }
}

private func fill(_ text: String, _ cat: String, _ partner: String) -> String {
    Episode.filled(text, cat: cat, partner: partner)
}

private struct SendingNote: View {
    let sending: CaseMachine.Sending

    var body: some View {
        if sending == .failed {
            Text("The room didn't answer. Nothing is lost; try again whenever.")
                .font(.ourioCaption)
                .foregroundStyle(Ink.textSecondary)
        }
    }
}

private struct File: View {
    let book: CaseMachine.Book
    let store: CaseStore
    let cat: String
    let partner: String

    var body: some View {
        let progress = book.progress
        Text(fill(book.episode.opening, cat, partner))
            .font(.ourioBody)
            .foregroundStyle(Ink.text)
        VStack(spacing: Space.s) {
            ForEach(Array(book.episode.beats.enumerated()), id: \.element.id) { index, beat in
                BeatRow(cat: cat, beat: beat, state: progress.beats[index], opensOn: index == nextIndex(progress) ? progress.opensOn : nil, partner: partner) {
                    store.send(.lookCloser(beat: index))
                }
            }
        }
        footer(progress.stage)
    }

    private func nextIndex(_ progress: CaseProgress) -> Int? {
        if case .clues(let next) = progress.stage { next } else { nil }
    }

    @ViewBuilder
    private func footer(_ stage: CaseProgress.Stage) -> some View {
        switch stage {
        case .clues:
            EmptyView()
        case .naming:
            VStack(alignment: .leading, spacing: Space.s) {
                Text(book.episode.ask).font(.ourioHeadline).foregroundStyle(Ink.text)
                Text("You each name one suspect. Neither of you sees the other's until both are in.")
                    .font(.ourioCaption).foregroundStyle(Ink.textSecondary)
                PrimaryButton("Name a suspect", symbol: "magnifyingglass") { store.send(.nameSuspect) }
            }
        case .named(let choice):
            let name = book.episode.suspect(choice)?.name ?? ""
            Text("You said \(name). \(partner)'s answer isn't in yet, and there's no rush.")
                .font(.ourioCallout).foregroundStyle(Ink.textSecondary)
        case .readyToTell:
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Both answers are in.").font(.ourioHeadline).foregroundStyle(Ink.text)
                PrimaryButton("Hear how it ended", symbol: "sparkles") { store.send(.watchEnding) }
            }
        case .told(let verdict):
            VStack(alignment: .leading, spacing: Space.s) {
                Text(fill(verdictLine(verdict), cat, partner)).font(.ourioCallout).foregroundStyle(Ink.textSecondary)
                SecondaryButton("Hear it again", symbol: "arrow.counterclockwise") { store.send(.watchEnding) }
            }
        }
    }

    private func verdictLine(_ verdict: CaseProgress.Verdict) -> String {
        switch verdict {
        case .both: book.episode.ending.verdicts.both
        case .one: book.episode.ending.verdicts.one
        case .none: book.episode.ending.verdicts.none
        }
    }
}

private struct BeatRow: View {
    let cat: String
    let beat: Episode.Beat
    let state: CaseProgress.BeatState
    let opensOn: Date?
    let partner: String
    let open: () -> Void

    var body: some View {
        switch state {
        case .notYet:
            row(symbol: "ellipsis", title: "Nothing new yet", detail: opensOn == nil ? "This one waits for the clue before it." : "\(cat) is still working on it. Back tomorrow, or any day after.", enabled: false)
        case .waiting(let partnerLooked):
            row(symbol: "magnifyingglass", title: beat.place, detail: partnerLooked ? "\(partner) has already had a look." : "Something is different here.", enabled: true)
        case .looked(let partnerLooked):
            row(symbol: "checkmark", title: beat.title, detail: partnerLooked ? "Both looked." : "You looked. Tell \(partner) what you saw.", enabled: true)
        case .compared:
            row(symbol: "checkmark.circle.fill", title: beat.title, detail: "Compared.", enabled: true)
        }
    }

    private func row(symbol: String, title: String, detail: String, enabled: Bool) -> some View {
        Button(action: open) {
            HStack(spacing: Space.m) {
                Image(systemName: symbol)
                    .frame(width: Size.control, height: Size.control)
                    .foregroundStyle(enabled ? Ink.accentText : Ink.textTertiary)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(title).font(.ourioHeadline).foregroundStyle(enabled ? Ink.text : Ink.textSecondary)
                    Text(detail).font(.ourioCaption).foregroundStyle(Ink.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(CardMetrics.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(radius: Radius.inner)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
    }
}

private struct Clue: View {
    let book: CaseMachine.Book
    let beat: Int
    let sending: CaseMachine.Sending
    let store: CaseStore
    let cat: String
    let partner: String

    var body: some View {
        let data = book.episode.beats[beat]
        let state = book.progress.beats[beat]
        let mine = ClueSplit.half(of: data, at: beat, side: book.side)
        let theirs = ClueSplit.half(of: data, at: beat, side: book.side.other)
        Text(data.place).font(.ourioCallout).foregroundStyle(Ink.textSecondary)
        switch state {
        case .notYet:
            EmptyView()
        case .waiting:
            VStack(spacing: Space.l) {
                Image(systemName: "magnifyingglass").font(.ourioNumber).foregroundStyle(Ink.accentText)
                Text("Something is different here. Take a look.")
                    .font(.ourioTitle).foregroundStyle(Ink.text).multilineTextAlignment(.center)
                SendingNote(sending: sending)
                PrimaryButton("Look closer", symbol: "eye") { store.send(.found) }
                    .disabled(sending == .sending)
            }
            .frame(maxWidth: .infinity)
        case .looked, .compared:
            half(mine, title: "What you found")
            if case .compared = state {
                half(theirs, title: "What \(partner) found")
                Text(fill(data.together, cat, partner)).font(.ourioHeadline).foregroundStyle(Ink.text)
            } else {
                Text("\(partner)'s half is different from yours. Tell them what you saw, in the app or over dinner.")
                    .font(.ourioCallout).foregroundStyle(Ink.textSecondary)
            }
        }
        SecondaryButton("Back to the case file", symbol: "chevron.left") { store.send(.back) }
    }

    private func half(_ half: Episode.Half, title: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title).font(.ourioCaption).foregroundStyle(Ink.textSecondary)
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: half.symbol).font(.ourioTitle).foregroundStyle(Ink.accentText)
                Text(fill(half.text, cat, partner)).font(.ourioBody).foregroundStyle(Ink.text)
            }
            .padding(CardMetrics.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(radius: Radius.inner)
        }
    }
}

private struct Naming: View {
    let book: CaseMachine.Book
    let choice: String?
    let sending: CaseMachine.Sending
    let store: CaseStore
    let partner: String

    var body: some View {
        Text(book.episode.ask).font(.ourioTitle).foregroundStyle(Ink.text)
        VStack(spacing: Space.s) {
            ForEach(book.episode.suspects) { suspect in
                Button { store.send(.choose(suspect.id)) } label: {
                    HStack(spacing: Space.m) {
                        Image(systemName: choice == suspect.id ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(Ink.accentText)
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text(suspect.name).font(.ourioHeadline).foregroundStyle(Ink.text)
                            Text(suspect.blurb).font(.ourioCaption).foregroundStyle(Ink.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(CardMetrics.padding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface(radius: Radius.inner)
                }
                .buttonStyle(PressScaleStyle())
            }
        }
        Text("\(partner) names one too. You see theirs once yours is in.")
            .font(.ourioCaption).foregroundStyle(Ink.textSecondary)
        SendingNote(sending: sending)
        PrimaryButton("That's my answer", symbol: "checkmark") { store.send(.confirmName) }
            .disabled(choice == nil || sending == .sending)
        SecondaryButton("Back to the case file", symbol: "chevron.left") { store.send(.back) }
    }
}

private struct Ending: View {
    let book: CaseMachine.Book
    let sending: CaseMachine.Sending
    let cat: String
    let partner: String

    var body: some View {
        let ending = book.episode.ending
        Text(ending.title).font(.ourioLargeTitle).foregroundStyle(Ink.text)
        ForEach(Array(ending.lines.enumerated()), id: \.offset) { _, line in
            Text(fill(line, cat, partner)).font(.ourioBody).foregroundStyle(Ink.text)
        }
        if case .readyToTell(let verdict) = book.progress.stage { verdictText(verdict) }
        if case .told(let verdict) = book.progress.stage { verdictText(verdict) }
        let souvenir = book.episode.souvenir
        HStack(spacing: Space.m) {
            Image(systemName: souvenir.symbol).font(.ourioTitle).foregroundStyle(Ink.accentText)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(souvenir.name).font(.ourioHeadline).foregroundStyle(Ink.text)
                Text(souvenir.note).font(.ourioCaption).foregroundStyle(Ink.textSecondary)
            }
        }
        .padding(CardMetrics.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Radius.inner)
        SendingNote(sending: sending)
    }

    private func verdictText(_ verdict: CaseProgress.Verdict) -> some View {
        let line =
            switch verdict {
            case .both: book.episode.ending.verdicts.both
            case .one: book.episode.ending.verdicts.one
            case .none: book.episode.ending.verdicts.none
            }
        return Text(fill(line, cat, partner)).font(.ourioCallout).foregroundStyle(Ink.textSecondary)
    }
}
