import AuthenticationServices
import CryptoKit
import FirebaseAuth
import Foundation
import Security

@MainActor
final class AccountStore: ObservableObject {
  enum State: Equatable {
    case starting
    case ready
    case working
    case failed(String)
  }

  @Published private(set) var state: State = .starting
  @Published private(set) var userID: String?
  @Published private(set) var email: String?
  @Published private(set) var isEmailVerified = false
  @Published private(set) var isAnonymous = true

  private var authHandle: AuthStateDidChangeListenerHandle?
  private var appleNonce: String?
  private var hasStarted = false

  var accountLabel: String {
    if let email, !email.isBlank { return email }
    return isAnonymous ? "Protected guest account" : "Apple account"
  }

  func start() async {
    guard !hasStarted else { return }
    hasStarted = true
    authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
      Task { @MainActor [weak self] in self?.apply(user) }
    }
    if Auth.auth().currentUser == nil {
      do { _ = try await Auth.auth().signInAnonymously() }
      catch { state = .failed(error.localizedDescription) }
    } else {
      apply(Auth.auth().currentUser)
    }
  }

  func submitEmail(_ email: String, password: String, createAccount: Bool) async {
    let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard cleanEmail.contains("@"), password.count >= 6 else {
      state = .failed("Enter a valid email and a password with at least 6 characters.")
      return
    }
    state = .working
    do {
      let result: AuthDataResult
      if createAccount, let current = Auth.auth().currentUser, current.isAnonymous {
        let credential = EmailAuthProvider.credential(withEmail: cleanEmail, password: password)
        result = try await current.link(with: credential)
      } else if createAccount {
        result = try await Auth.auth().createUser(withEmail: cleanEmail, password: password)
      } else {
        result = try await Auth.auth().signIn(withEmail: cleanEmail, password: password)
      }
      if createAccount { try? await result.user.sendEmailVerification() }
      apply(Auth.auth().currentUser)
    } catch {
      state = .failed(error.localizedDescription)
    }
  }

  func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
    let nonce = Self.randomNonce()
    appleNonce = nonce
    request.requestedScopes = [.fullName, .email]
    request.nonce = Self.sha256(nonce)
  }

  func completeAppleAuthorization(_ result: Result<ASAuthorization, Error>) async {
    state = .working
    do {
      let authorization = try result.get()
      guard let appleID = authorization.credential as? ASAuthorizationAppleIDCredential,
        let tokenData = appleID.identityToken,
        let token = String(data: tokenData, encoding: .utf8),
        let nonce = appleNonce
      else { throw AccountError.invalidAppleCredential }

      let credential = OAuthProvider.appleCredential(
        withIDToken: token, rawNonce: nonce, fullName: appleID.fullName)
      if let current = Auth.auth().currentUser, current.isAnonymous {
        do { _ = try await current.link(with: credential) }
        catch {
          // An existing Apple account is a normal return-user path.
          _ = try await Auth.auth().signIn(with: credential)
        }
      } else {
        _ = try await Auth.auth().signIn(with: credential)
      }
      appleNonce = nil
      apply(Auth.auth().currentUser)
    } catch {
      appleNonce = nil
      if (error as? ASAuthorizationError)?.code == .canceled {
        apply(Auth.auth().currentUser)
      } else {
        state = .failed(error.localizedDescription)
      }
    }
  }

  func signOut() async {
    state = .working
    do {
      try Auth.auth().signOut()
      _ = try await Auth.auth().signInAnonymously()
    } catch {
      state = .failed(error.localizedDescription)
    }
  }

  func sendVerificationEmail() async {
    do {
      try await Auth.auth().currentUser?.sendEmailVerification()
      state = .ready
    } catch { state = .failed(error.localizedDescription) }
  }

  func refreshAccount() async {
    do {
      try await Auth.auth().currentUser?.reload()
      apply(Auth.auth().currentUser)
    } catch { state = .failed(error.localizedDescription) }
  }

  private func apply(_ user: User?) {
    userID = user?.uid
    email = user?.email
    isEmailVerified = user?.isEmailVerified ?? false
    isAnonymous = user?.isAnonymous ?? true
    state = user == nil ? .starting : .ready
  }

  private static func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private static func randomNonce(length: Int = 32) -> String {
    precondition(length > 0)
    let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remaining = length
    while remaining > 0 {
      var bytes = [UInt8](repeating: 0, count: 16)
      guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
        fatalError("Unable to create a secure sign-in nonce.")
      }
      for byte in bytes where remaining > 0 && byte < characters.count {
        result.append(characters[Int(byte)])
        remaining -= 1
      }
    }
    return result
  }
}

private enum AccountError: LocalizedError {
  case invalidAppleCredential

  var errorDescription: String? {
    "Apple did not return a usable sign-in credential. Please try again."
  }
}
