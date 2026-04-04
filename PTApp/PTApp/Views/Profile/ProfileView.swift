//
//  ProfileView.swift
//  PTApp
//

import SwiftUI

struct ProfileView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appState: AppState
    @AppStorage("stride_appearance") private var appearance = "dark"
    @AppStorage("stride_audio_feedback") private var audioFeedback = true
    @AppStorage("stride_voice_type") private var voiceType = "Female"
    @AppStorage("stride_ghost_opacity") private var ghostOpacityPercent = 75
    @AppStorage("stride_privacy_local") private var privacyLocal = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    headerCard
                    ptConnectCard
                    settingsSection
                    librarySection
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(StrideTheme.gradientBackground(for: colorScheme))
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var headerCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(StrideTheme.accent)

            VStack(alignment: .leading, spacing: 6) {
                Text(appState.userName)
                    .font(.title2.weight(.bold))
                Text("Left ACL reconstruction · post-op week 6")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(StrideTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }

    private var ptConnectCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PT Connect")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .textCase(.uppercase)

            Text("Share a one-tap report with your clinician.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.95))

            Button {
                // PDF / QR later
            } label: {
                Label("Share Report", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(StrideTheme.accentDeep)

            Text("In-app PT messaging is coming soon.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [StrideTheme.accent, StrideTheme.accentDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.title3.weight(.bold))

            Group {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Appearance")
                        .font(.subheadline.weight(.semibold))
                    Picker("Appearance", selection: $appearance) {
                        Text("Dark").tag("dark")
                        Text("Light").tag("light")
                    }
                    .pickerStyle(.segmented)
                    Text("Dark is default. Light matches the earlier bright look.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                NavigationLink {
                    Text("Camera calibration")
                        .navigationTitle("Calibration")
                } label: {
                    settingsRow(title: "Camera calibration", subtitle: "Phone height · injury side")
                }

                Toggle(isOn: $audioFeedback) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Audio feedback")
                        Text("Ding on good reps · cue on compensation")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Voice type", selection: $voiceType) {
                    Text("Female").tag("Female")
                    Text("Male").tag("Male")
                    Text("Neutral").tag("Neutral")
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Ghost mode opacity")
                        Spacer()
                        Text("\(ghostOpacityPercent)%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(ghostOpacityPercent) },
                            set: { ghostOpacityPercent = Int($0) }
                        ),
                        in: 50...100,
                        step: 25
                    )
                    .tint(StrideTheme.accent)
                }

                Toggle(isOn: $privacyLocal) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Privacy: videos stay on device")
                        Text("When on, clips never leave your phone.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .background(StrideTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func settingsRow(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Library")
                .font(.title3.weight(.bold))

            libraryLink(title: "How to prop your phone", subtitle: "Short video guide", icon: "iphone.gen3")
            libraryLink(title: "Understanding compensations", subtitle: "What we look for", icon: "brain.head.profile")
            libraryLink(title: "When to rest vs push through", subtitle: "Green / yellow / red flags", icon: "arrow.triangle.2.circlepath")
        }
    }

    private func libraryLink(title: String, subtitle: String, icon: String) -> some View {
        Button {
            // Placeholder
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(StrideTheme.accent)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(StrideTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
