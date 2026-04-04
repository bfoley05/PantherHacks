//
//  ProfileEditorView.swift
//  Venture Local
//

import SwiftData
import SwiftUI

struct ProfileEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var profile: ExplorerProfile
    @State private var nameDraft: String

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
        }
    }

    private func save() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.displayName = trimmed.isEmpty ? "Explorer" : trimmed
        try? modelContext.save()
        dismiss()
    }
}
