import Ink
import MomentsInterface
import WidgetInterface
import WidgetUI
import SwiftUI
import Design
import Transport
import UsInterface
import Wire

struct DrawGuessScreen: View {
    let state: HomeState
    let model: DrawGuessModel

    @Environment(ServerSession.self) private var session: ServerSession?
    @State private var drawing: Word?
    @State private var ownWord = ""
    @State private var givingUp = false
    @State private var tapped = 0

    private var partner: String { state.profile.name(of: state.otherPartner) }

    private struct Word: Identifiable {
        let text: String
        var id: String { text }
    }

    var body: some View {
        BilletSheet("Draw & guess", scrolls: false) {
            VStack(spacing: 0) {
                if let subtitle {
                    SheetSubtitle(text: subtitle)
                        .padding(.horizontal, Space.gutter)
                }
                content
                    .frame(maxHeight: .infinity)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: tapped)
        .sensoryFeedback(.error, trigger: model.misses)
        .task { await model.load() }
        .fullScreenCover(item: $drawing) { picked in
            let word = picked.text
            LockCanvasView(
                state: state, api: session?.api, model: DrawModel(room: nil, partnerName: partner),
                riddle: .init(word: word) { strokes, canvas in
                    guard let encoded = try? DrawModel.encoded(strokes, canvas: canvas) else { return false }
                    return await model.send(word: word, png: encoded.png, compact: encoded.compact)
                })
        }
    }

    private var subtitle: String? {
        switch model.phase {
        case .guess, .waiting, .draw, .ended:
            if model.series > 0 { return DrawGuessModel.seriesLine(model.series) }
            return model.best > 0 ? "Best: \(model.best) in a row" : nil
        case .offline: return "Offline"
        case .loading, .unpaired: return nil
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .unpaired:
            EmptyState(icon: UsGlyph(symbol: "person.2.fill", tint: .honey), title: "Pair up to play",
                    text: "Draw & guess takes two: one of you draws a word, the other guesses it from the letters.")
        case .offline:
            VStack(spacing: Space.l) {
                EmptyState(icon: UsGlyph(symbol: "wifi.slash", tint: .sky), title: "Can't reach your riddles",
                        text: "Riddles wait in your room on the server, so the game needs a connection.")
                RetryButton { Task { await model.load() } }
            }
        case .guess:
            if let riddle = model.theirs { guess(riddle) }
        case .waiting:
            if let riddle = model.mine { waiting(riddle) }
        case .draw:
            pick
        case .ended:
            if let riddle = model.finished { ended(riddle) }
        }
    }

    // MARK: Guess

    private func guess(_ riddle: Riddle) -> some View {
        ScrollView {
            VStack(spacing: Space.l) {
                RiddleReplay(riddle: riddle, animated: true, download: session?.api.downloadImage)
                Text(riddle.tries == 0 ? "\(partner) drew you a riddle"
                                       : "\(riddle.tries) \(riddle.tries == 1 ? "try" : "tries") so far")
                    .font(.ourioCallout)
                    .foregroundStyle(Ink.textSecondary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: riddle.tries)
                RiddleBlanks(shape: riddle.shape, slots: model.slots) { slot in model.takeBack(slot) }
                    .disabled(model.busy)
                RiddleTiles(tiles: model.tiles, count: riddle.tiles.count, misses: model.misses) { tile in
                    tapped += 1
                    Task { await model.place(tile.index) }
                }
                .disabled(model.busy)
                if model.unsent {
                    Text("That didn't reach \(partner)'s room. Try again.")
                        .font(.ourioCaption)
                        .foregroundStyle(Ink.accentText)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: Space.m) {
                    Button { Task { await model.hint() } } label: {
                        HStack(spacing: Space.s) {
                            WhoKnowsArt(name: "DrawGuess-hint", size: 32)
                            Text(riddle.hints == 0 ? "Mochi's hint" : "Another hint")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!model.canHint || model.busy)
                    .accessibilityLabel(riddle.hints == 0 ? "Mochi's hint: takes away some extra letters"
                                                          : "Mochi's hint: shows one letter")
                    Button("Give up") { givingUp = true }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Text("Each hint costs 2 of the 10 coins a solve pays.")
                    .font(.ourioCaption)
                    .foregroundStyle(Ink.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.vertical, Space.l)
        }
        .softScrollEdges()
        .confirmationDialog("Give up on this riddle?", isPresented: $givingUp, titleVisibility: .visible) {
            Button("Give up and see the word", role: .destructive) { Task { await model.giveUp() } }
        } message: {
            Text("Your solved-in-a-row count starts again from 0.")
        }
    }

    // MARK: Waiting

    private func waiting(_ riddle: Riddle) -> some View {
        ScrollView {
            VStack(spacing: Space.m) {
                RiddleReplay(riddle: riddle, animated: false, download: session?.api.downloadImage)
                Text("Waiting for \(partner) to guess")
                    .font(.ourioTitle)
                    .foregroundStyle(Ink.text)
                    .multilineTextAlignment(.center)
                if let word = riddle.word {
                    Text("You drew “\(word)”")
                        .font(.ourioCallout)
                        .foregroundStyle(Ink.textSecondary)
                }
                Text(progress(riddle))
                    .font(.ourioCaption.monospacedDigit())
                    .foregroundStyle(Ink.textSecondary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: riddle.tries)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.vertical, Space.l)
        }
        .softScrollEdges()
    }

    private func progress(_ riddle: Riddle) -> String {
        let tries = riddle.tries == 0 ? "No tries yet" : "\(riddle.tries) \(riddle.tries == 1 ? "try" : "tries")"
        let hints = riddle.hints == 0 ? "" : " · \(riddle.hints) \(riddle.hints == 1 ? "hint" : "hints")"
        return tries + hints
    }

    // MARK: Draw

    private var pick: some View {
        let typed = DrawGuessModel.riddleWord(ownWord)
        return ScrollView {
            VStack(spacing: Space.l) {
                WhoKnowsArt(name: "DrawGuess-draw", size: 160)
                if let last = model.lastEnded, model.isMine(last), let word = last.word {
                    Text(lastLine(last, word: word))
                        .font(.ourioCallout)
                        .foregroundStyle(Ink.accentText)
                        .multilineTextAlignment(.center)
                }
                Text("Draw a riddle for \(partner)")
                    .font(.ourioTitle)
                    .foregroundStyle(Ink.text)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: Space.m) {
                    ForEach(Array(zip(["Easy", "Medium", "Hard"], model.offers)), id: \.1) { tier, word in
                        Button { drawing = Word(text: word) } label: { WordOption(tier: tier, word: word) }
                            .buttonStyle(PressScaleStyle())
                            .accessibilityLabel("\(tier): \(word)")
                            .accessibilityHint("Opens the canvas")
                    }
                    Button { model.shuffleOffers() } label: {
                        Label("Other words", systemImage: "shuffle")
                            .font(.ourioCallout)
                            .foregroundStyle(Ink.accentText)
                    }
                    .buttonStyle(PressScaleStyle())
                }
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Your own word")
                        .font(.ourioHeadline)
                        .foregroundStyle(Ink.text)
                    UsField(placeholder: "A place, a name, a joke", text: $ownWord)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit { if let typed { drawing = Word(text: typed) } }
                    Text(ownWord.isEmpty || typed != nil ? "Letters a to z, up to 12" : "Use letters a to z and single spaces, up to 12 letters")
                        .font(.ourioCaption)
                        .foregroundStyle(ownWord.isEmpty || typed != nil ? Ink.textTertiary : Ink.accentText)
                    Button("Draw it") { if let typed { drawing = Word(text: typed) } }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(typed == nil)
                }
                if model.unsent {
                    Text("The riddle didn't send. Draw it again.")
                        .font(.ourioCaption)
                        .foregroundStyle(Ink.accentText)
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.vertical, Space.l)
        }
        .softScrollEdges()
        .scrollDismissesKeyboard(.interactively)
    }

    private func lastLine(_ riddle: Riddle, word: String) -> String {
        switch riddle.state {
        case .solved: "\(partner) solved “\(word)” on try \(riddle.tries)"
        case .givenUp: "\(partner) gave up on “\(word)”"
        case .open: ""
        }
    }

    // MARK: Ended

    private func ended(_ riddle: Riddle) -> some View {
        let solved = if case .solved = riddle.state { true } else { false }
        return VStack(spacing: Space.l) {
            ScrollView {
                VStack(spacing: Space.m) {
                    WhoKnowsArt(name: solved ? "DrawGuess-solved" : "DrawGuess-giveup", size: 140)
                    Text(DrawGuessModel.endedTitle(riddle))
                        .font(.ourioTitle)
                        .foregroundStyle(Ink.text)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    if let word = riddle.word {
                        Text("The word was “\(word)”")
                            .font(.ourioHeadline)
                            .foregroundStyle(Ink.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    RiddleReplay(riddle: riddle, animated: false, download: session?.api.downloadImage)
                    if let coins = DrawGuessModel.coinsLine(riddle) {
                        HStack(spacing: Space.m) {
                            CoinIcon(size: 22)
                            Text(coins)
                                .font(.ourioHeadline.monospacedDigit())
                                .foregroundStyle(Ink.text)
                            Spacer(minLength: 0)
                            if model.series > 0 {
                                Text(DrawGuessModel.seriesLine(model.series))
                                    .font(.ourioCaption)
                                    .foregroundStyle(Ink.textSecondary)
                            }
                        }
                        .padding(CardMetrics.padding)
                        .cardSurface()
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.vertical, Space.l)
            }
            .softScrollEdges()
            PrimaryButton("Now you draw") { model.drawNext() }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.l)
    }
}

// MARK: - Pieces

/// The drawing replayed stroke by stroke at an even pace, or at once with Reduce Motion. Without strokes it shows the
/// riddle's PNG instead.
private struct RiddleReplay: View {
    let riddle: Riddle
    let animated: Bool
    var download: (@Sendable (MediaKey) async throws(TransportError) -> Data)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date.now
    @State private var image: UIImage?

    /// Points drawn per second: about four seconds for a simple drawing.
    private static let pace = 90.0
    private static let longest = 8.0

    private var strokes: [Stroke] {
        (try? InkDecoder.decode(riddle.compact)).map { DrawGuessModel.fitted($0) } ?? []
    }

    var body: some View {
        let strokes = self.strokes
        let total = strokes.reduce(0) { $0 + $1.points.count }
        let rate = max(Self.pace, Double(total) / Self.longest)
        let replays = animated && !reduceMotion && total > 0
        ZStack(alignment: .bottomTrailing) {
            // The riddle canvas draws on the default wallpaper with light ink; the card shows the same one so the
            // guesser sees what the drawer saw.
            LockWallpaperView(wallpaper: DrawModel.riddleWallpaper)
            if strokes.isEmpty {
                if let image { Image(uiImage: image).resizable().scaledToFit() }
            } else if replays {
                TimelineView(.animation) { context in
                    let shown = Int(context.date.timeIntervalSince(started) * rate)
                    InkLayer(strokes: DrawGuessModel.prefix(strokes, points: shown))
                }
            } else {
                InkLayer(strokes: strokes)
            }
            if replays {
                Button { started = .now } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.ourioHeadline)
                        .foregroundStyle(Ink.heroInk)
                        .frame(width: Size.control, height: Size.control)
                        .background(Circle().fill(.white.opacity(0.7)))
                }
                .buttonStyle(PressScaleStyle())
                .padding(Space.s)
                .accessibilityLabel("Replay the drawing")
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .corners(.card)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The drawing")
        .task(id: riddle.id) {
            started = .now
            guard strokes.isEmpty, image == nil, let download,
                  let data = try? await download(riddle.image) else { return }
            image = UIImage(data: data)
        }
    }
}

/// The word's blanks, one row per word where they fit. A placed letter goes back to the tiles on a tap.
private struct RiddleBlanks: View {
    let shape: [Int]
    let slots: [DrawGuessModel.Slot]
    var takeBack: (Int) -> Void

    var body: some View {
        FlowRow(spacing: Space.l) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                HStack(spacing: Space.s) {
                    ForEach(word, id: \.index) { slot in blank(slot) }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The word, \(slots.count) letters")
    }

    private var words: [[DrawGuessModel.Slot]] {
        var start = 0
        return shape.map { length in
            defer { start += length }
            return Array(slots[min(start, slots.count)..<min(start + length, slots.count)])
        }
    }

    @ViewBuilder
    private func blank(_ slot: DrawGuessModel.Slot) -> some View {
        let letter = Text((slot.letter ?? " ").uppercased())
            .font(.ourioHeadline)
            .frame(width: 26, height: 34)
        switch slot.kind {
        case .empty:
            letter
                .overlay(alignment: .bottom) { Capsule().fill(Ink.textTertiary).frame(height: 3) }
                .accessibilityLabel("Letter \(slot.index + 1), empty")
        case .revealed:
            letter
                .foregroundStyle(Color.honey)
                .overlay(alignment: .bottom) { Capsule().fill(Color.honey).frame(height: 3) }
                .accessibilityLabel("Letter \(slot.index + 1), \(slot.letter ?? ""), shown by Mochi")
        case .placed:
            Button { takeBack(slot.index) } label: {
                letter
                    .foregroundStyle(Ink.text)
                    .overlay(alignment: .bottom) { Capsule().fill(Ink.text).frame(height: 3) }
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Letter \(slot.index + 1), \(slot.letter ?? "")")
            .accessibilityHint("Takes the letter back")
        }
    }
}

/// The letter tiles; they shake once for every wrong try. Each tile keeps its place, and a used one leaves a gap, so
/// the next tap lands on the letter that was there.
private struct RiddleTiles: View {
    let tiles: [DrawGuessModel.Tile]
    let count: Int
    let misses: Int
    var place: (DrawGuessModel.Tile) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Space.s), count: 6)

    var body: some View {
        let shakes = !reduceMotion
        LazyVGrid(columns: columns, spacing: Space.s) {
            let shown = Dictionary(uniqueKeysWithValues: tiles.map { ($0.index, $0) })
            ForEach(0..<count, id: \.self) { index in
                if let tile = shown[index] { button(tile) } else { Color.clear.frame(minHeight: 48) }
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: tiles)
        .keyframeAnimator(initialValue: 0.0, trigger: misses) { content, offset in
            content.offset(x: shakes ? offset : 0)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(-10, duration: 0.06)
                LinearKeyframe(10, duration: 0.08)
                LinearKeyframe(-6, duration: 0.08)
                LinearKeyframe(6, duration: 0.08)
                LinearKeyframe(0, duration: 0.06)
            }
        }
    }

    private func button(_ tile: DrawGuessModel.Tile) -> some View {
        Button { place(tile) } label: {
            Text(tile.letter.uppercased())
                .font(.ourioTitle)
                .foregroundStyle(Ink.text)
                .frame(maxWidth: .infinity, minHeight: 48)
                .cardSurface(radius: Radius.inner)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(tile.letter)
        .accessibilityHint("Puts the letter in the next blank")
        .transition(.scale.combined(with: .opacity))
    }
}

private struct WordOption: View {
    let tier: String
    let word: String

    var body: some View {
        HStack(spacing: Space.m) {
            Text(tier)
                .font(.ourioMicro)
                .foregroundStyle(Ink.accentText)
                .padding(.horizontal, Space.s)
                .padding(.vertical, Space.xs)
                .background(Capsule().fill(Ink.surfaceRaised))
            Text(word)
                .font(.ourioHeadline)
                .foregroundStyle(Ink.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "pencil.tip")
                .font(.ourioHeadline)
                .foregroundStyle(Ink.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .cardSurface(radius: Radius.control)
        .contentShape(.rect(cornerRadius: Radius.control))
    }
}
