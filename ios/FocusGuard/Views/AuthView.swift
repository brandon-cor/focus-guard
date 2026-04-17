import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @EnvironmentObject var api: APIClient
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "timer")
                    .font(.system(size: 64))
                    .foregroundStyle(.primary)
                Text("Focus Guard")
                    .font(.largeTitle.bold())
                Text("Block distractions. Stay in flow.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let err = errorMessage {
                Text(err)
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Apple's built-in Sign in with Apple button — required by App Store guidelines
            SignInWithAppleButton(.signIn, onRequest: configureRequest, onCompletion: handleCompletion)
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .padding(.horizontal, 40)

            Spacer().frame(height: 40)
        }
    }

    private func configureRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.email]
    }

    private func handleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard
                let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = cred.identityToken,
                let token = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = "Could not read Apple identity token."
                return
            }
            Task {
                do {
                    try await api.signInWithApple(identityToken: token)
                } catch {
                    errorMessage = "Sign in failed: \(error.localizedDescription)"
                }
            }
        case .failure(let error):
            // ASAuthorizationError.canceled is normal (user dismissed), don't show an error
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = "Sign in failed: \(error.localizedDescription)"
            }
        }
    }
}
