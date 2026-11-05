import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The share sheet's "Nooki" action: a page shared from Safari or another app becomes a wish on the holder's list.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(Ink.screen)
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let sheet = UIHostingController(rootView: ShareWishView(
            link: { await Self.link(in: items) },
            done: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }))
        addChild(sheet)
        sheet.view.frame = view.bounds
        sheet.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sheet.view.backgroundColor = .clear
        view.addSubview(sheet.view)
        sheet.didMove(toParent: self)
    }

    /// The shared page: a URL, or the first web link in shared text, as some apps share links as text.
    private static func link(in items: [NSExtensionItem]) async -> URL? {
        let providers = items.flatMap { $0.attachments ?? [] }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await load(URL.self, from: provider), url.scheme?.hasPrefix("http") == true { return url }
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = await load(String.self, from: provider), let url = firstWebLink(in: text) { return url }
        }
        return nil
    }

    private static func load(_ type: URL.Type, from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { done in
            _ = provider.loadObject(ofClass: NSURL.self) { value, _ in
                done.resume(returning: (value as? NSURL) as URL?)
            }
        }
    }

    private static func load(_ type: String.Type, from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { done in
            _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                done.resume(returning: (value as? NSString) as String?)
            }
        }
    }

    private static func firstWebLink(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.matches(in: text, range: range).compactMap(\.url)
            .first { $0.scheme?.hasPrefix("http") == true }
    }
}
