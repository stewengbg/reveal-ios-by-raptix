import Foundation
import Supabase

enum RevealBackend {
    static let url = URL(string: "https://sclptdklvuavvqrnlcpm.supabase.co")!
    // Anon (publishable) key — same one the web app ships in its bundle.
    // RLS enforces tenant scope server-side.
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNjbHB0ZGtsdnVhdnZxcm5sY3BtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU3MzAzMjYsImV4cCI6MjA5MTMwNjMyNn0.YGQOGVMH-ZwO1l3NqoXoFQbrKkJyHvY_-TVm_-jBYJc"
}

enum SupabaseService {
    static let client = SupabaseClient(
        supabaseURL: RevealBackend.url,
        supabaseKey: RevealBackend.anonKey
    )
}
