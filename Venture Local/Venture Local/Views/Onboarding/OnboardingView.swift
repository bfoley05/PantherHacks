//
//  OnboardingView.swift
//  Venture Local
//

import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var theme: ThemeSettings
    @Bindable var exploration: ExplorationCoordinator

    @State private var name: String = "Explorer"
    @State private var avatar: ExplorerAvatar = .explorer
    @State private var saveError: String?

    var body: some View {
        let _ = theme.useDarkVintagePalette
        return ZStack {
            PaperBackground()
            VStack(spacing: 24) {
                Text("Your adventure begins…")
                    .font(.vlTitle(26))
                    .foregroundStyle(VLColor.burgundy)
                    .multilineTextAlignment(.center)
                Text("Create your Explorer’s Grimoire")
                    .font(.vlBody())
                    .foregroundStyle(VLColor.darkTeal)

                Text("Venture Local records where you explore in the city—roads you’ve traveled, places you can claim, and partner offers—even when the app isn’t open. iOS will ask for location access: choose “Always Allow” so exploration keeps working in the background. You can change this anytime in Settings.")
                    .font(.vlBody(14))
                    .foregroundStyle(VLColor.dustyBlue)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Name")
                        .font(.vlCaption())
                        .foregroundStyle(VLColor.dustyBlue)
                    TextField("Explorer name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.vlBody())
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Avatar")
                        .font(.vlCaption())
                        .foregroundStyle(VLColor.dustyBlue)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 12) {
                        ForEach(ExplorerAvatar.allCases) { a in
                            Button {
                                avatar = a
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: a.symbol)
                                        .font(.title2)
                                    Text(a.title)
                                        .font(.vlCaption(11))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(avatar == a ? VLColor.darkTeal.opacity(0.2) : VLColor.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(avatar == a ? VLColor.mutedGold : VLColor.burgundy.opacity(0.25), lineWidth: 2)
                                )
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(VLColor.burgundy)
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()

                Button {
                    complete()
                } label: {
                    Text("Continue & allow location")
                        .font(.vlBody(18))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(VLColor.burgundy)
                        .foregroundStyle(VLColor.cream)
                        .cornerRadius(14)
                        .shadow(color: VLColor.mutedGold.opacity(0.35), radius: 8, y: 4)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .padding(.top, 48)
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
            exploration.requestExplorationLocationAccess()
            exploration.startTracking()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
