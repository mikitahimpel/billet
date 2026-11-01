import Foundation
@preconcurrency import RiveRuntime
import SwiftUI

/// The Rive file in `Resources/LittleHouse.riv`: artboard `LittleHouse`, state machine `World`,
/// view model `PetWorld`.
@MainActor
final class LittleHouseRive {
  private let viewModel: RiveViewModel
  private var world: RiveDataBindingViewModel.Instance?

  /// Returns `nil` when the bundled file does not load or lacks the `noteArrived` property.
  init?() {
    let model: RiveModel
    do {
      model = try RiveModel(fileName: "LittleHouse", in: .module)
    } catch {
      assertionFailure("LittleHouse.riv failed to load: \(error)")
      return nil
    }
    var bound: RiveDataBindingViewModel.Instance?
    model.enableAutoBind { bound = $0 }
    viewModel = RiveViewModel(
      model, stateMachineName: "World", fit: .contain, alignment: .center,
      artboardName: "LittleHouse")
    world = bound
    guard world?.booleanProperty(fromPath: "noteArrived") != nil else {
      assertionFailure("LittleHouse.riv has no bound noteArrived property")
      return nil
    }
  }

  var view: some View { viewModel.view() }

  func setNoteArrived(_ value: Bool) {
    world?.booleanProperty(fromPath: "noteArrived")?.value = value
    viewModel.play()
  }
}
