#if DEBUG || LABS_YES
import Design
import FeatureRaid
import RaidInterface
import SwiftUI

/// The pair's living room from above, as the raid is played on it: furniture as blocks, the jar, the defences the
/// viewer may see, and the cat. A touch is reported as a place on the floor, in the room's metres.
struct RaidBoardCanvas: View {
    struct Cat: Equatable {
        var at: RaidPoint
        var heading: Double
        /// Drawn larger while she is off the floor.
        var lift: Double
        var inBox: Bool
    }

    struct Mark: Equatable, Identifiable {
        var defence: RaidDefence
        /// Where it is now; a vacuum moves.
        var place: RaidPoint
        var id: Int { defence.id }
    }

    let board: RaidBoard
    var jar: RaidPoint?
    var marks: [Mark] = []
    var cat: Cat?
    /// A vacuum's first end, waiting for its second.
    var pending: RaidPoint?
    var lampOn = false
    /// How far she is through tipping the jar, 0 to 1.
    var pawing: Double = 0
    /// The finger's place, and nil when it lifts.
    let touch: (RaidPoint?) -> Void

    @State private var side: CGFloat = 0

    /// A little floor past the walls, so a piece against one is not cut.
    private static let span = 2 * (RaidRules.reach + 0.03)

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / Self.span
            let middle = CGPoint(x: size.width / 2, y: size.height / 2)
            func place(_ point: RaidPoint) -> CGPoint {
                CGPoint(x: middle.x + point.x * scale, y: middle.y + point.z * scale)
            }
            func disc(_ point: RaidPoint, _ radius: Double) -> Path {
                let centre = place(point)
                let r = radius * scale
                return Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r))
            }

            let floor = CGRect(x: middle.x - RaidRules.reach * scale, y: middle.y - RaidRules.reach * scale,
                               width: 2 * RaidRules.reach * scale, height: 2 * RaidRules.reach * scale)
            context.fill(Path(roundedRect: floor, cornerSize: CGSize(width: Space.s, height: Space.s)),
                         with: .color(Ink.well))

            for piece in board.pieces.sorted(by: { $0.height < $1.height }) {
                let centre = place(piece.centre)
                let rect = CGRect(x: centre.x - piece.halfX * scale, y: centre.y - piece.halfZ * scale,
                                  width: 2 * piece.halfX * scale, height: 2 * piece.halfZ * scale)
                let path = Path(roundedRect: rect, cornerSize: CGSize(width: Space.xs, height: Space.xs))
                if piece.isFlat {
                    context.fill(path, with: .color(Color.lilac.opacity(0.22)))
                } else {
                    // Taller pieces read darker, so a way up can be told from a thing to step over.
                    let tone = piece.isLow ? 0.18 : 0.3 + min(piece.height, 0.4)
                    context.fill(path, with: .color(Ink.textSecondary.opacity(tone)))
                    context.stroke(path, with: .color(Ink.separator), lineWidth: 1)
                    if !piece.isLow {
                        context.draw(Text(piece.title).font(.ourioMicro).foregroundStyle(Ink.text),
                                     in: rect.insetBy(dx: Space.xxs, dy: Space.xxs))
                    }
                }
            }

            for mark in marks {
                switch mark.defence.kind {
                case .vacuum(let to):
                    var line = Path()
                    line.move(to: place(mark.defence.at))
                    line.addLine(to: place(to))
                    context.stroke(line, with: .color(Ink.textTertiary),
                                   style: StrokeStyle(lineWidth: 1, dash: [Space.xs, Space.xs]))
                    context.fill(disc(mark.place, RaidRules.vacuumRadius), with: .color(Ink.text))
                    context.fill(disc(mark.place, RaidRules.vacuumRadius * 0.35), with: .color(Ink.well))
                case .box:
                    context.stroke(disc(mark.place, RaidRules.boxPull), with: .color(Color.honeyDeep.opacity(0.35)),
                                   style: StrokeStyle(lineWidth: 1, dash: [Space.xxs, Space.xs]))
                    let centre = place(mark.place)
                    let half = 0.04 * scale
                    let box = CGRect(x: centre.x - half, y: centre.y - half, width: 2 * half, height: 2 * half)
                    context.fill(Path(box), with: .color(Color.honeyDeep))
                    context.stroke(Path(box.insetBy(dx: half * 0.3, dy: half * 0.3)), with: .color(Color.honeyBright),
                                   lineWidth: 1)
                case .cucumber:
                    let centre = place(mark.place)
                    let rect = CGRect(x: centre.x - 0.035 * scale, y: centre.y - 0.012 * scale,
                                      width: 0.07 * scale, height: 0.024 * scale)
                    context.fill(Path(roundedRect: rect, cornerSize: CGSize(width: rect.height / 2,
                                                                           height: rect.height / 2)),
                                 with: .color(Color.sage))
                case .squeakyBoard:
                    let centre = place(mark.place)
                    let rect = CGRect(x: centre.x - RaidRules.boardRadius * scale, y: centre.y - 0.02 * scale,
                                      width: 2 * RaidRules.boardRadius * scale, height: 0.04 * scale)
                    context.fill(Path(rect), with: .color(Color.lilac))
                }
            }

            if let pending {
                context.stroke(disc(pending, RaidRules.vacuumRadius), with: .color(Ink.text), lineWidth: 1)
            }

            if let jar {
                context.fill(disc(jar, 0.035), with: .color(Color.honey))
                context.fill(disc(jar, 0.018), with: .color(Color.honeyBright))
                if pawing > 0 {
                    let centre = place(jar)
                    var ring = Path()
                    ring.addArc(center: centre, radius: 0.05 * scale, startAngle: .degrees(-90),
                                endAngle: .degrees(-90 + 360 * pawing), clockwise: false)
                    context.stroke(ring, with: .color(Color.honeyBright), lineWidth: Space.xxs)
                }
            }

            context.fill(disc(board.start, 0.012), with: .color(Ink.textTertiary))

            if let cat {
                let size = RaidRules.catRadius * (1 + 0.5 * cat.lift)
                let forward = RaidPoint(x: cos(cat.heading), z: sin(cat.heading))
                func ahead(_ metres: Double, side: Double = 0) -> RaidPoint {
                    RaidPoint(x: cat.at.x + forward.x * metres - forward.z * side,
                              z: cat.at.z + forward.z * metres + forward.x * side)
                }
                var tail = Path()
                tail.move(to: place(ahead(-size * 0.8)))
                tail.addLine(to: place(ahead(-size * 2.1, side: size * 0.5)))
                context.stroke(tail, with: .color(Color.blushPink),
                               style: StrokeStyle(lineWidth: size * scale * 0.45, lineCap: .round))
                context.fill(disc(cat.at, size), with: .color(Color.blushPink))
                if !cat.inBox {
                    context.fill(disc(ahead(size * 1.05), size * 0.7), with: .color(Color.blushPink))
                    for ear in [-0.45, 0.45] {
                        context.fill(disc(ahead(size * 1.5, side: size * ear), size * 0.28), with: .color(Ink.text))
                    }
                }
            }

            if lampOn {
                context.fill(Path(roundedRect: floor, cornerSize: CGSize(width: Space.s, height: Space.s)),
                             with: .color(Color.honeyBright.opacity(0.28)))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onGeometryChange(for: CGFloat.self) { min($0.size.width, $0.size.height) } action: { side = $0 }
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard side > 0 else { return }
                    let scale = side / Self.span
                    touch(RaidPoint(x: (value.location.x - side / 2) / scale, z: (value.location.y - side / 2) / scale))
                }
                .onEnded { _ in touch(nil) }
        )
        .accessibilityLabel("The room from above")
    }
}
#endif
