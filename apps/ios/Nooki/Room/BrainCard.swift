import OurioShared
import Pet
import SwiftUI
import UIKit
import Design

extension AppSettings {
    /// Labs: shows the cat's brain over the room.
    static let brainCardKey = "labs.brainCard"
    /// Labs: the brain drives the cat; off, she runs on its original timers alone.
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
        .foregroundStyle(.white)
        .padding(Space.m)
        .frame(width: 236, alignment: .leading)
        .cornerFill(.card, .black.opacity(0.55))
        .onAppear { director.observing = true }
        .onDisappear { director.observing = false }
    }

    /// The observatory: the brain's speed, a nudge to a group or an event, and the log to paste.
    private var observatory: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(CatClock.speeds, id: \.self) { speed in
                    chip("x\(Int(speed))", selected: director.speed == speed) { director.set(speed: speed) }
                }
                chip("Copy log") { UIPasteboard.general.string = director.log() }
            }
            HStack(spacing: 6) {
                Menu {
                    ForEach(CatActivityGroup.chosen, id: \.self) { group in
                        Button(group.title) { director.force(group: group) }
                    }
                } label: { chipLabel("Force group") }
                Menu {
                    ForEach(LifeEvent.Kind.allCases, id: \.self) { kind in
                        Button(kind.rawValue) { director.send(kind) }
                    }
                } label: { chipLabel("Event") }
            }
        }
    }

    /// The last twenty things she did, newest first, with how long each lasted.
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(director.timeline.reversed().enumerated()), id: \.offset) { _, episode in
                HStack {
                    Text("\(episode.group.rawValue)/\(episode.step.rawValue)")
                    Spacer(minLength: 4)
                    Text(episode.end.map { "\(Int(($0 - episode.start).rounded())) s" } ?? "now")
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(episode.end == nil ? 1 : 0.6))
            }
        }
    }

    /// Labs controls: a tour of every state, the brain's clock, a neglected cat, and the couple's touches.
    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                chip(director.touring ? "Touring…" : "Tour") { director.startTour() }
                Menu {
                    ForEach([7.0, 13, 19, 23], id: \.self) { hour in
                        Button(String(format: "%02.0f:00", hour)) { director.force(hour: hour) }
                    }
                    Button("Real time") { director.force(hour: nil) }
                } label: {
                    chipLabel(director.forcedHour.map { String(format: "%02.0f:00", $0) } ?? "Clock")
                }
                chip("Alone") { director.neglect() }
            }
            HStack(spacing: 6) {
                chip("Pet") { director.pet() }
                chip("Feed") { director.feed() }
                chip("Hello") { director.greet() }
            }
        }
    }

    private func chip(_ title: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(title, selected: selected) }.buttonStyle(.plain)
    }

    private func chipLabel(_ title: String, selected: Bool = false) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(.white.opacity(selected ? 0.4 : 0.16), in: Capsule())
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text((director.touring ? "Tour · " : "") + (director.mind?.path ?? "starting…"))
                .font(.system(size: 14, weight: .bold, design: .rounded))
            Text(director.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(2)
            if let needs = director.needs {
                ForEach(PetNeed.allCases, id: \.self) { need in
                    bar(need.title, needs[need])
                }
            }
            line("Body", "\(director.rest.rawValue) at \(director.spot.rawValue)")
            line("Last", director.lastEvent)
            ForEach(director.top, id: \.group) { score in
                line(score.group.rawValue, String(format: "%.2f", score.score))
            }
        }
    }

    private func bar(_ title: String, _ value: Double) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 10, weight: .medium)).frame(width: 46, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule().fill(Color(hex: 0xFFC27A)).frame(width: geometry.size.width * min(max(value, 0), 1))
                }
            }
            .frame(height: 6)
            Text(String(format: "%.2f", value)).font(.system(size: 9, design: .monospaced)).frame(width: 28)
        }
    }

    private func line(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.65))
            Spacer(minLength: 4)
            Text(value).font(.system(size: 10, design: .monospaced)).lineLimit(1)
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
