import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        switch auth.state {
        case .unknown:
            SplashView()
        case .signedOut:
            AuthView()
        case .signedIn:
            signedInContent
        }
    }

    @ViewBuilder
    private var signedInContent: some View {
        if let assignment = auth.assignment {
            switch assignment.role {
            case .associate:
                AssociateHomeView(assignment: assignment)
            case .manager:
                if let site = assignment.primarySite {
                    NavigationStack {
                        ManagerHomeView(site: site)
                    }
                } else {
                    SitesListView()
                }
            case .owner:
                OwnerHomeView()
            }
        } else if auth.isResolvingRole {
            SplashView()
        } else {
            // No role resolved — user has no memberships. Fall back to the
            // sites list (which will render its empty state thanks to RLS).
            SitesListView()
        }
    }
}

private struct SplashView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text("Reveal")
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                    Text("by Raptix")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ProgressView()
                    .controlSize(.large)
                    .tint(.secondary)
            }
        }
    }
}

#Preview {
    ContentView().environmentObject(AuthStore.preview)
}
