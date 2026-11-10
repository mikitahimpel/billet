import Design
import Foundation
import SwiftUI
import Testing
@testable import Billet

/// Every design component, and the key screens, at the SE and Pro Max sizes and at the largest accessibility text
/// size, against the references in packages/ios/design/Tests/Gallery. Run with `scripts/gallery.sh`.
@MainActor @Suite(.serialized) struct GalleryTests {
    @Test(arguments: GalleryPage.allCases, Snapshot.Variant.allCases)
    func component(_ page: GalleryPage, _ variant: Snapshot.Variant) throws {
        let name = "\(page.rawValue)-\(variant.rawValue)"
        let view = page.view.padding(.vertical, Space.l).frame(maxWidth: .infinity).background(Ink.screen)
        let image = try #require(Snapshot.render(view, variant: variant, fits: true), "\(name) drew nothing")
        try Snapshot.match(image, name: name)
    }

    @Test(arguments: GalleryScreen.allCases, Snapshot.Variant.allCases)
    func screen(_ screen: GalleryScreen, _ variant: Snapshot.Variant) throws {
        let name = "screen-\(screen.rawValue)-\(variant.rawValue)"
        let image = try #require(Snapshot.render(screen.view, variant: variant, fits: false), "\(name) drew nothing")
        try Snapshot.match(image, name: name)
    }
}

/// The screens a change to the design package reaches most, each with fixed content. Onboarding's welcome draws
/// drifting motes and the live hero cat, and the Shop's Today changes with the date, so neither is here.
enum GalleryScreen: String, CaseIterable, Sendable {
    case inbox
    case settings

    @MainActor @ViewBuilder var view: some View {
        switch self {
        case .inbox:
            NavigationStack {
                InboxSheet(model: InboxFixture.model(), state: HomeState(stores: .live())) { _ in }
            }
        case .settings:
            NavigationStack { SettingsView(state: HomeState(stores: .live())) {} }
        }
    }
}
