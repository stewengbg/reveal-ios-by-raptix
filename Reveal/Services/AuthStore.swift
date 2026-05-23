import Foundation
import Supabase

@MainActor
final class AuthStore: ObservableObject {
    enum State { case unknown, signedOut, signedIn }

    @Published private(set) var state: State = .unknown
    @Published private(set) var userEmail: String?
    @Published var lastError: String?

    private var listenerTask: Task<Void, Never>?

    func bootstrap() async {
        listenerTask?.cancel()
        listenerTask = Task { [weak self] in
            for await (event, session) in SupabaseService.client.auth.authStateChanges {
                self?.apply(event: event, session: session)
            }
        }

        do {
            let session = try await SupabaseService.client.auth.session
            apply(session: session)
        } catch {
            state = .signedOut
            userEmail = nil
        }
    }

    func signIn(email: String, password: String) async {
        lastError = nil
        do {
            _ = try await SupabaseService.client.auth.signIn(email: email, password: password)
        } catch {
            lastError = friendlyMessage(for: error)
        }
    }

    func signOut() async {
        do {
            try await SupabaseService.client.auth.signOut()
        } catch {
            lastError = friendlyMessage(for: error)
        }
    }

    private func apply(event: AuthChangeEvent, session: Session?) {
        switch event {
        case .signedIn, .tokenRefreshed, .userUpdated, .initialSession:
            apply(session: session)
        case .signedOut, .userDeleted:
            state = .signedOut
            userEmail = nil
        case .passwordRecovery, .mfaChallengeVerified:
            apply(session: session)
        @unknown default:
            apply(session: session)
        }
    }

    private func apply(session: Session?) {
        if let session {
            state = .signedIn
            userEmail = session.user.email
        } else {
            state = .signedOut
            userEmail = nil
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        let msg = (error as NSError).localizedDescription
        if msg.lowercased().contains("invalid login") { return "Wrong email or password." }
        return msg
    }
}

extension AuthStore {
    static var preview: AuthStore {
        let store = AuthStore()
        store.state = .signedIn
        store.userEmail = "stefan@raptix.se"
        return store
    }
}
