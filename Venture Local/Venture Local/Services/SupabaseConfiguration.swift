//
//  SupabaseConfiguration.swift
//  Venture Local
//
//  Loads public Supabase client credentials from the app bundle (Info.plist).
//
//  Security (read before shipping):
//  - Use only the **anon** public key here. Never embed the **service_role** key in an app.
//  - Passwords are never stored on-device; Supabase Auth hashes them server-side over TLS.
//  - Protect user data in Postgres with Row Level Security (RLS) keyed to `auth.uid()`.
//  - Optional `SUPABASE_EMAIL_REDIRECT_URL`: HTTPS page opened after the user taps “confirm email”
//    (must exactly match an entry under Authentication → URL Configuration → Redirect URLs).
//  - For CI/local builds, set `SUPABASE_URL` and `SUPABASE_ANON_KEY` as Xcode User-Defined
//    Build Settings (or duplicate `Supporting/SupabaseSecrets.example.plist` → `SupabaseSecrets.plist`,
//    add it to the target, and keep the copy out of git).
//

import Foundation
import Supabase

enum SupabaseConfiguration {
    /// Builds a client when URL + anon key are non-empty in Info.plist.
    static func makeClient() -> SupabaseClient? {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
            url.scheme == "https" || url.scheme == "http",
            !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        let emailRedirectURL: URL? = {
            guard let s = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_EMAIL_REDIRECT_URL") as? String else {
                return nil
            }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, let u = URL(string: t), u.scheme == "https" || u.scheme == "http" else {
                return nil
            }
            return u
        }()

        // Matches next major supabase-swift default; silences “Initial session emitted after attempting to refresh…”
        // console warning (see https://github.com/supabase/supabase-swift/pull/822).
        let options = SupabaseClientOptions(
            auth: .init(redirectToURL: emailRedirectURL, emitLocalSessionAsInitialSession: true)
        )
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key.trimmingCharacters(in: .whitespacesAndNewlines),
            options: options
        )
    }
}
