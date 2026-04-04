//
//  ProfileEditorView.swift
//  Venture Local
//

import SwiftData
import SwiftUI

struct ProfileEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.explorationCoordinator) private var explorationCoordinator

    @Bindable var profile: ExplorerProfile
    @State private var nameDraft: String
    @State private var showResetConfirm = false
    @State private var resetError: String?

    init(profile: ExplorerProfile) {
        self.profile = profile
        _nameDraft = State(initialValue: profile.displayName)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                VStack(alignment: .leading, spacing: 20) {
                    Text("Display name")
                        .font(.vlCaption())
                        .foregroundStyle(Color.black)
                    TextField("Your name", text: $nameDraft)
                        .textContentType(.name)
                        .font(.vlBody(17))
                        .foregroundStyle(Color.black)
                        .tint(Color.black)
                        .padding(14)
                        .background(VLColor.cream)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(VLColor.burgundy.opacity(0.35), lineWidth: 2))
                        .cornerRadius(12)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Testing")
                            .font(.vlCaption())
                            .foregroundStyle(Color.black.opacity(0.55))
                        Button(role: .destructive) {
                            showResetConfirm = true
                        } label: {
                            Text("Clear visits & exploration data on this device")
                                .font(.vlBody(15))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(14)
                        .background(VLColor.cream.opacity(0.9))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.35), lineWidth: 1.5))
                        .cornerRadius(12)
                        Text("Removes discovered places, passport stamps, revealed roads, and resets XP. Your profile name and cached map places stay.")
                            .font(.vlCaption(11))
                            .foregroundStyle(Color.black.opacity(0.45))
                    }

                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Profile")
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.black)
                }
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
                Text("This cannot be undone. Cached map POIs and your display name are kept.")
            }
            .alert("Couldn’t clear data", isPresented: Binding(
                get: { resetError != nil },
                set: { if !$0 { resetError = nil } }
            )) {
                Button("OK", role: .cancel) { resetError = nil }
            } message: {
                Text(resetError ?? "")
            }
        }
    }

    private func save() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.displayName = trimmed.isEmpty ? "Explorer" : trimmed
        try? modelContext.save()
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
