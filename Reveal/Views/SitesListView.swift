import SwiftUI

@MainActor
final class SitesListModel: ObservableObject {
    enum LoadState {
        case idle, loading
        case loaded([Site])
        case failed(String)
    }

    @Published var state: LoadState = .idle

    func load() async {
        state = .loading
        do {
            let sites = try await SitesRepository.fetchAll()
            state = .loaded(sites)
        } catch {
            state = .failed((error as NSError).localizedDescription)
        }
    }
}

struct SitesListView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model = SitesListModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Sites")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if let email = auth.userEmail {
                                Text(email)
                            }
                            Button("Sign out", role: .destructive) {
                                Task { await auth.signOut() }
                            }
                        } label: {
                            Image(systemName: "person.circle")
                        }
                    }
                }
                .refreshable { await model.load() }
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .loaded(sites) where sites.isEmpty:
            ContentUnavailableView(
                "No sites yet",
                systemImage: "building.2",
                description: Text("Sites you have access to will appear here.")
            )
        case let .loaded(sites):
            List(sites) { site in
                NavigationLink(value: site) {
                    SiteRow(site: site)
                }
            }
            .listStyle(.insetGrouped)
            .navigationDestination(for: Site.self) { site in
                SiteDetailView(site: site)
            }
        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn't load sites", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct SiteRow: View {
    let site: Site

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.tint.opacity(0.15))
                Image(systemName: "building.2")
                    .foregroundStyle(.tint)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(site.name).font(.body).fontWeight(.medium)
                if let subtitle = site.location ?? site.streetAddress {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !site.isActive {
                Text("Paused")
                    .font(.caption2)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.gray.opacity(0.2), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SitesListView().environmentObject(AuthStore.preview)
}
