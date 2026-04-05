//
//  OnboardingView.swift
//  Venture Local
//

import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var theme: ThemeSettings
    @EnvironmentObject private var auth: AuthSessionController
    @Bindable var exploration: ExplorationCoordinator

    @State private var name: String = "Explorer"
    @State private var avatar: ExplorerAvatar = .explorer
    @State private var saveError: String?

    private let avatarColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        let _ = theme.useDarkVintagePalette
        return ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 12) {
                        Text("Your adventure begins…")
                            .font(.vlTitle(28))
                            .foregroundStyle(VLColor.burgundy)
                            .multilineTextAlignment(.center)
                        Text("Create your Explorer’s Grimoire")
                            .font(.vlBody(16).weight(.medium))
                            .foregroundStyle(VLColor.darkTeal)
                            .multilineTextAlignment(.center)
                        Capsule()
                            .fill(VLColor.mutedGold.opacity(0.45))
                            .frame(width: 48, height: 3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
                    .padding(.bottom, 22)

                    Text("Venture Local records where you explore in the city—roads you’ve traveled, places you can claim, and partner offers—even when the app isn’t open. iOS will ask for location access: choose “Always Allow” so exploration keeps working in the background. You can change this anytime in Settings.")
                        .font(.vlBody(15))
                        .foregroundStyle(VLColor.subtleInk)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(4)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(VLColor.cardBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(VLColor.burgundy.opacity(0.12), lineWidth: 1)
                        )
                        .padding(.bottom, 22)

                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name")
                                .font(.vlBody(13).weight(.semibold))
                                .foregroundStyle(VLColor.darkTeal)
                            TextField("Explorer name", text: $name)
                                .textFieldStyle(.plain)
                                .font(.vlBody(17))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(VLColor.cardBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(VLColor.burgundy.opacity(0.18), lineWidth: 1)
                                )
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Avatar")
                                .font(.vlBody(13).weight(.semibold))
                                .foregroundStyle(VLColor.darkTeal)
                            LazyVGrid(columns: avatarColumns, spacing: 12) {
                                ForEach(ExplorerAvatar.allCases) { a in
                                    Button {
                                        avatar = a
                                    } label: {
                                        VStack(spacing: 8) {
                                            Image(systemName: a.symbol)
                                                .font(.system(size: 22, weight: .medium))
                                                .symbolRenderingMode(.hierarchical)
                                            Text(a.title)
                                                .font(.vlBody(13).weight(.medium))
                                                .foregroundStyle(VLColor.ink)
                                                .multilineTextAlignment(.center)
                                                .lineLimit(2)
                                                .minimumScaleFactor(0.88)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .padding(.horizontal, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(avatar == a ? VLColor.darkTeal.opacity(0.14) : VLColor.cardBackground)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(
                                                    avatar == a ? VLColor.mutedGold : VLColor.burgundy.opacity(0.2),
                                                    lineWidth: avatar == a ? 2 : 1
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(VLColor.burgundy)
                                }
                            }
                        }
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(VLColor.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(VLColor.burgundy.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.bottom, 100)
                }
                .padding(.horizontal, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                    .opacity(theme.useDarkVintagePalette ? 0.35 : 0.25)
                Button {
                    complete()
                } label: {
                    Text("Continue & allow location")
                        .font(.vlBody(17).weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(VLColor.burgundy)
                        .foregroundStyle(VLColor.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: VLColor.mutedGold.opacity(0.28), radius: 10, y: 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .background(theme.paperBackdropColor.ignoresSafeArea(edges: .bottom))
            }
        }
        .alert("Couldn’t save profile", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private func complete() {
        do {
            let p = try exploration.fetchOrCreateProfile()
            p.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Explorer" : name
            p.avatarKindRaw = avatar.rawValue
            p.onboardingComplete = true
            try modelContext.save()
            CloudSyncService.shared.bind(auth: auth)
            Task {
                await CloudSyncService.shared.pushProfileIfPossible(profile: p)
                await CloudSyncService.shared.syncAfterSignIn(modelContext: modelContext, localProfile: p)
            }
            exploration.requestExplorationLocationAccess()
            exploration.startTracking()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
