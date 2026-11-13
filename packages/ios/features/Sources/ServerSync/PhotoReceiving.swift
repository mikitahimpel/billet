import Foundation

/// Runs one receive at a time across every `PhotoSync`: a call while one runs asks it to go once more instead, so a
/// burst of socket frames downloads each photo once and the cursor only moves forward.
@MainActor
public final class PhotoReceiving {
  private var running = false
  private var again = false

  public init() {}

  public func run(_ body: () async -> Void) async {
    guard !running else {
      again = true
      return
    }
    running = true
    repeat {
      again = false
      await body()
    } while again
    running = false
  }
}
