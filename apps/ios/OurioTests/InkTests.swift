import Foundation
import OurioShared
import Testing
import Wire
@testable import Billet

@Suite struct PaletteInkTests {
    @Test func theServersInksReadAsColours() throws {
        let ink = try #require(
            PaletteInk(Wire.Ink(id: InkId("ink-rose"), name: "Rose", light: "#D2456B", dark: "#FF8FAB", price: 60)))
        #expect(ink.light == 0xD2456B)
        #expect(ink.dark == 0xFF8FAB)
        #expect(PaletteInk.wire(ink.dark) == "#FF8FAB")
        #expect(PaletteInk(Wire.Ink(id: InkId("x"), name: "X", light: "red", dark: "#000000", price: 1)) == nil)
    }

    @Test func theBundledCatalogStartsFree() {
        #expect(PaletteInk.bundled.first == PaletteInk.free)
        #expect(PaletteInk.free.id == InkId.free.rawValue)
        #expect(PaletteInk.bundled.filter { $0.price == 0 } == [PaletteInk.free])
    }

    @Test func oldNotesKeepTheirBrown() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","author":"L","date":0,"text":"hi","paper":"butter"}"#
        let note = try JSONDecoder().decode(Billet.Note.self, from: Data(json.utf8))
        #expect(note.ink == nil)
        #expect(note.inkHex == 0x5B3A28)
    }
}
