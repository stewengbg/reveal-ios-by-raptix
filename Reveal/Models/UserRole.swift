import Foundation

/// Coarse user role used by the iOS app to decide which home view to render.
/// Resolved from a combination of `tenant_memberships` and `site_memberships`.
enum UserRole: String, Codable, Hashable {
    case owner       // tenant_memberships.role IN ('owner', 'admin')
    case manager     // tenant_memberships.role IN ('member', 'manager') OR site_memberships.role = 'manager'
    case associate   // only site_memberships.role = 'associate', no tenant_membership
}

/// What the role resolver returns: the picked role plus optional context the
/// home view needs (e.g. which site an associate is tied to).
struct UserRoleAssignment: Hashable {
    let role: UserRole
    /// First site the user is bound to. Owners may have many; associates and
    /// managers typically have one (or a small handful). Phase-1 picks the
    /// first one — multi-site switching is future work.
    let primarySite: Site?
}

/// Raw tenant_memberships row used during resolution.
struct TenantMembershipRow: Codable {
    let role: String
    let tenant_id: String
}

/// Raw site_memberships row used during resolution.
struct SiteMembershipRow: Codable {
    let role: String
    let site_id: String
}
