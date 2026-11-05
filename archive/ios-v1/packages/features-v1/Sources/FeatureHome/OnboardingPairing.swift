import Foundation
import PetScene

/// Pairing as the first-launch scene tells it: the heart opens, this phone's half stays and the
/// other waits with the code, or flies in once the partner's code is entered, and the two join.
///
/// It follows what the pairing itself reports (``Facts``) and what is tapped (``Event``), and
/// holds on the joined moment after the pairing is done, until the scene has shown it.
struct OnboardingPairing: Equatable {
  enum Step: Equatable {
    case welcome
    /// This phone made `code` and waits for the partner with it. `live` once the room has it.
    case inviting(code: String, live: Bool)
    case enteringCode
    /// The typed code was sent; waiting for the room.
    case joining
    /// Paired: the halves join. `madeCode` when this phone made the code.
    case joined(madeCode: Bool)
    /// The joined moment has been shown.
    case done
  }

  /// Where the pairing itself is.
  enum Facts: Equatable {
    case unpaired
    /// This phone made `code`. `live` once the room has it; `partnerHere` once they joined.
    case creating(code: String, live: Bool, partnerHere: Bool)
    case joining
    case paired
  }

  /// What was tapped, or that the joined moment is over.
  enum Event: Equatable {
    case enterCode
    case back
    /// Leaving for the app before the partner has joined.
    case goIn
    case joinShown
  }

  private(set) var step: Step

  init(paired: Bool = false) {
    step = paired ? .done : .welcome
  }

  mutating func send(_ event: Event) {
    switch (step, event) {
    case (.welcome, .enterCode): step = .enteringCode
    case (.enteringCode, .back): step = .welcome
    case (.inviting, .goIn), (.joined, .joinShown): step = .done
    case (.welcome, _), (.inviting, _), (.enteringCode, _), (.joining, _), (.joined, _),
      (.done, _):
      break
    }
  }

  mutating func observe(_ facts: Facts) {
    switch (step, facts) {
    case (.done, _), (.joined, _):
      break
    case (.welcome, .paired):
      // Paired without a code here, as with the fake partner: nothing to show.
      step = .done
    case (.welcome, .creating(let code, let live, false)),
      (.inviting, .creating(let code, let live, false)):
      step = .inviting(code: code, live: live)
    case (.welcome, .creating(_, _, true)), (.inviting, .creating(_, _, true)),
      (.inviting, .paired):
      step = .joined(madeCode: true)
    case (.inviting, .unpaired):
      step = .welcome
    case (.enteringCode, .joining), (.welcome, .joining):
      step = .joining
    case (.joining, .paired), (.enteringCode, .paired):
      step = .joined(madeCode: false)
    case (.joining, .unpaired):
      // Turned away or unreachable: back to the code, with the failure shown.
      step = .enteringCode
    case (.welcome, .unpaired), (.enteringCode, .unpaired), (.enteringCode, .creating),
      (.joining, .joining), (.joining, .creating), (.inviting, .joining):
      break
    }
  }

  var isFinished: Bool { step == .done }

  /// What the scene shows once the opening flight is over.
  var scene: OnboardingSceneState {
    switch step {
    case .welcome:
      OnboardingSceneState(moment: .resting)
    case .inviting(let code, _):
      OnboardingSceneState(moment: .apart(partner: .waiting), mine: .left, code: code)
    case .enteringCode, .joining:
      OnboardingSceneState(moment: .apart(partner: .away), mine: .right)
    case .joined(let madeCode):
      OnboardingSceneState(moment: .together, mine: madeCode ? .left : .right)
    case .done:
      OnboardingSceneState(moment: .together)
    }
  }
}
