import PhotosUI
import SwiftUI
import Design

/// Owns the drag so gesture frames redraw only the cards, not the screen that builds the deck.
struct SwipeDeck: View {
    let deck: [DateIdea]
    var onSwipe: (DateIdea, Bool) -> Void

    @State private var drag: CGSize = .zero
    @State private var flying = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let flingDistance: CGFloat = 110

    /// 0 at rest, 1 once the top card is dragged far enough to fling; the cards behind rise with it.
    private var progress: CGFloat { min(1, abs(drag.width) / Self.flingDistance) }

    var body: some View {
        VStack(spacing: 14) {
            deckStack
            HStack(spacing: 28) {
                passButton
                likeButton
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var deckStack: some View {
        ZStack(alignment: .top) {
            ForEach(Array(deck.prefix(3).enumerated()).reversed(), id: \.element.id) { index, idea in
                stackedCard(idea, index: index)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: DateIdeaCard.height + 22)
    }

    /// One view path for every position, so a card keeps its identity (and its drawn picture) while it moves from
    /// the back of the stack to the top; an if/else here would rebuild it with a crossfade.
    private func stackedCard(_ idea: DateIdea, index: Int) -> some View {
        let top = index == 0
        // Each card behind moves one step forward as the top one is dragged away.
        let depth = top ? 0 : CGFloat(index) - progress
        return DateIdeaCard(idea: idea)
            .overlay(alignment: .topLeading) {
                stamp("LOVE", tint: Color(hex: 0xE287A9), strength: top ? drag.width / Self.flingDistance : 0)
                    .padding(24)
            }
            .overlay(alignment: .topTrailing) {
                stamp("NOPE", tint: Color(hex: 0x5B3A28), strength: top ? -drag.width / Self.flingDistance : 0)
                    .padding(24)
            }
            .scaleEffect(reduceMotion ? 1 : 1 - depth * 0.05, anchor: .bottom)
            .offset(y: reduceMotion ? 0 : depth * 12)
            .rotationEffect(.degrees(top && !reduceMotion ? drag.width / 20 : 0))
            .offset(top ? drag : .zero)
            .zIndex(Double(3 - index))
            // A flung card is already off screen when it leaves; with Reduce Motion it fades where it is.
            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity, removal: .identity))
            .gesture(cardDrag, including: top ? .all : .subviews)
    }

    private func stamp(_ text: String, tint: Color, strength: CGFloat) -> some View {
        Text(text)
            .font(.system(.title, design: .rounded, weight: .heavy))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.tag, style: .continuous)
                    .stroke(tint, lineWidth: 3)
            )
            .rotationEffect(.degrees(text == "LOVE" ? -14 : 14))
            .opacity(Double(min(1, max(0, strength))))
    }

    private var passButton: some View {
        Button { fling(liked: false) } label: {
            Image(systemName: "xmark")
                .font(.system(.title2, weight: .bold))
                .foregroundStyle(Ink.text)
                .frame(width: 64, height: 64)
                .background(Ink.surfaceRaised, in: .circle)
                .overlay(Circle().stroke(Ink.separator, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pass")
    }

    private var likeButton: some View {
        Button { fling(liked: true) } label: {
            Image(systemName: "heart.fill")
                .font(.system(.title2, weight: .bold))
                .foregroundStyle(Ink.heroInk)
                .frame(width: 64, height: 64)
                .background(Circle().fill(.honeyGradient))
                .shadow(color: Color.honeyDeep.opacity(0.4), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Love")
    }

    private var cardDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !flying else { return }
                drag = value.translation
            }
            .onEnded { value in
                guard !flying else { return }
                // A quick flick counts as well as a long drag.
                let throwWidth = value.predictedEndTranslation.width
                if abs(value.translation.width) > Self.flingDistance || abs(throwWidth) > Self.flingDistance * 2.5 {
                    fling(liked: throwWidth > 0)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) { drag = .zero }
                }
            }
    }

    private func fling(liked: Bool) {
        guard !flying, !deck.isEmpty else { return }
        flying = true
        if reduceMotion {
            commitSwipe(liked: liked)
            return
        }
        // The cards behind finish rising during the throw, so the hand-off below lands on the same frame.
        withAnimation(.easeIn(duration: 0.2)) {
            drag = CGSize(width: liked ? 640 : -640, height: drag.height + 40)
        } completion: {
            commitSwipe(liked: liked)
        }
    }

    private func commitSwipe(liked: Bool) {
        guard let idea = deck.first else {
            flying = false
            return
        }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.82)) {
            onSwipe(idea, liked)
            drag = .zero
            flying = false
        }
    }
}

struct DateIdeaCard: View {
    static let height: CGFloat = 420

    let idea: DateIdea

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
        DateScenePicture(art: idea.art)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(idea.title)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(idea.pitch)
                        .font(.nookiCallout)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        tag(idea.place.title, symbol: idea.place.icon.symbol)
                        tag(idea.cost.title, symbol: idea.cost.symbol)
                        tag(idea.time.title, symbol: idea.time.symbol)
                    }
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .clipShape(shape)
            .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
            .accessibilityElement(children: .combine)
    }

    private func tag(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.nookiMicro)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.18), in: .capsule)
    }
}

/// A date scene filling its frame, darkened at the bottom so white text on it stays readable.
struct DateScenePicture: View {
    /// An idea's picture, fetched from the server; nil for the Plans backdrop, which ships with the app.
    var art: DateIdea.Art?

    /// The pictures are immutable, so `URLCache` keeps them across launches. A build without a server shows only
    /// each picture's colour.
    private static let host = Backend.baseURL(host: Bundle.main.object(forInfoDictionaryKey: Backend.infoKey) as? String)

    var body: some View {
        Color(hex: art.flatMap { UInt32($0.color.dropFirst(), radix: 16) } ?? 0x6B4A35)
            .overlay {
                if let art {
                    AsyncImage(url: Self.host?.appending(path: art.path),
                               transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                        phase.image?.resizable().scaledToFill()
                    }
                } else {
                    Image(decorative: "DateScene-plans")
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay {
                LinearGradient(stops: [.init(color: .clear, location: 0.35),
                                       .init(color: Ink.screen.opacity(0.88), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .clipped()
    }
}
