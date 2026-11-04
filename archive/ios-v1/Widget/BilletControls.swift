import AppIntents
import Persistence
import SwiftUI
import WidgetBridge
import WidgetKit

/// Whether a control is switched on in Settings, and has what it needs, read when it is drawn.
struct ControlAvailability: ControlValueProvider {
  let needsNote: Bool

  var previewValue: Bool { true }

  func currentValue() async throws -> Bool {
    guard needsNote else { return true }
    return WidgetSnapshotStore.appGroup()?.load()?.latestReceivedNote != nil
  }
}

struct PetCatControl: ControlWidget {
  static let kind = "com.mikitahimpel.billet.control.pet"

  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(
      kind: Self.kind, provider: ControlAvailability(needsNote: false)
    ) { available in
      ControlWidgetButton(action: PetCatIntent(surface: .control)) {
        Label("Pet the cat", systemImage: "pawprint.fill")
      }
      .disabled(!available)
    }
    .displayName("Pet the cat")
    .description("Pets the cat; your partner's phone feels it once billet is open.")
  }
}

struct SendHeartControl: ControlWidget {
  static let kind = "com.mikitahimpel.billet.control.heart"

  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(
      kind: Self.kind, provider: ControlAvailability(needsNote: true)
    ) { available in
      ControlWidgetButton(action: SendHeartIntent(surface: .control)) {
        Label("Send a heart", systemImage: "heart.fill")
      }
      .disabled(!available)
    }
    .displayName("Send a heart")
    .description("Answers your partner's newest note once billet is open.")
  }
}

struct OpenCanvasControl: ControlWidget {
  static let kind = "com.mikitahimpel.billet.control.canvas"

  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(
      kind: Self.kind, provider: ControlAvailability(needsNote: false)
    ) { available in
      ControlWidgetButton(action: OpenCanvasIntent(surface: .control)) {
        Label("Draw a note", systemImage: "pencil.tip")
      }
      .disabled(!available)
    }
    .displayName("Draw a note")
    .description("Opens billet straight on the canvas.")
  }
}
