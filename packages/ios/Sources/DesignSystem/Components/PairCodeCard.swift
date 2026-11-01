import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

/// The pair code, large enough to read aloud, with ways to pass it on.
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
    .litPanel()
  }

  @ViewBuilder private var actions: some View {
    Button {
      copy()
    } label: {
      Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
        .labelStyle(CodeActionLabelStyle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(copied ? "Code copied" : "Copy code")

    ShareLink(item: "Pair with me on billet: \(code)") {
      Label("Share", systemImage: "square.and.arrow.up")
        .labelStyle(CodeActionLabelStyle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Share code")
  }

  private func copy() {
    #if canImport(UIKit)
      UIPasteboard.general.string = code
    #endif
    copied = true
  }
}

private struct CodeActionLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: Spacing.small) {
      configuration.icon
      configuration.title
    }
    .billetType(.label)
    .foregroundStyle(Palette.paper.color)
    .padding(.horizontal, Spacing.medium)
    .frame(maxWidth: .infinity, minHeight: Target.minimum)
    .background(Palette.raisedTop.color, in: .rect(cornerRadius: Radius.control))
    .contentShape(.rect(cornerRadius: Radius.control))
  }
}
