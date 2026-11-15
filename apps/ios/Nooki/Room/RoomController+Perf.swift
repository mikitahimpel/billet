#if DEBUG || LABS_YES
import RealityKit

extension RoomController {
    /// Labs → Performance's switches for the scene: the lights, the merged furniture and the baked contact shadow, joined with the quality tier's at `applySwitches`.
    func setPerf(_ state: PerfLabMachine.State) {
        labsSwitches = RoomPerfSwitches(state)
        applySwitches()
    }

    func perfDecorChanged() {
        perf.furniture(stage: decorStage.root, room: .home, decor: decor) { [weak self] in self?.home?.iblReceiver }
        if let city {
            perf.furniture(stage: city.decorStage.root, room: .bedroom, decor: decor) { [weak city] in city?.iblReceiver }
        }
    }
}
#endif
