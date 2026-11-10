import Foundation
import Supabase

enum SupabaseBackend {
    static let client = SupabaseClient(
        supabaseURL: URL(string: "https://posvneeaxnjxxxgiuiws.supabase.co")!,
        supabaseKey: "sb_publishable_0xqMFOWIA2Eq4xsF2G4U3Q_g-JcxfZt",
        options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
    )
}
