import Design
import Testing
import UIKit

@MainActor
struct NavigationBarStyleTests {
    @Test func theTitleFontsAreTheSameMadeOffTheMainThread() async {
        let onMain = NavigationBarStyle.Fonts()
        let offMain = await Task.detached { NavigationBarStyle.Fonts() }.value
        #expect(offMain.large == onMain.large)
        #expect(offMain.inline == onMain.inline)
        #expect(onMain.large.fontName.localizedCaseInsensitiveContains("rounded"))
        #expect(onMain.inline.fontName.localizedCaseInsensitiveContains("rounded"))
    }

    @Test func applySetsThemOnEveryNavigationBar() {
        NavigationBarStyle.apply()
        let fonts = NavigationBarStyle.Fonts()
        let bar = UINavigationBar.appearance()
        #expect(bar.largeTitleTextAttributes?[.font] as? UIFont == fonts.large)
        #expect(bar.titleTextAttributes?[.font] as? UIFont == fonts.inline)
    }
}
