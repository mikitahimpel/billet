import DesignSystem
import Foundation
import Pet
import PetScene
import SwiftUI

/// The Little House: the Rive cat in a flat house at night.
public struct LittleHousePetScene: PetScene {
  public let id = "little-house"
  public let title = "Little House"

  /// Mirrors the `NoteNew` node. Frame 468 of Deliver at 60 fps is when it first shows.
  public let noteWall: PetSceneNoteWall? = PetSceneNoteWall(
    artboard: CGSize(width: 780, height: 980),
    paper: CGRect(x: 336, y: 455, width: 112, height: 138),
    peg: CGPoint(x: 392, y: 446),
    revealDelay: .seconds(468.0 / 60.0))

  public init() {}

  /// Mirrors the animation lengths in `LittleHouse.riv`. Deliver runs 590 frames at 60 fps, then
  /// the cat sits proudly for one 4 s Proud loop. Settle runs 150 frames at 60 fps.
  static let pacing = PetScenePacing(
    delivery: .seconds(590.0 / 60.0 + 4),
    settling: .seconds(150.0 / 60.0))

  public func makeView(
    world: PetWorld,
    onEvent: @escaping @MainActor (PetSceneEvent) -> Void
  ) -> AnyView {
    AnyView(LittleHouseView(world: world, onEvent: onEvent))
  }

  public func posePNG(_ pose: PetPose) -> Data? {
    guard
      let url = Bundle.module.url(forResource: "pose-\(pose.rawValue)", withExtension: "png")
    else { return nil }
    return try? Data(contentsOf: url)
  }
}

private struct LittleHouseView: View {
  let world: PetWorld
  let onEvent: @MainActor (PetSceneEvent) -> Void

  @State private var rive = LittleHouseRive()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      if let rive {
        rive.view
          .aspectRatio(Self.artboardRatio, contentMode: .fit)
          .overlay { windowLight }
          .mask { Self.fade(.leading, .trailing) }
          .mask { Self.fade(.top, .bottom) }
          .accessibilityLabel("Little House with the cat")
      }
    }
    .onChange(of: world.noteArrived, initial: true) { _, arrived in
      rive?.setNoteArrived(arrived)
    }
    .task(id: world.step) {
      await LittleHousePetScene.pacing.play(world, onEvent: onEvent)
    }
  }

  private static let artboardRatio: CGFloat = 780.0 / 980.0
  private static let artboard = CGSize(width: 780, height: 980)
  /// The house's side window in the artboard. `LittleHouse.riv` binds only `noteArrived`, so the
  /// glow is drawn here and the cat's own pose is left as it is.
  private static let window = CGRect(x: 523, y: 543, width: 119, height: 119)

  /// A warm light behind the window's panes and a soft spill beyond them, while the partner is here.
  private var windowLight: some View {
    GeometryReader { proxy in
      let scale = proxy.size.width / Self.artboard.width
      ZStack {
        RoundedRectangle(cornerRadius: 6 * scale)
          .fill(Palette.gold.color.opacity(0.55))
          .blendMode(.plusLighter)
          .frame(width: Self.window.width * scale, height: Self.window.height * scale)
          .blur(radius: 6 * scale)
        Circle()
          .fill(Palette.gold.color.opacity(0.28))
          .frame(width: Self.window.width * 2.4 * scale)
          .blur(radius: 28 * scale)
      }
      .position(x: Self.window.midX * scale, y: Self.window.midY * scale)
      .opacity(world.partnerHere ? 1 : 0)
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: world.partnerHere)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }

  /// Dissolves the artboard's edges into whatever is behind the scene.
  private static func fade(_ start: UnitPoint, _ end: UnitPoint) -> some View {
    LinearGradient(
      stops: [
        .init(color: .clear, location: 0),
        .init(color: .black, location: 0.06),
        .init(color: .black, location: 0.94),
        .init(color: .clear, location: 1),
      ],
      startPoint: start,
      endPoint: end
    )
  }
}
