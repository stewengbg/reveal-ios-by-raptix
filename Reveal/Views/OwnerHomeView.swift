import SwiftUI

@MainActor
final class OwnerHomeModel: ObservableObject {
    @Published var sites: [Site] = []
    @Published var siteMetrics: [UUID: LiveMetrics] = [:]
    @Published var isLoading = false
    @Published var lastError: String?

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await SitesRepository.fetchAll()
            sites = fetched
            await fetchMetrics(for: fetched)
        } catch {
            lastError = (error as NSError).localizedDescription
        }
    }

    private func fetchMetrics(for sites: [Site]) async {
        // Parallel per-site fetches. With handful-of-sites tenants this is
        // fine; if Reveal ever lands a customer with 30+ sites we'd swap to
        // a single batch endpoint.
        var collected: [UUID: LiveMetrics] = [:]
        await withTaskGroup(of: (UUID, LiveMetrics?).self) { group in
            for site in sites {
                let siteId = site.id
                group.addTask {
                    let m = try? await LiveMetricsRepository.fetch(siteId: siteId)
                    return (siteId, m)
                }
            }
            for await (siteId, metrics) in group {
                if let m = metrics { collected[siteId] = m }
            }
        }
        siteMetrics = collected
    }

    // Aggregate fleet stats derived from the per-site metrics map.
    var totalCustomers: Int { siteMetrics.values.reduce(0) { $0 + $1.occupancyCount } }
    var totalQueue: Int { siteMetrics.values.reduce(0) { $0 + $1.queueCount } }
    var sitesWithAlert: Int { siteMetrics.values.filter { $0.openAlert != nil }.count }

    var firstTenantLogoUrl: String? {
        // Every site in a tenant has the same logo; just use whichever
        // happened to be in the first response.
        siteMetrics.values.first { $0.tenantLogoUrl != nil }?.tenantLogoUrl
    }
}

struct OwnerHomeView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model = OwnerHomeModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    fleetPulse
                    sitesGrid
                    if let error = model.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("All sites")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let urlStr = model.firstTenantLogoUrl, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fit)
                        } placeholder: {
                            Color.clear
                        }
                        .frame(width: 28, height: 28)
                    }
                }
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
            .navigationDestination(for: Site.self) { site in
                ManagerHomeView(site: site)
            }
            .refreshable { await model.load() }
        }
        .task { await model.load() }
    }

    private var fleetPulse: some View {
        HStack(spacing: 12) {
            FleetStat(label: "Customers now", value: "\(model.totalCustomers)")
            FleetStat(label: "In queue", value: "\(model.totalQueue)",
                      tone: model.totalQueue >= 5 ? .alert : .neutral)
            FleetStat(label: "Sites with alert", value: "\(model.sitesWithAlert)",
                      tone: model.sitesWithAlert > 0 ? .alert : .neutral)
        }
    }

    private var sitesGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(model.sites) { site in
                NavigationLink(value: site) {
                    SiteCard(site: site, metrics: model.siteMetrics[site.id])
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct FleetStat: View {
    enum Tone { case neutral, alert }
    let label: String
    let value: String
    var tone: Tone = .neutral

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(label))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .foregroundStyle(tone == .alert ? .red : Color.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SiteCard: View {
    let site: Site
    let metrics: LiveMetrics?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(site.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("People")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(metrics.map { "\($0.occupancyCount)" } ?? "—")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                }
                Spacer()
                queuePill
            }

            if let alert = metrics?.openAlert {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text(alert.acknowledgedByEmail != nil
                         ? "Handled by \(alert.ackerDisplayName)"
                         : "Needs attention")
                        .font(.caption2)
                }
                .foregroundStyle(alert.acknowledgedBy != nil ? .green : .red)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var queuePill: some View {
        let q = metrics?.queueCount ?? 0
        let color: Color = q >= 5 ? .red : q >= 3 ? .orange : .green
        return HStack(spacing: 4) {
            Image(systemName: "person.2.fill").font(.caption2)
            Text("\(q)").font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.15), in: Capsule())
    }
}
