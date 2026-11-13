#if DEBUG || LABS_YES
import RealityKit

extension RoomController {
    /// Labs → Performance's switches for the scene: the lights, the merged furniture and the baked contact shadow.
    func setPerf(_ state: PerfLabMachine.State) {
        guard perf.set(RoomPerfSwitches(state)) else { return }
        for room in [home, city, board].compactMap({ $0 }) { perf.lights(in: room) }
        perfDecorChanged()
    }

    func perfDecorChanged() {
        perf.furniture(stage: decorStage.root, decor: decor) { [weak self] in self?.home?.iblReceiver }
    }
}
#endif
