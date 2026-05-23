import SwiftUI

struct SiteDetailView: View {
    let site: Site

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                kpiGrid

                placeholder(
                    title: "Hourly visitors",
                    description: "Today's footfall vs typical day — coming next."
                )

                placeholder(
                    title: "Sensors",
                    description: "Live temperature, humidity, queue status — coming next."
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle(site.name)
        .navigationBarTitleDisplayMode(.large)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let address = site.streetAddress ?? site.location {
                Label(address, systemImage: "mappin.and.ellipse")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            KpiCard(title: "Visitors today", value: "—", trend: nil)
            KpiCard(title: "People now", value: "—", trend: nil)
            KpiCard(title: "Checkout queue", value: "—", trend: nil)
            KpiCard(title: "Sensor health", value: "—", trend: nil)
        }
    }

    private func placeholder(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(description).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct KpiCard: View {
    let title: String
    let value: String
    let trend: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title, design: .rounded, weight: .semibold))
            if let trend {
                Text(trend).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    NavigationStack {
        SiteDetailView(site: Site(
            id: UUID(),
            name: "ICA Nära Roslagstull",
            location: "Stockholm",
            isActive: true,
            tenantId: UUID(),
            streetAddress: "Roslagsvägen 17",
            latitude: 59.35,
            longitude: 18.06
        ))
    }
}
