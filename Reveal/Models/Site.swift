import Foundation

struct Site: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let location: String?
    let isActive: Bool
    let tenantId: UUID
    let streetAddress: String?
    let latitude: Double?
    let longitude: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case location
        case isActive = "is_active"
        case tenantId = "tenant_id"
        case streetAddress = "street_address"
        case latitude
        case longitude
    }
}
