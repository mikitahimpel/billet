import CoreImage.CIFilterBuiltins
import OurioShared
import SwiftUI
import VisionKit
import Wire

/// What an invite code or link scanned, pasted or typed holds: the code, or nil when it isn't one.
enum InviteInput {
    static func code(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), case .invite(let code)? = DeepLink(url: url) {
            return code.count == InviteCode.length ? OnboardingView.code(from: code) : nil
        }
        let code = OnboardingView.code(from: trimmed)
        let bare = InviteCode.normalized(trimmed).filter { !$0.isWhitespace && $0 != "-" }
        let lengths = [InviteCode.length, InviteCode.reviewLength]
        return lengths.contains(bare.count) && code.count == bare.count ? code : nil
    }
}

enum QRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct InviteScanner: UIViewControllerRepresentable {
    static var isAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    let found: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
            recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        private var done = false

        init(found: @escaping (String) -> Void) { self.found = found }

        func dataScanner(_ scanner: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for case .barcode(let barcode) in added {
                if let payload = barcode.payloadStringValue, let code = InviteInput.code(in: payload) {
                    done = true
                    found(code)
                    return
                }
            }
        }
    }
}
