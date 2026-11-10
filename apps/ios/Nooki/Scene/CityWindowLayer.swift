import SwiftUI
import UIKit
import WindowViews

/// Hosts the City room's flat window view, the same size as the room's view so the window's points match.
struct CityWindowLayer: UIViewRepresentable {
    let view: CityWindowView

    func makeUIView(context: Context) -> UIView {
        let holder = UIView()
        holder.isUserInteractionEnabled = false
        holder.backgroundColor = .clear
        attach(to: holder)
        return holder
    }

    func updateUIView(_ holder: UIView, context: Context) {
        if view.superview !== holder { attach(to: holder) }
    }

    private func attach(to holder: UIView) {
        view.frame = holder.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        holder.addSubview(view)
    }
}
