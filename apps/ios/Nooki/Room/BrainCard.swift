import MomentsInterface
import WidgetInterface
import WidgetUI
import Pet
import SwiftUI
import UIKit
import Design
import UsInterface

extension AppSettings {
    /// Labs: shows the cat's brain over the room.
    static let brainCardKey = "labs.brainCard"
    /// Labs: the brain drives the cat; off, she runs on its original timers alone.
    /// Labs: the room's close-up follows Mochi's head; off, the camera frames the room and stays put.
    static let followMochiKey = "labs.followMochi"
    static let catBrainKey = "labs.catBrain"

    static var catBrain: Bool { UserDefaults.standard.object(forKey: catBrainKey) as? Bool ?? true }
}

/// Labs' window on Mochi's brain: the owner's state and the brain's own stack, her four needs, where she is and in
/// which body, the last thing that reached her, and the three activities scoring best right now.
struct BrainCard: View {
    let director: CatDirector

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            readout.allowsHitTesting(false)
            controls
            observatory
            timeline.allowsHitTesting(false)
        }
        .foregroundStyle(Ink.primary)
        .padding(Space.m)
        .frame(width: 260, alignment: .leading)
        .cornerFill(.card, Ink.screen.opacity(0.85))
        .onAppear { director.observing = true }
        .onDisappear { director.observing = false }
    }

    /// The observatory: the brain's speed, a nudge to a group or an event, and the log to paste.
    private var observatory: some View {
        FlowRow(spacing: Space.xs) {
            ForEach(CatClock.speeds, id: \.self) { speed in
                PillButton((director.speed == speed ? "• x" : "x") + "\(Int(speed))") { director.set(speed: speed) }
            }
            PillButton("Copy log") { UIPasteboard.general.string = director.log() }
            Menu {
                ForEach(CatActivityGroup.chosen, id: \.self) { group in
                    Button(group.title) { director.force(group: group) }
                }
            } label: { menuLabel("Force group") }
            Menu {
                ForEach(LifeEvent.Kind.allCases, id: \.self) { kind in
                    Button(kind.rawValue) { director.send(kind) }
                }
            } label: { menuLabel("Event") }
        }
    }

    /// The last twenty things she did, newest first, with how long each lasted.
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(director.timeline.reversed().enumerated()), id: \.offset) { _, episode in
                HStack {
                    Text("\(episode.group.rawValue)/\(episode.step.rawValue)")
                    Spacer(minLength: Space.xs)
                    Text(episode.end.map { "\(Int(($0 - episode.start).rounded())) s" } ?? "now")
                }
                .font(.ourioMicro.monospaced())
                .foregroundStyle(episode.end == nil ? Ink.primary : Ink.secondary)
            }
        }
    }

    /// Labs controls: a tour of every state, the brain's clock, a neglected cat, and the couple's touches.
    private var controls: some View {
        FlowRow(spacing: Space.xs) {
            PillButton(director.touring ? "Touring…" : "Tour") { director.startTour() }
            Menu {
                ForEach([7.0, 13, 19, 23], id: \.self) { hour in
                    Button(String(format: "%02.0f:00", hour)) { director.force(hour: hour) }
                }
                Button("Real time") { director.force(hour: nil) }
            } label: {
                menuLabel(director.forcedHour.map { String(format: "%02.0f:00", $0) } ?? "Clock")
            }
            PillButton("Alone") { director.neglect() }
            PillButton("Pet") { director.pet() }
            PillButton("Feed") { director.feed() }
            PillButton("Hello") { director.greet() }
        }
    }

    private func menuLabel(_ title: String) -> some View {
        Text(title)
            .font(.ourioCallout.weight(.semibold))
            .foregroundStyle(Ink.accentText)
            .padding(.horizontal, Space.m)
            .frame(minHeight: Size.control)
            .background(Ink.surfaceRaised, in: .capsule)
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text((director.touring ? "Tour · " : "") + (director.mind?.path ?? "starting…"))
                .font(.ourioHeadline)
            Text(director.path)
                .font(.ourioMicro.monospaced())
                .foregroundStyle(Ink.secondary)
                .lineLimit(2)
            if let needs = director.needs {
                ForEach(PetNeed.allCases, id: \.self) { need in
                    bar(need.title, needs[need])
                }
            }
            line("Body", "\(director.rest.rawValue) at \(director.spot.rawValue)")
            line("Last", director.lastEvent)
            if let reset = director.resets.last { line("Reset ×\(director.resets.count)", reset) }
            ForEach(director.top, id: \.group) { score in
                line(score.group.rawValue, String(format: "%.2f", score.score))
            }
        }
    }

    private func bar(_ title: String, _ value: Double) -> some View {
        HStack(spacing: Space.xs) {
            Text(title).font(.ourioMicro).frame(width: 52, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.hairline)
                    Capsule().fill(Color.honey).frame(width: geometry.size.width * min(max(value, 0), 1))
                }
            }
            .frame(height: Space.xs)
            Text(String(format: "%.2f", value)).font(.ourioMicro.monospaced()).frame(width: 34)
        }
    }

    private func line(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.ourioMicro).foregroundStyle(Ink.secondary)
            Spacer(minLength: Space.xs)
            Text(value).font(.ourioMicro.monospaced()).lineLimit(1)
        }
    }
}

/// The brain card over the room's corner, once her brain is running; looks again now and then, as it starts after
/// the room has drawn.
struct RoomBrainCard: View {
    let controller: RoomController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let director = controller.current?.director { BrainCard(director: director) }
        }
    }
}
