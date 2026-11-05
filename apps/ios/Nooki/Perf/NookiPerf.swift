import PetScene
import Synchronization

/// Nooki's side of a `-perf.script` run (`ScenePerf`, read by apps/ios/scripts/perf/measure.sh): the room on screen
/// is the scene a run drives, and the tabs are the ones it switches. Silent without the launch argument.
///
/// A run orbits by turning the room the way a drag does. It has no zoom: the pinch lives inside `DioramaView`.
/// Nooki has one lighting and one cat, so those steps are skipped.
@MainActor
enum NookiPerf {
    /// Starts the frame recorder and the script, and says how to switch tabs. Once, at launch.
    static func start(state: HomeState) {
        guard ScenePerf.isOn else { return }
        var host = ScenePerf.Host()
        host.lightings = []
        host.cats = []
        host.shotPrefix = "world"
        host.selectTab = { tab in
            switch tab {
            case "shop": state.tab = .shop
            case "notes": state.tab = .moments
            default: state.tab = .world
            }
        }
        host.scroll = { y in shopScroll?(y) }
        ScenePerf.host = host
        ScenePerf.start()
    }

    /// Scrolls the Shop's page, while the Shop is on screen; a run scrolls it to measure its frames.
    static var shopScroll: ((Double) -> Void)?

    /// `room` is on screen: the Room (`room on screen`) or the City (`city room on screen`), so a run that waits for
    /// "room on screen" finds either.
    static func shown(_ room: CatRoom, kind: RoomKind) {
        guard ScenePerf.isOn else { return }
        ScenePerf.host.shotPrefix = kind == .city ? "city" : "world"
        ScenePerf.shown(
            .init(
                name: kind == .city ? "city room" : "room",
                orbit: { deltaX, _ in room.setYaw(room.settledYaw - deltaX * 0.004) },
                zoom: { _ in },
                release: { room.setYaw(0) },
                census: {
                    let skin = SplatSkinner.stats.withLock { $0 }
                    return "kind=\(kind == .city ? "city" : "room") skin_passes=\(skin.passes) skin_skipped=\(skin.skipped)"
                        + " skin_ms=\(String(format: "%.2f", skin.milliseconds))"
                },
                switches: ["cat shadow"],
                setSwitch: { _, isOn in room.setCatShadow(isOn) }
            ))
    }

    /// Mochi stands in a room, posed and ready to draw.
    static func catPlaced() {
        ScenePerf.trace("styled cat placed")
    }

    /// A tab other than the World came on screen, under the names a run waits for.
    static func tabShown(_ tab: HomeTab) {
        guard ScenePerf.isOn else { return }
        switch tab {
        case .shop: ScenePerf.mark("shop on screen")
        case .moments: ScenePerf.mark("notes on screen")
        case .us: ScenePerf.mark("us on screen")
        case .world: break
        }
    }
}
