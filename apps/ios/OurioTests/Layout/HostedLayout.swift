import SwiftUI
import UIKit
import Darwin

/// A view laid out in a window of a given phone's size, and the accessibility elements it draws, with their frames in
/// the window's points: the same frames a UI test reads, without launching the app.
@MainActor
final class HostedLayout {
    struct Phone {
        var size: CGSize
        var safeArea: UIEdgeInsets
        var dynamicType: DynamicTypeSize = .large

        static let iPhone = Phone(size: CGSize(width: 402, height: 874), safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0))
        static let se = Phone(size: CGSize(width: 375, height: 667), safeArea: UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0))

        func largestText() -> Phone {
            var copy = self
            copy.dynamicType = .accessibility5
            return copy
        }
    }

    struct Element {
        let identifier: String
        let label: String
        let frame: CGRect
    }

    /// SwiftUI builds its accessibility elements only once something asks for them, as VoiceOver or XCUITest do; this
    /// asks the way XCUITest does.
    private static let accessibilityOn: Void = {
        _ = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW)
        typealias Setter = @convention(c) (Bool) -> Void
        for name in ["_AXSSetAutomationEnabled", "_AXSApplicationAccessibilitySetEnabled"] {
            if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) {
                unsafeBitCast(symbol, to: Setter.self)(true)
            }
        }
        RunLoop.main.run(until: .now + 0.3)
    }()

    let window: UIWindow
    let phone: Phone

    init(_ view: some View, phone: Phone) {
        self.phone = phone
        Self.accessibilityOn
        let controller = UIHostingController(rootView: view.environment(\.dynamicTypeSize, phone.dynamicType))
        controller.overrideUserInterfaceStyle = .light
        controller.additionalSafeAreaInsets = phone.safeArea
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(origin: .zero, size: phone.size)
        window.rootViewController = controller
        window.isHidden = false
        RunLoop.main.run(until: .now + 0.2)
        settle()
    }

    deinit {
        MainActor.assumeIsolated { window.isHidden = true }
    }

    var bounds: CGRect { CGRect(origin: .zero, size: phone.size) }

    func settle(_ seconds: TimeInterval = 0.3) {
        UIView.performWithoutAnimation {
            window.rootViewController?.view.frame = window.bounds
            window.layoutIfNeeded()
        }
        let deadline = Date.now + seconds
        repeat {
            RunLoop.main.run(until: .now + 0.05)
            window.layoutIfNeeded()
        } while Date.now < deadline
    }

    func elements() -> [Element] {
        guard let root = window.rootViewController?.view else { return [] }
        var found: [Element] = []
        Self.collect(root, into: &found)
        return found
    }

    var scrollViews: [UIScrollView] {
        guard let root = window.rootViewController?.view else { return [] }
        var found: [UIScrollView] = []
        func walk(_ view: UIView) {
            if let scroll = view as? UIScrollView { found.append(scroll) }
            view.subviews.forEach(walk)
        }
        walk(root)
        return found
    }

    /// Every scroll view that has more to show below, moved to its end.
    func scrollToEnd() {
        for scroll in scrollViews where scroll.contentSize.height > scroll.bounds.height + 1 {
            scroll.setContentOffset(
                CGPoint(x: scroll.contentOffset.x, y: scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom),
                animated: false)
        }
        settle()
    }

    func element(id: String) -> Element? { elements().first { $0.identifier == id } }
    func element(label: String) -> Element? { elements().first { $0.label == label } }

    private static func string(_ object: NSObject, _ key: String) -> String {
        guard object.responds(to: Selector(key)) else { return "" }
        return object.value(forKey: key) as? String ?? ""
    }

    private static func collect(_ object: NSObject, into found: inout [Element], depth: Int = 0) {
        var seen = Set<ObjectIdentifier>()
        visit(object, into: &found, seen: &seen, depth: depth)
    }

    private static func children(_ object: NSObject) -> [NSObject] {
        var result: [NSObject] = []
        let count = object.accessibilityElementCount()
        if count != NSNotFound, count > 0 {
            for index in 0..<count { if let child = object.accessibilityElement(at: index) as? NSObject { result.append(child) } }
        }
        if let elements = object.accessibilityElements { result += elements.compactMap { $0 as? NSObject } }
        if let view = object as? UIView { result += view.subviews }
        return result
    }

    private static func visit(_ object: NSObject, into found: inout [Element], seen: inout Set<ObjectIdentifier>, depth: Int) {
        guard depth < 40, seen.insert(ObjectIdentifier(object)).inserted else { return }
        let identifier = string(object, "accessibilityIdentifier")
        let label = string(object, "accessibilityLabel")
        if !(identifier.isEmpty && label.isEmpty) && !(object is UIWindow) {
            let frame = (object as? UIView).map { $0.convert($0.bounds, to: nil) } ?? object.accessibilityFrame
            found.append(Element(identifier: identifier, label: label, frame: frame))
        }
        for child in children(object) { visit(child, into: &found, seen: &seen, depth: depth + 1) }
    }
}
