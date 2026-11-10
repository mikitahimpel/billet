import SwiftUI

/// A load or a send that failed, in place of the content: what went wrong, and the one
/// `RetryButton`.
public struct ErrorState: View {
  let title: String
  let text: String?
  let retry: () -> Void

  public init(
    _ title: String = "Couldn't load this", text: String? = nil, retry: @escaping () -> Void
  ) {
    self.title = title
    self.text = text
    self.retry = retry
  }

  public var body: some View {
    EmptyState(symbol: "wifi.exclamationmark", title: title, text: text) {
      RetryButton(action: retry).padding(.top, Space.s)
    }
  }
}

#Preview("Error state") {
  BothSchemes {
    VStack(spacing: Space.l) {
      EmptyState(symbol: "tray", title: "All quiet", text: "Notes and gifts show up here.")
      ErrorState(text: "Check the connection and try again.") {}
    }
  }
}
