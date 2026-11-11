import Foundation
import RoomInterface

extension CatRig.Files {
    private init(rig: RigFile, splat: SplatLoader.File?, skin: [UInt8]?) {
        self.rig = rig
        self.splat = splat
        self.skin = skin
    }

    /// The same cat with her least important splats left out, and the rest a little larger to cover for them. The
    /// files on disk, and so their checksums and the coats cut from them, stay whole.
    nonisolated func reduced(to detail: SplatDetail) -> Self {
        guard detail != .full, let splat, let skin, splat.count > 0 else { return self }
        let importance = (0..<splat.count).map { i in
            SplatPruning.importance(
                logitOpacity: splat.still[8 * i + 3],
                logScales: [splat.still[8 * i], splat.still[8 * i + 1], splat.still[8 * i + 2]])
        }
        let kept = SplatPruning.survivors(importance: importance, keeping: detail.keep)
        let boost = SplatPruning.logScaleBoost(keeping: Double(kept.count) / Double(splat.count))
        var moving = [Float](), still = [Float](), skinned = [UInt8]()
        moving.reserveCapacity(8 * kept.count)
        still.reserveCapacity(8 * kept.count)
        skinned.reserveCapacity(8 * kept.count)
        for i in kept {
            moving.append(contentsOf: splat.moving[8 * i..<8 * i + 8])
            var s = Array(splat.still[8 * i..<8 * i + 8])
            for k in 0..<3 { s[k] += boost }
            still.append(contentsOf: s)
            skinned.append(contentsOf: skin[8 * i..<8 * i + 8])
        }
        let file = SplatLoader.File(name: splat.name, count: kept.count, moving: moving, still: still)
        return Self(rig: rig, splat: file, skin: skinned)
    }
}

extension SplatDetail {
    /// How much of her to draw, read when she loads: what Labs asks for, and the tier Labs forces or else the phone's heat and
    /// Low Power Mode at that moment. The most reduced wins.
    nonisolated static func chosen(
        defaults: UserDefaults = .standard, info: ProcessInfo = .processInfo
    ) -> SplatDetail {
        #if DEBUG || LABS_YES
        let lab = PerfLabMachine.State.saved(in: defaults)
        #else
        let lab = PerfLabMachine.State.shipped
        #endif
        let tier = lab.forcedTier?.plan.splatDetail ?? RoomConditions(info).wanted.plan.splatDetail
        return max(lab.isOn(.splatLean) ? SplatDetail.balanced : .full, tier)
    }
}

extension RoomConditions {
    nonisolated init(_ info: ProcessInfo) {
        let heat: Heat =
            switch info.thermalState {
            case .nominal: .nominal
            case .fair: .fair
            case .serious: .serious
            case .critical: .critical
            @unknown default: .nominal
            }
        self.init(heat: heat, lowPower: info.isLowPowerModeEnabled)
    }
}
