import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

public struct PairCodeCard: View {
  private let code: String

  @State private var copied = false

  public init(code: String) {
    self.code = code
  }

  public var body: some View {
    VStack(spacing: Spacing.medium) {
      Text(verbatim: code)
        .font(.custom(BilletFonts.monoFamily, size: 28, relativeTo: .title))
        .foregroundStyle(Palette.gold.color)
        .minimumScaleFactor(0.5)
        .lineLimit(1)
        .textSelection(.enabled)
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.small)
        .frame(maxWidth: .infinity)
        .background(Palette.plate.color, in: .rect(cornerRadius: Radius.plate))
        .accessibilityLabel(code.map(String.init).joined(separator: " "))
        .accessibilityIdentifier("pairCode")
      ViewThatFits(in: .horizontal) {
        HStack(spacing: Spacing.small) { actions }
        VStack(spacing: Spacing.small) { actions }
      }
    }
    .padding(Spacing.medium)
    .frame(maxWidth: .infinity)
    .card()
  }

  @ViewBuilder private var actions: some View {
    Button {
      copy()
    } label: {
      ButtonLabel(
        copied ? "Copied" : "Copy", rank: .secondary,
        systemImage: copied ? "checkmark" : "doc.on.doc")
    }
    .billetButton(.secondary)
    .accessibilityLabel(copied ? "Code copied" : "Copy code")

    ShareLink(item: "Pair with me on billet: \(code)") {
      ButtonLabel("Share", rank: .secondary, systemImage: "square.and.arrow.up")
    }
    .billetButton(.secondary)
    .accessibilityLabel("Share code")
  }

  private func copy() {
    #if canImport(UIKit)
      UIPasteboard.general.string = code
    #endif
    withAnimation(Motion.quick) { copied = true }
  }
}
