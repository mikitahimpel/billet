import Foundation
import WidgetInterface
import Wire

/// What an invite code or link scanned, pasted or typed holds: the code, or nil when it isn't one.
public enum InviteInput {
  public static func code(in text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let url = URL(string: trimmed), case .invite(let code)? = DeepLink(url: url) {
      return code.isEmpty ? nil : code
    }
    let code = InviteCode.cleaned(trimmed)
    let bare = InviteCode.normalized(trimmed).filter { !$0.isWhitespace && $0 != "-" }
    let lengths = [InviteCode.length, InviteCode.reviewLength]
    return lengths.contains(bare.count) && code.count == bare.count ? code : nil
  }

  /// What the code field takes from a paste: the code or invite link in it, the shared message included, or else
  /// its code-like symbols; empty when there are none.
  public static func pasted(_ text: String) -> String {
    code(in: text)
      ?? text.split(whereSeparator: \.isWhitespace).lazy.compactMap { code(in: String($0)) }.first
      ?? InviteCode.cleaned(text)
  }

}
