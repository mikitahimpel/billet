import Pet
import SwiftUI

extension AppSettings {
    /// Labs: shows the cat's brain over the room.
    static let brainCardKey = "labs.brainCard"
    /// Labs: the brain drives the cat; off, she runs on Ilya's own timers alone. On by default for now.
    static let catBrainKey = "labs.catBrain"

    static var catBrain: Bool { UserDefaults.standard.object(forKey: catBrainKey) as? Bool ?? true }
}

/// Labs' window on Mochi's brain: the owner's state and the brain's own stack, her four needs, where she is and in
/// which body, the last thing that reached her, and the three activities scoring best right now.
struct BrainCard: View {
    let director: CatDirector

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(director.mind?.path ?? "starting…")
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
        .foregroundStyle(.white)
        .padding(12)
        .frame(width: 210, alignment: .leading)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .allowsHitTesting(false)
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
