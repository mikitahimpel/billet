import Foundation
@preconcurrency import RiveRuntime
import SwiftUI

/// A bundled Rive scene: an artboard with state machine `World`, bound to view model `PetWorld`,
/// whose boolean `noteArrived` runs Sleep, Deliver, Proud and Settle.
@MainActor
final class PetWorldRive {
  private let viewModel: RiveViewModel
  private var world: RiveDataBindingViewModel.Instance?

  /// Returns `nil` when the bundled file does not load or lacks the `noteArrived` property.
  init?(fileName: String, artboardName: String) {
    let model: RiveModel
    do {
      model = try RiveModel(fileName: fileName, in: .module)
    } catch {
      assertionFailure("\(fileName).riv failed to load: \(error)")
      return nil
    }
    var bound: RiveDataBindingViewModel.Instance?
    model.enableAutoBind { bound = $0 }
    viewModel = RiveViewModel(
      model, stateMachineName: "World", fit: .contain, alignment: .center,
      artboardName: artboardName)
    world = bound
    guard world?.booleanProperty(fromPath: "noteArrived") != nil else {
      assertionFailure("\(fileName).riv has no bound noteArrived property")
      return nil
    }
  }

  var view: some View { viewModel.view() }

  func setNoteArrived(_ value: Bool) {
    world?.booleanProperty(fromPath: "noteArrived")?.value = value
    viewModel.play()
  }
}
