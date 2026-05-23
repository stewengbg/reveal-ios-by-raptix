import Foundation
import Supabase

@MainActor
final class AuthStore: ObservableObject {
    enum State { case unknown, signedOut, signedIn }

    @Published private(set) var state: State = .unknown
    @Published private(set) var userEmail: String?
    @Published private(set) var assignment: UserRoleAssignment?
    @Published private(set) var isResolvingRole = false
    @Published var lastError: String?

    private var listenerTask: Task<Void, Never>?
    private var roleResolverTask: Task<Void, Never>?

    func bootstrap() async {
        print("[AuthStore] bootstrap start")
        listenerTask?.cancel()
        listenerTask = Task { [weak self] in
            for await (event, session) in SupabaseService.client.auth.authStateChanges {
                print("[AuthStore] authStateChange event=\(event) hasSession=\(session != nil)")
                self?.apply(event: event, session: session)
            }
        }

        do {
            let session = try await SupabaseService.client.auth.session
            print("[AuthStore] resumed session for \(session.user.email ?? "?")")
            apply(session: session)
        } catch {
            print("[AuthStore] no resumable session: \(error.localizedDescription)")
            if state == .unknown {
                state = .signedOut
                userEmail = nil
            }
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
            resolveRole(for: session.user.id)
        } else {
            state = .signedOut
            userEmail = nil
            assignment = nil
            isResolvingRole = false
            roleResolverTask?.cancel()
        }
    }

    private func resolveRole(for userId: UUID) {
        roleResolverTask?.cancel()
        isResolvingRole = true
        roleResolverTask = Task { [weak self] in
            do {
                let resolved = try await RoleResolver.resolve(userId: userId)
                guard !Task.isCancelled else { return }
                self?.assignment = resolved
                self?.isResolvingRole = false
                print("[AuthStore] resolved role=\(resolved?.role.rawValue ?? "nil") site=\(resolved?.primarySite?.name ?? "nil")")
            } catch {
                guard !Task.isCancelled else { return }
                print("[AuthStore] role resolution failed: \(error.localizedDescription)")
                self?.assignment = nil
                self?.isResolvingRole = false
            }
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

    static func previewAssociate() -> AuthStore {
        let store = AuthStore()
        store.state = .signedIn
        store.userEmail = "meja@jarlegren.se"
        store.assignment = UserRoleAssignment(
            role: .associate,
            primarySite: Site(
                id: UUID(),
                name: "ICA Nära Roslagstull",
                location: "Stockholm",
                isActive: true,
                tenantId: UUID(),
                streetAddress: "Roslagsvägen 17",
                latitude: 59.35,
                longitude: 18.06
            )
        )
        return store
    }
}
