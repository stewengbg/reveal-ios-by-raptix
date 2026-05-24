import Foundation
import Supabase

enum PushTokenRepository {
    static func register(token: String) async throws {
        let _: EmptyResponse = try await SupabaseService.client.functions.invoke(
            "register-push-token",
            options: FunctionInvokeOptions(body: [
                "token": token,
                "platform": "ios",
            ])
        )
    }
}

private struct EmptyResponse: Decodable {}
