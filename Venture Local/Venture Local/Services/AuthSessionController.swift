//
//  AuthSessionController.swift
//  Venture Local
//
//  Email/password auth via Supabase. Session tokens are persisted by the Supabase SDK (Keychain-backed).
//

import Combine
import Foundation
import Supabase
import SwiftUI

@MainActor
final class AuthSessionController: ObservableObject {
    private let client: SupabaseClient?

    @Published private(set) var session: Session?
    @Published private(set) var isBootstrapping = true
    @Published var lastError: String?
    /// Set after a successful password-reset email request (cleared on sign-in / sign-up / ``clearPasswordResetFeedback()``).
    @Published private(set) var passwordResetSentMessage: String?

    /// True when Info.plist is missing URL or anon key.
    var configurationMissing: Bool { client == nil }

    /// Shared PostgREST / Auth client for sync and social (anon key + user JWT).
    var supabaseClient: SupabaseClient? { client }

    var isSignedIn: Bool { session != nil }

    /// Supabase `auth.users` id for linking local profile rows (no email stored locally).
    var currentSupabaseUserId: String? {
        session?.user.id.uuidString
    }

    init(client: SupabaseClient?) {
        self.client = client
        if client != nil {
            Task { await observeAuthState() }
        } else {
            session = nil
            isBootstrapping = false
        }
    }

    private func observeAuthState() async {
        guard let client else { return }
        session = client.auth.currentSession
        isBootstrapping = false
        for await (_, newSession) in client.auth.authStateChanges {
            session = newSession
            isBootstrapping = false
        }
    }

    func signIn(email: String, password: String) async {
        guard let client else {
            lastError = "Supabase is not configured."
            return
        }
        lastError = nil
        passwordResetSentMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.contains("@"), password.count >= 6 else {
            lastError = "Enter a valid email and a password of at least 6 characters."
            return
        }
        do {
            _ = try await client.auth.signIn(email: trimmedEmail, password: password)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// - Returns: `true` if a session was created. Requires **Confirm email** off in Supabase (Auth → Providers → Email).
    func signUp(email: String, password: String) async -> Bool {
        guard let client else {
            lastError = "Supabase is not configured."
            return false
        }
        lastError = nil
        passwordResetSentMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.contains("@"), password.count >= 8 else {
            lastError = "Use a valid email and a password of at least 8 characters."
            return false
        }
        do {
            let response = try await client.auth.signUp(email: trimmedEmail, password: password)
            if response.session != nil { return true }
            lastError =
                "Sign-up did not return a session. In Supabase: Authentication → Providers → Email → disable “Confirm email”."
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func signOut() async {
        guard let client else { return }
        lastError = nil
        passwordResetSentMessage = nil
        do {
            try await client.auth.signOut()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Sends Supabase’s password-recovery email (user sets a new password from the link).
    func sendPasswordResetEmail(email: String) async {
        guard let client else {
            lastError = "Supabase is not configured."
            return
        }
        lastError = nil
        passwordResetSentMessage = nil
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@") else {
            lastError = "Enter the email address for your account."
            return
        }
        do {
            try await client.auth.resetPasswordForEmail(trimmed, redirectTo: SupabaseConfiguration.emailRedirectURLFromBundle())
            passwordResetSentMessage =
                "If an account exists for that email, you’ll receive a link to reset your password."
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearPasswordResetFeedback() {
        passwordResetSentMessage = nil
    }
}
