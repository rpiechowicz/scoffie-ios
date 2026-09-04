import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Minimal payload we extract from a successful Sign in with Apple flow
/// and send to our backend `/auth/apple` endpoint.
struct AppleSignInResult {
    let identityToken: String
    let authorizationCode: String?
    /// The pre-hashed nonce generated for this flow. The backend re-hashes
    /// it with SHA256 and compares against the `nonce` claim in the JWT.
    let rawNonce: String
    /// User's Apple ID sub (stable across sessions). Used for keychain lookups / logout.
    let userIdentifier: String
    /// First name from the credential — Apple only returns this on the FIRST sign-in
    /// per Apple ID per app install.
    let givenName: String?
    let familyName: String?
    /// Email from the credential — also only on first sign-in. May be a
    /// `@privaterelay.appleid.com` address.
    let email: String?
}

enum AppleSignInError: LocalizedError {
    case canceled
    case missingIdentityToken
    case invalidTokenEncoding
    case underlying(Error)
    case noPresentationAnchor

    var errorDescription: String? {
        switch self {
        case .canceled:
            return "Logowanie zostało anulowane."
        case .missingIdentityToken:
            return "Apple nie zwróciło identityToken."
        case .invalidTokenEncoding:
            return "Apple identityToken ma nieprawidłowe kodowanie."
        case .noPresentationAnchor:
            return "Brak okna do wyświetlenia ekranu Apple."
        case .underlying(let error):
            return (error as NSError).localizedDescription
        }
    }
}

/// Coordinates a single Sign in with Apple request. Generates a cryptographically
/// secure random nonce, sets SHA256(nonce) on the request, and hands the credential
/// back to the caller as an `AppleSignInResult` (raw nonce included so the backend
/// can verify the token).
///
/// Usage:
///
///     let coordinator = AppleSignInCoordinator()
///     let result = try await coordinator.start()
///     // send result.identityToken + result.rawNonce to backend
@MainActor
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

    private var continuation: CheckedContinuation<AppleSignInResult, Error>?
    private var currentRawNonce: String?

    /// Kicks off the native Apple sign-in UI. Resolves with the credential payload
    /// or throws `AppleSignInError`. Safe to call again after a failure.
    func start() async throws -> AppleSignInResult {
        let rawNonce = Self.randomNonceString()
        self.currentRawNonce = rawNonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        // Apple stores sha256(rawNonce) in the JWT's `nonce` claim.
        request.nonce = Self.sha256Hex(rawNonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    /// Queries Apple for the current credential state for a previously-signed-in user.
    /// Use this on app launch (if we have a stored `appleUserIdentifier`) to decide
    /// whether to auto-sign-out (e.g. user revoked access in Settings → Apple ID → Sign in with Apple).
    static func currentCredentialState(for userIdentifier: String) async -> ASAuthorizationAppleIDProvider.CredentialState {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userIdentifier) { state, _ in
                continuation.resume(returning: state)
            }
        }
    }

    // MARK: - ASAuthorizationControllerDelegate

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            self.handleSuccess(authorization: authorization)
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            self.handleFailure(error: error)
        }
    }

    @MainActor
    private func handleSuccess(authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(.failure(.missingIdentityToken))
            return
        }

        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8),
              !identityToken.isEmpty else {
            finish(.failure(.missingIdentityToken))
            return
        }

        guard let rawNonce = currentRawNonce, !rawNonce.isEmpty else {
            finish(.failure(.missingIdentityToken))
            return
        }

        let authCode = credential.authorizationCode
            .flatMap { String(data: $0, encoding: .utf8) }

        let result = AppleSignInResult(
            identityToken: identityToken,
            authorizationCode: authCode,
            rawNonce: rawNonce,
            userIdentifier: credential.user,
            givenName: credential.fullName?.givenName,
            familyName: credential.fullName?.familyName,
            email: credential.email
        )

        finish(.success(result))
    }

    @MainActor
    private func handleFailure(error: Error) {
        let mapped: AppleSignInError
        if let asError = error as? ASAuthorizationError {
            switch asError.code {
            case .canceled:
                mapped = .canceled
            default:
                mapped = .underlying(error)
            }
        } else {
            mapped = .underlying(error)
        }
        finish(.failure(mapped))
    }

    @MainActor
    private func finish(_ result: Result<AppleSignInResult, AppleSignInError>) {
        guard let continuation else { return }
        self.continuation = nil
        self.currentRawNonce = nil
        switch result {
        case .success(let payload): continuation.resume(returning: payload)
        case .failure(let error):   continuation.resume(throwing: error)
        }
    }

    // MARK: - ASAuthorizationControllerPresentationContextProviding

    nonisolated func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        // Find the current key window on the main thread (delegate runs on main).
        // Fall back to an empty window (rarely — we then fail fast).
        return MainActor.assumeIsolated {
            Self.keyWindow() ?? UIWindow()
        }
    }

    @MainActor
    private static func keyWindow() -> UIWindow? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if let keyWindow = windowScene.keyWindow { return keyWindow }
            if let first = windowScene.windows.first { return first }
        }
        return nil
    }

    // MARK: - Nonce helpers

    /// Cryptographically strong random nonce. Apple recommends 32+ bytes of
    /// unbiased randomness; we use SecRandomCopyBytes.
    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var buffer = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
            if status != errSecSuccess {
                fatalError("Unable to generate nonce: OSStatus \(status)")
            }
            for byte in buffer where remaining > 0 {
                if byte < charset.count {
                    result.append(charset[Int(byte) % charset.count])
                    remaining -= 1
                }
            }
        }
        return result
    }

    /// SHA256(input) as lowercase hex — same representation Apple stores in the
    /// JWT `nonce` claim.
    private static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
