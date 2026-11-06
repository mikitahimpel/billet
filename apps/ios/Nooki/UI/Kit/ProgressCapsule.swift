import SwiftUI
import Design

struct ProgressCapsule: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                Capsule()
                    .fill(.honeyGradient)
                    .frame(width: geo.size.width * min(max(value, 0.04), 1))
            }
        }
        .frame(height: 8)
    }
}
