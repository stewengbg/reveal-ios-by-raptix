import SwiftUI

@MainActor
final class ManagerHomeModel: ObservableObject {
    @Published var metrics: LiveMetrics?
    @Published var shifts: [Shift] = []
    @Published var isAcknowledging = false
    @Published var lastError: String?

    let siteId: UUID
    private var pollTask: Task<Void, Never>?

    init(siteId: UUID) {
        self.siteId = siteId
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stopPolling() { pollTask?.cancel() }

    func refresh() async {
        async let metricsTask = LiveMetricsRepository.fetch(siteId: siteId)
        async let shiftsTask = ShiftsRepository.onShift(siteId: siteId)
        do {
            metrics = try await metricsTask
            shifts = try await shiftsTask
        } catch {
            lastError = (error as NSError).localizedDescription
        }
    }

    func acknowledgeQueueAlert(threshold: Int, triggeredValue: Int) async {
        isAcknowledging = true
        defer { isAcknowledging = false }
        do {
            let alert = try await QueueAlertsRepository.acknowledge(
                siteId: siteId,
                threshold: threshold,
                triggeredValue: triggeredValue
            )
            if let m = metrics {
                metrics = LiveMetrics(
                    queueCount: m.queueCount,
                    occupancyCount: m.occupancyCount,
                    queueLastUpdated: m.queueLastUpdated,
                    occupancyLastUpdated: m.occupancyLastUpdated,
                    openAlert: alert,
                    tenantLogoUrl: m.tenantLogoUrl
                )
            }
        } catch {
            lastError = (error as NSError).localizedDescription
        }
    }
}

struct ManagerHomeView: View {
    let site: Site
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model: ManagerHomeModel

    init(site: Site) {
        self.site = site
        _model = StateObject(wrappedValue: ManagerHomeModel(siteId: site.id))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                kpiStrip
                queueCard
                staffOnShiftCard
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
        .navigationTitle(site.name)
        .navigationBarTitleDisplayMode(.large)
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
        .refreshable { await model.refresh() }
        .task {
            model.startPolling()
        }
        .onDisappear { model.stopPolling() }
    }

    private var kpiStrip: some View {
        HStack(spacing: 10) {
            ManagerKpi(label: "Customers now", value: model.metrics.map { "\($0.occupancyCount)" } ?? "—")
            ManagerKpi(label: "In queue", value: model.metrics.map { "\($0.queueCount)" } ?? "—",
                       tone: (model.metrics?.queueCount ?? 0) >= 5 ? .alert : .neutral)
            ManagerKpi(label: "On shift", value: "\(model.shifts.count)")
        }
    }

    @ViewBuilder
    private var queueCard: some View {
        if let alert = model.metrics?.openAlert {
            QueueAlertCard(
                alert: alert,
                isBusy: model.isAcknowledging,
                onAck: {
                    Task {
                        await model.acknowledgeQueueAlert(
                            threshold: alert.threshold,
                            triggeredValue: alert.triggeredValue
                        )
                    }
                }
            )
        }
    }

    @ViewBuilder
    private var staffOnShiftCard: some View {
        if !model.shifts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Staff on shift")
                    .font(.subheadline.weight(.semibold))
                ForEach(model.shifts) { shift in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text(shift.initial)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shift.displayName).font(.subheadline)
                            Text(LocalizedStringKey(shift.roleLabel))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        } else {
            Text("No one is checked in right now.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

private struct ManagerKpi: View {
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

private struct QueueAlertCard: View {
    let alert: QueueAlert
    let isBusy: Bool
    let onAck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Queue forming")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(alert.triggeredValue)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.red)
            }

            if alert.acknowledgedByEmail != nil {
                Text(alert.isSelfAck
                     ? "You've got it"
                     : "\(alert.ackerDisplayName) has taken it")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            } else {
                Button(action: onAck) {
                    HStack {
                        if isBusy { ProgressView().tint(.white) }
                        else { Image(systemName: "hand.raised.fill") }
                        Text("I've got it").bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red, in: Capsule())
                    .foregroundStyle(.white)
                }
                .disabled(isBusy)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.red.opacity(0.3)))
    }
}
