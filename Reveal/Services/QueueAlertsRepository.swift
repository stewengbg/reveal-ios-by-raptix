import Foundation
import Supabase

enum QueueAlertsRepository {
    struct AcknowledgeResponse: Decodable {
        let alert: QueueAlert
    }

    static func acknowledge(siteId: UUID, threshold: Int, triggeredValue: Int) async throws -> QueueAlert {
        let response: AcknowledgeResponse = try await SupabaseService.client.functions.invoke(
            "acknowledge-queue-alert",
            options: FunctionInvokeOptions(body: [
                "site_id": siteId.uuidString.lowercased(),
                "threshold": String(threshold),
                "triggered_value": String(triggeredValue),
            ]),
            decoder: alertDecoder
        )
        return response.alert
    }
}

private let alertDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601WithFractionalSeconds
    return d
}()
