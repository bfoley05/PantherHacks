//
//  AuthLoginView.swift
//  Venture Local
//

import SwiftUI

struct AuthLoginView: View {
    @EnvironmentObject private var theme: ThemeSettings
    @EnvironmentObject private var auth: AuthSessionController

    @State private var email = ""
    @State private var password = ""
    @State private var isRegisterMode = false
    @State private var isBusy = false
    @State private var isSendingPasswordReset = false

    var body: some View {
        let _ = theme.useDarkVintagePalette
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(spacing: 22) {
                    Text("Venture Local")
                        .font(.vlTitle(28))
                        .foregroundStyle(VLColor.burgundy)
                    Text("Sign in with your explorer account")
                        .font(.vlBody(15))
                        .foregroundStyle(VLColor.darkTeal)
                        .multilineTextAlignment(.center)

                    if auth.configurationMissing {
                        configurationBanner
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.vlCaption())
                            .foregroundStyle(VLColor.dustyBlue)
                        TextField("you@example.com", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.vlBody())
                            .padding(12)
                            .background(VLColor.paperSurface)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(VLColor.burgundy.opacity(0.35), lineWidth: 1.5))
                            .cornerRadius(10)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.vlCaption())
                            .foregroundStyle(VLColor.dustyBlue)
                        SecureField(isRegisterMode ? "At least 8 characters" : "Password", text: $password)
                            .textContentType(isRegisterMode ? .newPassword : .password)
                            .font(.vlBody())
                            .padding(12)
                            .background(VLColor.paperSurface)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(VLColor.burgundy.opacity(0.35), lineWidth: 1.5))
                            .cornerRadius(10)
                        if !isRegisterMode, !auth.configurationMissing {
                            HStack {
                                Spacer(minLength: 0)
                                Button {
                                    Task {
                                        isSendingPasswordReset = true
                                        defer { isSendingPasswordReset = false }
                                        await auth.sendPasswordResetEmail(email: email)
                                    }
                                } label: {
                                    Text("Forgot password?")
                                        .font(.vlCaption(12).weight(.semibold))
                                        .foregroundStyle(VLColor.darkTeal)
                                }
                                .buttonStyle(.plain)
                                .disabled(isBusy || isSendingPasswordReset)
                            }
                        }
                    }

                    if let info = auth.passwordResetSentMessage, !info.isEmpty {
                        Text(info)
                            .font(.vlCaption(12))
                            .foregroundStyle(VLColor.darkTeal)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let err = auth.lastError, !err.isEmpty {
                        Text(err)
                            .font(.vlCaption(12))
                            .foregroundStyle(VLColor.burgundy)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task {
                            isBusy = true
                            defer { isBusy = false }
                            if isRegisterMode {
                                _ = await auth.signUp(email: email, password: password)
                            } else {
                                await auth.signIn(email: email, password: password)
                            }
                        }
                    } label: {
                        HStack {
                            if isBusy { ProgressView().tint(VLColor.cream) }
                            Text(isRegisterMode ? "Create account" : "Sign in")
                                .font(.vlBody(16).weight(.semibold))
                        }
                        .foregroundStyle(VLColor.cream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(auth.configurationMissing ? VLColor.subtleInk : VLColor.burgundy)
                        .cornerRadius(12)
                    }
                    .disabled(isBusy || auth.configurationMissing)

                    Button {
                        isRegisterMode.toggle()
                        auth.lastError = nil
                        auth.clearPasswordResetFeedback()
                    } label: {
                        Text(isRegisterMode ? "Already have an account? Sign in" : "New here? Create an account")
                            .font(.vlCaption(13))
                            .foregroundStyle(VLColor.darkTeal)
                    }
                    .disabled(isBusy)
                }
                .padding(24)
            }
        }
    }

    private var configurationBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Supabase not configured")
                .font(.vlCaption().weight(.semibold))
                .foregroundStyle(VLColor.burgundy)
            Text(
                "Add SUPABASE_URL (https://…supabase.co) and SUPABASE_ANON_KEY to your target’s Info properties, or merge Supporting/SupabaseSecrets.example.plist into the app bundle. Use only the anon key; enable Email auth and RLS in the Supabase dashboard."
            )
            .font(.vlCaption(11))
            .foregroundStyle(VLColor.ink)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VLColor.mutedGold.opacity(0.15))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(VLColor.mutedGold.opacity(0.5), lineWidth: 1))
        .cornerRadius(10)
    }
}
