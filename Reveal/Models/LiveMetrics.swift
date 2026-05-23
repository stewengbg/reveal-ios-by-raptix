import Foundation

/// Live queue + occupancy for a site. Returned by the
/// `get-live-site-metrics` edge function.
struct LiveMetrics: Codable, Hashable {
    let queueCount: Int
    let occupancyCount: Int
    let queueLastUpdated: Date?
    let occupancyLastUpdated: Date?
    let openAlert: QueueAlert?
    let tenantLogoUrl: String?

    enum CodingKeys: String, CodingKey {
        case queueCount = "queue_count"
        case occupancyCount = "occupancy_count"
        case queueLastUpdated = "queue_last_updated"
        case occupancyLastUpdated = "occupancy_last_updated"
        case openAlert = "open_alert"
        case tenantLogoUrl = "tenant_logo_url"
    }
}

/// Open queue alert state. Returned inline by get-live-site-metrics
/// and directly by acknowledge-queue-alert.
struct QueueAlert: Codable, Hashable {
    let id: UUID
    let threshold: Int
    let triggeredValue: Int
    let acknowledgedBy: UUID?
    let acknowledgedByEmail: String?
    let acknowledgedAt: Date?
    let startedAt: Date
    let isSelfAck: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case threshold
        case triggeredValue = "triggered_value"
        case acknowledgedBy = "acknowledged_by"
        case acknowledgedByEmail = "acknowledged_by_email"
        case acknowledgedAt = "acknowledged_at"
        case startedAt = "started_at"
        case isSelfAck = "is_self_ack"
    }

    var ackerDisplayName: String {
        guard let email = acknowledgedByEmail else { return "Colleague" }
        let local = email.split(separator: "@").first.map(String.init) ?? email
        return local.prefix(1).uppercased() + local.dropFirst()
    }
}

/// A single row from staff_shifts, hydrated with the user's email for
/// avatar rendering. Returned by `check-in`, `check-out`, and
/// `staff-on-shift`.
struct Shift: Codable, Hashable, Identifiable {
    let id: UUID
    let userId: UUID?
    let email: String?
    let roleTag: String
    let checkedInAt: Date
    let checkedOutAt: Date?
    let isSelf: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case email
        case roleTag = "role_tag"
        case checkedInAt = "checked_in_at"
        case checkedOutAt = "checked_out_at"
        case isSelf = "is_self"
    }

    var displayName: String {
        guard let email else { return "Colleague" }
        let local = email.split(separator: "@").first.map(String.init) ?? email
        // Capitalise first letter so "anna" becomes "Anna" in the roster.
        return local.prefix(1).uppercased() + local.dropFirst()
    }

    var initial: String {
        guard let email, let first = email.first else { return "?" }
        return String(first).uppercased()
    }

    var roleLabel: String {
        switch roleTag {
        case "floor": return "Floor"
        case "checkout": return "Checkout"
        case "back_office": return "Back office"
        default: return roleTag.capitalized
        }
    }
}
