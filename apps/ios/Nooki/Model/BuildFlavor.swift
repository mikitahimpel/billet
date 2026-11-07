import Foundation

/// Which build this is. Labs and the testing tools are for a debug build or one installed from TestFlight; the App
/// Store build never shows them.
enum BuildFlavor {
    static var showsLabs: Bool {
        #if DEBUG
        true
        #else
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }
}
