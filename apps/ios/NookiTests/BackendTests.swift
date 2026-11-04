import Foundation
import Testing
@testable import Billet

struct BackendTests {
    @Test func aHostBecomesAnHTTPSBaseURL() {
        #expect(Backend.baseURL(host: "api.example.dev")?.absoluteString == "https://api.example.dev")
    }

    @Test func aServerOnThisMacIsPlainHTTP() {
        #expect(Backend.baseURL(host: "127.0.0.1:8787")?.absoluteString == "http://127.0.0.1:8787")
        #expect(Backend.baseURL(host: "localhost:8787")?.absoluteString == "http://localhost:8787")
    }

    @Test func noHostMeansNoBackend() {
        #expect(Backend.baseURL(host: nil) == nil)
        #expect(Backend.baseURL(host: "") == nil)
        #expect(Backend.baseURL(host: "  ") == nil)
        // An unset build setting reaches Info.plist as the empty string, but a URL or path is a mistake.
        #expect(Backend.baseURL(host: "https://api.example.dev") == nil)
        #expect(Backend.live(info: [:]) == nil)
    }
}
