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

/// A load in progress, in the place and size of the `EmptyState` it becomes.
public struct LoadingState: View {
  let title: String

  public init(_ title: String = "Loading") { self.title = title }

  public var body: some View {
    VStack(spacing: Space.m) {
      ProgressView()
        .controlSize(.large)
      Text(title)
        .font(.ourioCallout)
        .foregroundStyle(Ink.textSecondary)
        .multilineTextAlignment(.center)
    }
    .padding(.horizontal, Space.xl)
    .padding(.vertical, Space.xl)
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }
}

#Preview("Error state") {
  BothSchemes {
    VStack(spacing: Space.l) {
      EmptyState(symbol: "tray", title: "All quiet", text: "Notes and gifts show up here.")
      ErrorState(text: "Check the connection and try again.") {}
      LoadingState("Loading the Inbox")
    }
  }
}
