import CoreTransferable
import SwiftUI

/// The system Paste button in the app's capsule: it pastes without the "Allow Paste" prompt and greys
/// out with nothing to paste. `titled` is `Size.button` tall and fills its width, so it pairs with a
/// `SecondaryButton`; `iconOnly` sits beside a field. iOS draws its fill and label, so only the
/// tint, shape and size are ours.
public struct PasteCapsuleButton<Payload: Transferable>: View {
  public enum Look: Sendable {
    case titled
    case iconOnly
  }

  let look: Look
  let paste: @Sendable ([Payload]) -> Void

  public init(
    _ payload: Payload.Type, look: Look = .titled,
    paste: @escaping @Sendable ([Payload]) -> Void
  ) {
    self.look = look
    self.paste = paste
  }

  public var body: some View {
    switch look {
    case .titled:
      PasteButton(payloadType: Payload.self, onPaste: paste)
        .labelStyle(.titleAndIcon)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(.honey)
        .frame(maxWidth: .infinity, minHeight: Size.button)
    case .iconOnly:
      PasteButton(payloadType: Payload.self, onPaste: paste)
        .labelStyle(.iconOnly)
        .buttonBorderShape(.capsule)
        .tint(.honey)
    }
  }
}
