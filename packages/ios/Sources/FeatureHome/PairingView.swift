import SwiftUI

/// First launch: use this device's generated code, or type the partner's.
struct PairingView: View {
  let onPair: (String) -> Void

  @State private var generatedCode = DemoRoom.generateCode()
  @State private var partnerCode = ""

  private var typedCode: String {
    partnerCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
  }

  var body: some View {
    VStack(spacing: 32) {
      Text("Pair with your partner")
        .font(.title2)

      VStack(spacing: 12) {
        Text("Your code")
          .foregroundStyle(.secondary)
        Text(generatedCode)
          .font(.title3.monospaced())
          .textSelection(.enabled)
          .accessibilityIdentifier("generatedCode")
        Button("Use this code") { onPair(generatedCode) }
          .buttonStyle(.borderedProminent)
      }

      Divider()

      VStack(spacing: 12) {
        partnerCodeField
        Button("Join") { onPair(typedCode) }
          .buttonStyle(.bordered)
          .disabled(!DemoRoom.isValid(code: typedCode))
      }
    }
    .padding(24)
  }

  private var partnerCodeField: some View {
    TextField("Partner's code", text: $partnerCode)
      .font(.title3.monospaced())
      .multilineTextAlignment(.center)
      .autocorrectionDisabled()
      #if os(iOS)
        .textInputAutocapitalization(.characters)
      #endif
  }
}
