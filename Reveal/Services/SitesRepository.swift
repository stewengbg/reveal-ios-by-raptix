import Foundation

enum SitesRepository {
    static func fetchAll() async throws -> [Site] {
        try await SupabaseService.client
            .from("sites")
            .select("id,name,location,is_active,tenant_id,street_address,latitude,longitude")
            .order("name", ascending: true)
            .execute()
            .value
    }
}
