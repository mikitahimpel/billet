import Foundation
import Testing
import UIKit
@testable import Billet

@Suite struct WidgetShowcaseTests {
    @Test func idsAreUniqueAndEveryGroupHasItems() {
        let ids = WidgetShowcase.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for group in WidgetShowcase.Group.allCases {
            #expect(!WidgetShowcase.items(in: group).isEmpty, "\(group.title) lists nothing")
        }
    }

    @Test func everyPreviewIsInTheAssetCatalog() {
        for item in WidgetShowcase.all {
            guard let preview = item.preview else { continue }
            #expect(UIImage(named: preview) != nil, "\(item.id): no image named \(preview)")
        }
    }

    @Test func onlyControlsHaveNoPreview() {
        for item in WidgetShowcase.all {
            #expect((item.preview == nil) == (item.group == .controls), "\(item.id)")
        }
    }
}
