import RealityKit
import UIKit

/// A puff of honey and pink sparks over her head when something goes well. One emitter, burst on demand: it costs
/// nothing between bursts.
@MainActor
final class GameSparkles {
    private let entity: Entity

    init(in parent: Entity) {
        entity = parent.group()
        var p = ParticleEmitterComponent()
        p.emitterShape = .sphere
        p.emitterShapeSize = [0.03, 0.02, 0.03]
        p.birthLocation = .surface
        p.birthDirection = .normal
        p.speed = 0.09
        p.speedVariation = 0.04
        p.isEmitting = false
        p.mainEmitter.birthRate = 0
        p.mainEmitter.lifeSpan = 0.9
        p.mainEmitter.lifeSpanVariation = 0.25
        p.mainEmitter.size = 0.006
        p.mainEmitter.sizeVariation = 0.002
        p.mainEmitter.sizeMultiplierAtEndOfLifespan = 0.3
        p.mainEmitter.color = .evolving(start: .single(UIColor(hex: 0xFFD58A)), end: .single(UIColor(hex: 0xFF8FA3)))
        p.mainEmitter.blendMode = .additive
        p.mainEmitter.opacityCurve = .linearFadeOut
        p.mainEmitter.acceleration = [0, -0.12, 0]
        p.mainEmitter.isLightingEnabled = false
        entity.components.set(p)
    }

    /// At `point` in the parent's space; `big` for the game's end.
    func burst(at point: SIMD3<Float>, big: Bool) {
        guard var p = entity.components[ParticleEmitterComponent.self] else { return }
        entity.position = point
        p.burstCount = big ? 80 : 24
        p.speed = big ? 0.16 : 0.09
        p.burst()
        entity.components.set(p)
    }

    func remove() { entity.removeFromParent() }
}
