import Delivery
import SwiftUI

/// Pairs on first launch, then shows the home screen connected to the room on `host`.
public struct DemoRootView: View {
  private let host: String
  @State private var room = DemoRoom.saved()

  public init(host: String) {
    self.host = host
  }

  public var body: some View {
    if host.isEmpty {
      Text("This build has no demo host.")
    } else if let room, let url = room.socketURL(host: host) {
      HomeView(
        delivery: .live(url: url),
        code: room.code,
        onChangeCode: {
          DemoRoom.forget()
          self.room = nil
        }
      )
      .id(room.code)
    } else {
      PairingView { room = DemoRoom.pair(code: $0) }
    }
  }
}
