import Foundation

/// Resolves the current user's role by querying tenant_memberships and
/// site_memberships, then picks the highest-privilege role available.
///
/// Priority (highest first):
///   1. tenant_memberships.role IN ('owner','admin')      → .owner
///   2. tenant_memberships.role IN ('member','manager')   → .manager
///   3. site_memberships.role = 'manager'                 → .manager
///   4. site_memberships.role = 'associate'               → .associate
///
/// Returns nil if the user has no memberships at all. The caller can choose
/// to surface a "no workspace" state in that case.
enum RoleResolver {
    static func resolve(userId: UUID) async throws -> UserRoleAssignment? {
        async let tenantRows: [TenantMembershipRow] = SupabaseService.client
            .from("tenant_memberships")
            .select("role,tenant_id")
            .eq("user_id", value: userId)
            .execute()
            .value

        async let siteRows: [SiteMembershipRow] = SupabaseService.client
            .from("site_memberships")
            .select("role,site_id")
            .eq("user_id", value: userId)
            .execute()
            .value

        let (tenants, sites) = try await (tenantRows, siteRows)

        // Highest-privilege wins.
        if tenants.contains(where: { $0.role == "owner" || $0.role == "admin" }) {
            let primary = try await fetchFirstSiteForCurrentUser()
            return UserRoleAssignment(role: .owner, primarySite: primary)
        }

        if tenants.contains(where: { $0.role == "member" || $0.role == "manager" }) {
            let primary = try await fetchFirstSiteForCurrentUser()
            return UserRoleAssignment(role: .manager, primarySite: primary)
        }

        if let managerSite = sites.first(where: { $0.role == "manager" }) {
            let site = try await fetchSite(id: managerSite.site_id)
            return UserRoleAssignment(role: .manager, primarySite: site)
        }

        if let associateSite = sites.first(where: { $0.role == "associate" }) {
            let site = try await fetchSite(id: associateSite.site_id)
            return UserRoleAssignment(role: .associate, primarySite: site)
        }

        return nil
    }

    private static func fetchFirstSiteForCurrentUser() async throws -> Site? {
        let sites: [Site] = try await SupabaseService.client
            .from("sites")
            .select("id,name,location,is_active,tenant_id,street_address,latitude,longitude")
            .order("name", ascending: true)
            .limit(1)
            .execute()
            .value
        return sites.first
    }

    private static func fetchSite(id: String) async throws -> Site? {
        let sites: [Site] = try await SupabaseService.client
            .from("sites")
            .select("id,name,location,is_active,tenant_id,street_address,latitude,longitude")
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        return sites.first
    }
}
