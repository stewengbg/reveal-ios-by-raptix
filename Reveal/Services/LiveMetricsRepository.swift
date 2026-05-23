import Foundation
import Supabase

enum LiveMetricsRepository {
    static func fetch(siteId: UUID) async throws -> LiveMetrics {
        try await SupabaseService.client.functions.invoke(
            "get-live-site-metrics",
            options: FunctionInvokeOptions(
                body: ["site_id": siteId.uuidString.lowercased()]
            ),
            decoder: jsonDecoder
        )
    }
}

private let jsonDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601WithFractionalSeconds
    return d
}()

extension JSONDecoder.DateDecodingStrategy {
    /// Supabase returns timestamps as ISO 8601 with or without fractional
    /// seconds. The default `.iso8601` strategy fails on the fractional
    /// variant, so we use a permissive ISO 8601 formatter.
    static var iso8601WithFractionalSeconds: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = ISO8601DateFormatter.withFraction.date(from: value) {
                return date
            }
            if let date = ISO8601DateFormatter.plain.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO 8601 timestamp: \(value)"
            )
        }
    }
}

private extension ISO8601DateFormatter {
    static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
