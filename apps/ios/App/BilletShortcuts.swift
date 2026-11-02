import AppIntents
import WidgetBridge

/// "Draw a note" from Shortcuts, Spotlight or Siri: opens billet straight on the canvas.
struct DrawNoteIntent: AppIntent {
  static let title: LocalizedStringResource = "Draw a note"
  static let description = IntentDescription("Opens billet on the canvas.")
  static let openAppWhenRun = true

  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard ActionSubmission.submit(.openCanvas, at: .shortcut) else {
      return .result(dialog: "Drawing from a shortcut is off in billet Settings.")
    }
    return .result(dialog: "Opening the canvas.")
  }
}

struct BilletShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: DrawNoteIntent(),
      phrases: ["Draw a note in \(.applicationName)", "Draw in \(.applicationName)"],
      shortTitle: "Draw a note",
      systemImageName: "pencil.tip")
  }
}
