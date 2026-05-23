import Foundation
import Supabase

enum ShiftsRepository {
    struct CheckInResponse: Decodable {
        let shift: Shift
        let status: String  // "checked_in" or "already_checked_in"
    }

    struct CheckOutResponse: Decodable {
        let shift: Shift
        let status: String
    }

    struct OnShiftResponse: Decodable {
        let shifts: [Shift]
    }

    static func checkIn(siteId: UUID, roleTag: String) async throws -> Shift {
        let response: CheckInResponse = try await SupabaseService.client.functions.invoke(
            "check-in",
            options: FunctionInvokeOptions(body: [
                "site_id": siteId.uuidString.lowercased(),
                "role_tag": roleTag,
            ]),
            decoder: shiftDecoder
        )
        return response.shift
    }

    static func checkOut() async throws -> Shift {
        let response: CheckOutResponse = try await SupabaseService.client.functions.invoke(
            "check-out",
            options: FunctionInvokeOptions(body: [String: String]()),
            decoder: shiftDecoder
        )
        return response.shift
    }

    static func onShift(siteId: UUID) async throws -> [Shift] {
        let response: OnShiftResponse = try await SupabaseService.client.functions.invoke(
            "staff-on-shift",
            options: FunctionInvokeOptions(body: [
                "site_id": siteId.uuidString.lowercased(),
            ]),
            decoder: shiftDecoder
        )
        return response.shifts
    }
}

private let shiftDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601WithFractionalSeconds
    return d
}()
