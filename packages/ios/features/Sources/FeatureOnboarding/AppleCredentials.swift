import AuthenticationServices
import Foundation
import SwiftUI

/// What Apple's sheet ended with, for the two places that ask it: linking (an identity token for
/// the nonce) and deleting an account (the authorization code the server revokes the token with).
enum AppleSheetOutcome: Equatable {
  case token(String)
  case code(String)
  case cancelled
  case failed

  static func identityToken(of result: Result<ASAuthorization, any Error>) -> Self {
    switch result {
    case .success(let authorization):
      guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
        let data = credential.identityToken, let token = String(data: data, encoding: .utf8)
      else { return .failed }
      return .token(token)
    case .failure(let error): return failure(error)
    }
  }

  static func authorizationCode(of credential: ASAuthorizationAppleIDCredential) -> Self {
    guard let data = credential.authorizationCode, let code = String(data: data, encoding: .utf8)
    else { return .failed }
    return .code(code)
  }

  static func failure(_ error: any Error) -> Self {
    (error as? ASAuthorizationError)?.code == .canceled ? .cancelled : .failed
  }
}

/// A fresh Sign in with Apple, no scopes, for its authorization code: Apple's sheet confirms who
/// is deleting the account, and the server trades the code for the token it revokes.
public enum AppleAuthorizationCode {
  public enum Failure: Error, Equatable, Sendable {
    /// The user closed Apple's sheet: nothing should be deleted.
    case cancelled
    case failed
  }

  @MainActor
  public static func fresh(using controller: AuthorizationController) async throws(Failure)
    -> String
  {
    let request = ASAuthorizationAppleIDProvider().createRequest()
    request.requestedScopes = []
    let result: ASAuthorizationResult
    do {
      result = try await controller.performRequest(request)
    } catch {
      throw AppleSheetOutcome.failure(error) == .cancelled ? .cancelled : .failed
    }
    guard case .appleID(let credential) = result,
      case .code(let code) = AppleSheetOutcome.authorizationCode(of: credential)
    else { throw .failed }
    return code
  }
}
