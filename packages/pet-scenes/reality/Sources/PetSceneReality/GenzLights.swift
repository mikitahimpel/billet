import RealityKit

extension Entity {
  /// Sets the intensity of the light on this entity, and takes a light with none out of the
  /// scene: a dark light still counts against RealityKit's limit on lights and is still tested
  /// against every model each frame.
  @MainActor
  func setLight(intensity: Float) {
    if components.has(PointLightComponent.self) {
      components[PointLightComponent.self]?.intensity = intensity
    } else if components.has(SpotLightComponent.self) {
      components[SpotLightComponent.self]?.intensity = intensity
    } else if components.has(DirectionalLightComponent.self) {
      components[DirectionalLightComponent.self]?.intensity = intensity
    }
    let isLit = intensity > 0
    if isEnabled != isLit { isEnabled = isLit }
  }
}
