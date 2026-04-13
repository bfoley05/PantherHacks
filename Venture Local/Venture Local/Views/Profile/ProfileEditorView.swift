//
//  ProfileEditorView.swift
//  Venture Local
//

import SwiftData
import SwiftUI
import UIKit

struct ProfileEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.explorationCoordinator) private var explorationCoordinator
    @EnvironmentObject private var theme: ThemeSettings
    @EnvironmentObject private var auth: AuthSessionController
    @EnvironmentObject private var tabRouter: MainShellTabRouter

    @Bindable var profile: ExplorerProfile
    @Query(sort: \FavoritePlace.favoritedAt, order: .reverse) private var favorites: [FavoritePlace]

    @State private var nameDraft: String
    @State private var showResetConfirm = false
    @State private var resetError: String?
    /// Sign out only after this view is torn down; otherwise `ModelContainer` can swap while the sheet still reads `profile`.
    @State private var signOutAfterDisappear = false
    @AppStorage("mapDistanceUsesMiles") private var mapDistanceUsesMiles = Locale.current.measurementSystem == .us

    init(profile: ExplorerProfile) {
        self.profile = profile
        _nameDraft = State(initialValue: profile.displayName)
    }

    private var journalCitySummary: String {
        if let p = profile.pinnedExplorationCityKey, !p.isEmpty {
            return CityKey.displayLabel(for: p)
        }
        return "Following GPS"
    }

    var body: some View {
        let _ = theme.useDarkVintagePalette
        return NavigationStack {
            ZStack {
                PaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("Display name")
                            .font(.vlCaption())
                            .foregroundStyle(VLColor.ink)
                        TextField("Your name", text: $nameDraft)
                            .textContentType(.name)
                            .font(.vlBody(17))
                            .foregroundStyle(VLColor.ink)
                            .tint(VLColor.burgundy)
                            .padding(14)
                            .background(VLColor.paperSurface)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(VLColor.burgundy.opacity(0.35), lineWidth: 2))
                            .cornerRadius(12)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Favorites")
                                .font(.vlCaption())
                                .foregroundStyle(VLColor.subtleInk)
                            NavigationLink {
                                FavoritesListView()
                                    .environmentObject(theme)
                                    .environmentObject(tabRouter)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(favorites.count) place\(favorites.count == 1 ? "" : "s")")
                                            .font(.vlBody(16))
                                            .foregroundStyle(VLColor.ink)
                                        Text("Browse by category")
                                            .font(.vlCaption(12))
                                            .foregroundStyle(VLColor.dustyBlue)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(VLColor.darkTeal.opacity(0.85))
                                }
                                .padding(14)
                                .background(VLColor.paperSurface)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(VLColor.burgundy.opacity(0.28), lineWidth: 1.5))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Journal city")
                                .font(.vlCaption())
                                .foregroundStyle(VLColor.subtleInk)
                            NavigationLink {
                                JournalCityHubView(profile: profile)
                                    .environmentObject(theme)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(journalCitySummary)
                                            .font(.vlBody(16))
                                            .foregroundStyle(VLColor.ink)
                                        Text("Choose city & browse visits")
                                            .font(.vlCaption(12))
                                            .foregroundStyle(VLColor.dustyBlue)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(VLColor.darkTeal.opacity(0.85))
                                }
                                .padding(14)
                                .background(VLColor.paperSurface)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(VLColor.burgundy.opacity(0.28), lineWidth: 1.5))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }

                        NavigationLink {
                            FriendsView()
                                .environmentObject(theme)
                                .environmentObject(auth)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.2.fill")
                                    .font(.body.weight(.semibold))
                                Text("Friends")
                                    .font(.vlBody(16).weight(.semibold))
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.body.weight(.semibold))
                                    .opacity(0.85)
                            }
                            .foregroundStyle(VLColor.profileFriendsLabel)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(VLColor.profileFriendsFill)
                            .cornerRadius(14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(VLColor.profileFriendsBorder, lineWidth: 1.5))
                            .shadow(color: VLColor.profileFriendsFill.opacity(theme.useDarkVintagePalette ? 0.35 : 0.2), radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Appearance")
                                .font(.vlCaption())
                                .foregroundStyle(VLColor.subtleInk)
                            Toggle("Dark vintage palette", isOn: $theme.useDarkVintagePalette)
                                .tint(VLColor.burgundy)
                            Text("In-app ledger colors only; iOS Light/Dark mode is separate (see top-level appearance).")
                                .font(.vlCaption(11))
                                .foregroundStyle(VLColor.subtleInk)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Map distances")
                                .font(.vlCaption())
                                .foregroundStyle(VLColor.subtleInk)
                            Picker("Units", selection: $mapDistanceUsesMiles) {
                                Text("Miles").tag(true)
                                Text("Kilometers").tag(false)
                            }
                            .pickerStyle(.segmented)
                            Text("Used for map voice search and place detail “how far away” hints.")
                                .font(.vlCaption(11))
                                .foregroundStyle(VLColor.subtleInk)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Location")
                                .font(.vlCaption())
                                .foregroundStyle(VLColor.subtleInk)
                            Text("Always allows Venture Local to keep discovery context and nearby place availability current while the app is in the background. iOS shows a blue bar or indicator when location is active.")
                                .font(.vlCaption(12))
                                .foregroundStyle(VLColor.subtleInk)
                                .fixedSize(horizontal: false, vertical: true)
                            if explorationCoordinator?.shouldSuggestAlwaysLocationUpgrade == true {
                                Button {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    Text("Upgrade to Always in Settings")
                                        .font(.vlBody(15))
                                        .foregroundStyle(VLColor.burgundy)
                                }
                            }
                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Text("Open location privacy settings")
                                    .font(.vlCaption(12))
                                    .foregroundStyle(VLColor.darkTeal)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Testing")
                                .font(.vlCaption())
                                .foregroundStyle(VLColor.subtleInk)
                            Button(role: .destructive) {
                                showResetConfirm = true
                            } label: {
                                Text("Clear visits & exploration data on this device")
                                    .font(.vlBody(15))
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(14)
                            .background(VLColor.paperSurface.opacity(0.95))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(VLColor.burgundy.opacity(0.35), lineWidth: 1.5))
                            .cornerRadius(12)
                            Text("Removes discovered places, passport stamps, and resets XP. Your profile name and cached map places stay.")
                                .font(.vlCaption(11))
                                .foregroundStyle(VLColor.subtleInk)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Session")
                                .font(.vlCaption())
                                .foregroundStyle(VLColor.subtleInk)
                            Button {
                                signOutAfterDisappear = true
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(.body.weight(.semibold))
                                    Text("Sign out")
                                        .font(.vlBody(17).weight(.semibold))
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(VLColor.profileSignOutLabel)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(VLColor.profileSignOutFill)
                                .cornerRadius(14)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(VLColor.profileSignOutBorder, lineWidth: 1.5))
                                .shadow(color: Color.black.opacity(theme.useDarkVintagePalette ? 0.35 : 0.12), radius: 10, y: 4)
                            }
                            .buttonStyle(.plain)
                            Text("Ends your Supabase session on this device. Your journal stays on this device until you clear it.")
                                .font(.vlCaption(11))
                                .foregroundStyle(VLColor.subtleInk)
                        }
                        .padding(.top, 8)
                    }
                    .padding(24)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .vintageNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(VLColor.darkTeal)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(VLColor.burgundy)
                }
            }
            .confirmationDialog(
                "Erase exploration data on this device?",
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear all", role: .destructive) { clearExplorationDataForTesting() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes visits, passport stamps, and XP on this device. Your display name and cached map listings stay. This cannot be undone.")
            }
            .alert("Couldn’t clear data", isPresented: Binding(
                get: { resetError != nil },
                set: { if !$0 { resetError = nil } }
            )) {
                Button("OK", role: .cancel) { resetError = nil }
            } message: {
                Text(resetError ?? "")
            }
            .onDisappear {
                guard signOutAfterDisappear else { return }
                signOutAfterDisappear = false
                Task {
                    await Task.yield()
                    await auth.signOut()
                }
            }
        }
    }

    private func save() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.displayName = trimmed.isEmpty ? "Explorer" : trimmed
        try? modelContext.save()
        Task { await CloudSyncService.shared.pushProfileIfPossible(profile: profile) }
        dismiss()
    }

    private func clearExplorationDataForTesting() {
        do {
            try ExplorationProgressReset.clearAllVisitAndExplorationData(in: modelContext)
            explorationCoordinator?.reloadSessionStateAfterDataReset()
        } catch {
            resetError = error.localizedDescription
        }
    }
}
