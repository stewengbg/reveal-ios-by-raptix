import SwiftUI

@MainActor
final class AssociateHomeModel: ObservableObject {
    @Published var metrics: LiveMetrics?
    @Published var myShift: Shift?
    @Published var allShifts: [Shift] = []
    @Published var isCheckingIn = false
    @Published var isCheckingOut = false
    @Published var isAcknowledging = false
    @Published var isLoadingInitial = true
    @Published var lastError: String?

    private let siteId: UUID
    private var refreshTask: Task<Void, Never>?

    init(siteId: UUID) {
        self.siteId = siteId
    }

    func startPolling() {
        stopPolling()
        refreshTask = Task { [weak self] in
            // Tick now, then every 30 s.
            await self?.refresh()
            await MainActor.run { self?.isLoadingInitial = false }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { break }
                await self?.refresh()
            }
        }
    }

    func stopPolling() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() async {
        async let metricsTask = LiveMetricsRepository.fetch(siteId: siteId)
        async let shiftsTask = ShiftsRepository.onShift(siteId: siteId)
        do {
            let (m, s) = try await (metricsTask, shiftsTask)
            metrics = m
            allShifts = s
            myShift = s.first(where: { ($0.isSelf ?? false) && $0.checkedOutAt == nil })
            lastError = nil
        } catch {
            print("[AssociateHomeModel] refresh failed: \(error.localizedDescription)")
            lastError = (error as NSError).localizedDescription
        }
    }

    func checkIn(roleTag: String) async {
        isCheckingIn = true
        defer { isCheckingIn = false }
        do {
            let shift = try await ShiftsRepository.checkIn(siteId: siteId, roleTag: roleTag)
            myShift = shift
            await refresh()
        } catch {
            lastError = (error as NSError).localizedDescription
        }
    }

    func checkOut() async {
        isCheckingOut = true
        defer { isCheckingOut = false }
        do {
            _ = try await ShiftsRepository.checkOut()
            myShift = nil
            await refresh()
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
            // Optimistically merge into the local metrics so the tile
            // updates instantly without waiting for the next poll.
            if let current = metrics {
                metrics = LiveMetrics(
                    queueCount: current.queueCount,
                    occupancyCount: current.occupancyCount,
                    queueLastUpdated: current.queueLastUpdated,
                    occupancyLastUpdated: current.occupancyLastUpdated,
                    openAlert: alert,
                    tenantLogoUrl: current.tenantLogoUrl
                )
            }
        } catch {
            lastError = (error as NSError).localizedDescription
        }
    }
}

struct AssociateHomeView: View {
    let assignment: UserRoleAssignment
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model: AssociateHomeModel
    @State private var roleTag: RoleTag = .floor

    init(assignment: UserRoleAssignment) {
        self.assignment = assignment
        let siteId = assignment.primarySite?.id ?? UUID()
        _model = StateObject(wrappedValue: AssociateHomeModel(siteId: siteId))
    }

    enum RoleTag: String, CaseIterable, Identifiable {
        case floor = "Floor"
        case checkout = "Checkout"
        case backOffice = "Back office"
        var id: String { rawValue }

        var apiValue: String {
            switch self {
            case .floor: return "floor"
            case .checkout: return "checkout"
            case .backOffice: return "back_office"
            }
        }

        static func fromApi(_ value: String) -> RoleTag {
            switch value {
            case "floor": return .floor
            case "checkout": return .checkout
            case "back_office": return .backOffice
            default: return .floor
            }
        }
    }

    private var isCheckedIn: Bool { model.myShift != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    siteHeader

                    checkInCard

                    if isCheckedIn {
                        queueCard
                        if !otherShifts.isEmpty {
                            onShiftWithMe
                        }
                        customersNowCard
                    }

                    if let error = model.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let urlStr = model.metrics?.tenantLogoUrl,
                       let url = URL(string: urlStr) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
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
            .refreshable { await model.refresh() }
        }
        .task {
            model.startPolling()
            // Sync role tag picker to existing open shift if any.
            if let shift = model.myShift {
                roleTag = RoleTag.fromApi(shift.roleTag)
            }
        }
        .onChange(of: model.myShift?.id) { _, _ in
            if let shift = model.myShift {
                roleTag = RoleTag.fromApi(shift.roleTag)
            }
        }
        .onDisappear { model.stopPolling() }
    }

    // MARK: – Site header

    private var siteHeader: some View {
        Text(assignment.primarySite?.name ?? String(localized: "Your store"))
            .font(.title3.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: – Check in / out

    private var checkInCard: some View {
        VStack(spacing: 14) {
            if let shift = model.myShift {
                Label("On shift since \(timeFormatter.string(from: shift.checkedInAt))",
                      systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if model.isLoadingInitial {
                Label("Loading…", systemImage: "clock")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Tap below to start your shift")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            rolePicker
                .disabled(isCheckedIn || model.isCheckingIn)
                .opacity(isCheckedIn ? 0.6 : 1)

            Button(action: handleButtonTap) {
                HStack {
                    if model.isCheckingIn || model.isCheckingOut {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: isCheckedIn ? "arrow.right.square" : "arrow.right.circle.fill")
                        Text(isCheckedIn ? "Check out" : "Check in")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .tint(isCheckedIn ? .red : .blue)
            .controlSize(.large)
            .disabled(model.isCheckingIn || model.isCheckingOut || model.isLoadingInitial)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
        )
    }

    private var rolePicker: some View {
        HStack(spacing: 8) {
            ForEach(RoleTag.allCases) { tag in
                Button {
                    roleTag = tag
                } label: {
                    Text(LocalizedStringKey(tag.rawValue))
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            roleTag == tag ? Color.blue.opacity(0.15) : Color.clear,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                roleTag == tag ? Color.blue : Color(.separator),
                                lineWidth: 1
                            )
                        )
                        .foregroundStyle(roleTag == tag ? Color.blue : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func handleButtonTap() {
        Task {
            if isCheckedIn {
                await model.checkOut()
            } else {
                await model.checkIn(roleTag: roleTag.apiValue)
            }
        }
    }

    // MARK: – Queue card

    private var queueCard: some View {
        let count = model.metrics?.queueCount ?? 0
        let level: QueueLevel = count >= 5 ? .red : count >= 3 ? .yellow : .green
        let lastUpdated = model.metrics?.queueLastUpdated
        let alert = model.metrics?.openAlert

        return VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Checkout queue")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text("\(count) waiting")
                        .font(.system(.title, design: .rounded, weight: .semibold))
                }
                Spacer()
                Circle()
                    .fill(level.color)
                    .frame(width: 16, height: 16)
            }

            Text(level.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Three states for level=red:
            //   • No open alert OR alert exists but no ack → big "I've got it" button.
            //   • Alert ack'd by me → green "You've got it" pill.
            //   • Alert ack'd by someone else → grey "{Name} has taken it".
            if level == .red {
                if let alert, alert.acknowledgedBy != nil {
                    if alert.isSelfAck {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("You've got it")
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                        }
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .padding(.vertical, 6)
                        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "person.fill.checkmark")
                                .foregroundStyle(.secondary)
                            Text("\(alert.ackerDisplayName) has taken it")
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .padding(.vertical, 6)
                        .background(.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                } else {
                    Button(action: handleAcknowledge) {
                        HStack {
                            if model.isAcknowledging {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "hand.raised.fill")
                                Text("I've got it").fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                    .disabled(model.isAcknowledging)
                }
            }

            if let lastUpdated {
                Text(relativeTimestamp(lastUpdated))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(level.color.opacity(0.4), lineWidth: level == .red ? 1.5 : 0.5)
        )
    }

    private func handleAcknowledge() {
        let count = model.metrics?.queueCount ?? 0
        Task {
            await model.acknowledgeQueueAlert(threshold: 5, triggeredValue: count)
        }
    }

    private enum QueueLevel {
        case green, yellow, red

        var color: Color {
            switch self {
            case .green: return .green
            case .yellow: return .orange
            case .red:    return .red
            }
        }

        var subtitle: LocalizedStringKey {
            switch self {
            case .green: return "Calm — no action needed."
            case .yellow: return "Steady — keep an eye on it."
            case .red:    return "Queue forming. Open another lane."
            }
        }
    }

    // MARK: – On shift with me

    private var otherShifts: [Shift] {
        model.allShifts.filter { ($0.isSelf ?? false) == false && $0.checkedOutAt == nil }
    }

    private var onShiftWithMe: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("On shift with you")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(otherShifts.enumerated()), id: \.element.id) { idx, person in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Color.blue.opacity(0.15))
                            Text(person.initial)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.blue)
                        }
                        .frame(width: 36, height: 36)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(person.displayName).font(.body)
                            Text(person.roleLabel).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(relativeTimestamp(person.checkedInAt))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                    if idx < otherShifts.count - 1 {
                        Divider().padding(.leading, 48)
                    }
                }
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: – Customers now

    private var customersNowCard: some View {
        let count = model.metrics?.occupancyCount ?? 0
        let lastUpdated = model.metrics?.occupancyLastUpdated

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Customers in store")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text("\(count) right now")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                if let lastUpdated {
                    Text(relativeTimestamp(lastUpdated))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Image(systemName: "figure.walk")
                .font(.title2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: – Formatters

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private func relativeTimestamp(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "Updated just now" }
        if seconds < 3600 {
            let min = Int(seconds / 60)
            return "Updated \(min) min ago"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated \(formatter.localizedString(for: date, relativeTo: .now))"
    }
}

#Preview("On shift") {
    let auth = AuthStore.previewAssociate()
    let view = AssociateHomeView(assignment: auth.assignment!)
    return view.environmentObject(auth)
}
