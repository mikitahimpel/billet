import AuthenticationServices

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

extension AppleReauthorization {
  /// Shows the system Sign in with Apple sheet and returns its authorization code. No name or
  /// email is asked for: the code is all the server needs to revoke the app's token.
  @MainActor
  public static func system() async -> AppleReauthorization {
    let request = ASAuthorizationAppleIDProvider().createRequest()
    request.requestedScopes = []
    let controller = ASAuthorizationController(authorizationRequests: [request])
    let delegate = AppleReauthorizationDelegate()
    controller.delegate = delegate
    controller.presentationContextProvider = delegate
    let result = await withCheckedContinuation { continuation in
      delegate.continuation = continuation
      controller.performRequests()
    }
    // The controller holds its delegate weakly: both must outlive the sheet.
    withExtendedLifetime((controller, delegate)) {}
    return result
  }
}

/// Holds the continuation until the sheet answers, then resumes it once.
@MainActor
private final class AppleReauthorizationDelegate: NSObject,
  ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding
{
  var continuation: CheckedContinuation<AppleReauthorization, Never>?

  private func finish(_ result: AppleReauthorization) {
    continuation?.resume(returning: result)
    continuation = nil
  }

  func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithAuthorization authorization: ASAuthorization
  ) {
    guard
      let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
      let data = credential.authorizationCode,
      let code = String(data: data, encoding: .utf8)
    else {
      finish(.cancelled)
      return
    }
    finish(.code(code))
  }

  func authorizationController(
    controller: ASAuthorizationController, didCompleteWithError error: any Error
  ) {
    finish(.cancelled)
  }

  func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    #if canImport(UIKit)
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return window }
      guard let scene = scenes.first else { return ASPresentationAnchor() }
      return ASPresentationAnchor(windowScene: scene)
    #else
      NSApplication.shared.keyWindow ?? ASPresentationAnchor()
    #endif
  }
}
