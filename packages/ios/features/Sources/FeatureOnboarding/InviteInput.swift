import Foundation
import WidgetInterface
import Wire

/// What an invite code or link scanned, pasted or typed holds: the code, or nil when it isn't one.
enum InviteInput {
  static func code(in text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let url = URL(string: trimmed), case .invite(let code)? = DeepLink(url: url) {
      return code.count == InviteCode.length ? cleaned(code) : nil
    }
    let code = cleaned(trimmed)
    let bare = InviteCode.normalized(trimmed).filter { !$0.isWhitespace && $0 != "-" }
    let lengths = [InviteCode.length, InviteCode.reviewLength]
    return lengths.contains(bare.count) && code.count == bare.count ? code : nil
  }

  /// What was typed or pasted, kept to the symbols a code has, up to the App Review pair's longer code.
  static func cleaned(_ typed: String) -> String {
    String(
      InviteCode.normalized(typed).filter { InviteCode.alphabet.contains($0) }.prefix(
        InviteCode.reviewLength))
  }
}
