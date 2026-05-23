import SwiftUI

struct AssociateHomeView: View {
    let assignment: UserRoleAssignment
    @EnvironmentObject private var auth: AuthStore

    @State private var isCheckedIn = false
    @State private var roleTag: RoleTag = .floor
    // Placeholders until Phase 5 wires real data.
    @State private var queueCount = 3
    @State private var customersInStore = 12

    enum RoleTag: String, CaseIterable, Identifiable {
        case floor = "Floor"
        case checkout = "Checkout"
        case backOffice = "Back office"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    siteHeader

                    checkInCard

                    if isCheckedIn {
                        queueCard
                        onShiftWithMe
                        customersNowCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
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
        }
    }

    // MARK: – Site header

    private var siteHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(assignment.primarySite?.name ?? "Your store")
                .font(.title3.bold())
            if let subtitle = assignment.primarySite?.streetAddress ?? assignment.primarySite?.location {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: – Check in / out

    private var checkInCard: some View {
        VStack(spacing: 14) {
            if isCheckedIn {
                Label("On shift since 09:12", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)

                rolePicker
            } else {
                Text("Tap below to start your shift")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                rolePicker
            }

            Button(action: { isCheckedIn.toggle() }) {
                HStack {
                    Image(systemName: isCheckedIn ? "arrow.right.square" : "arrow.right.circle.fill")
                    Text(isCheckedIn ? "Check out" : "Check in")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .tint(isCheckedIn ? .red : .blue)
            .controlSize(.large)
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
                    Text(tag.rawValue)
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

    // MARK: – Queue card (live coordination)

    private var queueCard: some View {
        let count = queueCount
        let level: QueueLevel = count >= 5 ? .red : count >= 3 ? .yellow : .green

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

            if level == .red {
                Button {
                    // Phase 7 — acknowledge alert
                } label: {
                    HStack {
                        Image(systemName: "hand.raised.fill")
                        Text("I've got it").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(level.color.opacity(0.4), lineWidth: level == .red ? 1.5 : 0.5)
        )
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

        var subtitle: String {
            switch self {
            case .green: return "Calm — no action needed."
            case .yellow: return "Steady — keep an eye on it."
            case .red:    return "Queue forming. Open another lane."
            }
        }
    }

    // MARK: – On shift with me

    private var onShiftWithMe: some View {
        // Hardcoded placeholders — Phase 5 staff_shifts pipeline.
        let staff = [
            (name: "Anna", tag: "Checkout"),
            (name: "Erik", tag: "Floor"),
            (name: "Sara", tag: "Back office"),
        ]

        return VStack(alignment: .leading, spacing: 10) {
            Text("On shift with you")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(staff.enumerated()), id: \.offset) { idx, person in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Color.blue.opacity(0.15))
                            Text(String(person.name.prefix(1)))
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.blue)
                        }
                        .frame(width: 36, height: 36)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(person.name).font(.body)
                            Text(person.tag).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    if idx < staff.count - 1 {
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

    // MARK: – Customers now (calm context)

    private var customersNowCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Customers in store")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text("\(customersInStore) right now")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
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
}

#Preview("Off shift") {
    let auth = AuthStore.previewAssociate()
    return AssociateHomeView(assignment: auth.assignment!)
        .environmentObject(auth)
}

#Preview("On shift") {
    let auth = AuthStore.previewAssociate()
    let view = AssociateHomeView(assignment: auth.assignment!)
    return view.environmentObject(auth)
}
