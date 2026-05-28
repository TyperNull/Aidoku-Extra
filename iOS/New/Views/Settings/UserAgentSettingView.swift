//
//  UserAgentSettingView.swift
//  Aidoku
//

import SwiftUI

struct UserAgentSettingView: View {
    @State private var storedUserAgent: String
    @State private var pickerActive = false
    @State private var showCustomSheet = false
    @State private var customInput = ""

    init() {
        _storedUserAgent = State(initialValue: UserAgentProvider.storedUserAgent())
    }

    private var isCustomSelection: Bool {
        let trimmed = storedUserAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !UserAgentProvider.presets.contains { $0.userAgent == trimmed }
    }

    var body: some View {
        Button {
            pickerActive = true
        } label: {
            NavigationLink(
                destination: pickerList,
                isActive: $pickerActive
            ) {
                HStack {
                    Text(NSLocalizedString("CUSTOM_USER_AGENT"))
                        .lineLimit(1)
                    Spacer()
                    Text(UserAgentProvider.selectionLabel(for: storedUserAgent))
                        .foregroundStyle(Color.secondaryLabel)
                        .lineLimit(1)
                }
            }
            .environment(\.isEnabled, true)
        }
        .foregroundStyle(.primary)
        .sheet(isPresented: $showCustomSheet) {
            customUserAgentSheet
        }
    }

    private var pickerList: some View {
        List {
            Section {
                selectionRow(
                    title: NSLocalizedString("USER_AGENT_DEFAULT", comment: ""),
                    subtitle: nil,
                    selected: storedUserAgent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    applySelection("")
                }
            }

            Section {
                ForEach(UserAgentProvider.presets) { preset in
                    selectionRow(
                        title: preset.title,
                        subtitle: nil,
                        selected: storedUserAgent == preset.userAgent
                    ) {
                        applySelection(preset.userAgent)
                    }
                }
            } header: {
                Text(NSLocalizedString("USER_AGENT_PRESETS_HEADER", comment: ""))
            } footer: {
                Text(NSLocalizedString("USER_AGENT_PRESETS_FOOTER", comment: ""))
            }

            if isCustomSelection {
                Section {
                    selectionRow(
                        title: NSLocalizedString("USER_AGENT_CUSTOM_LABEL", comment: ""),
                        subtitle: storedUserAgent,
                        selected: true
                    ) {
                        customInput = storedUserAgent
                        showCustomSheet = true
                    }
                } header: {
                    Text(NSLocalizedString("USER_AGENT_CURRENT_CUSTOM", comment: ""))
                }
            }

            Section {
                Button {
                    customInput = isCustomSelection ? storedUserAgent : ""
                    showCustomSheet = true
                } label: {
                    Label(NSLocalizedString("USER_AGENT_ADD_CUSTOM", comment: ""), systemImage: "plus.circle.fill")
                }
            }
        }
        .navigationTitle(NSLocalizedString("CUSTOM_USER_AGENT"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var customUserAgentSheet: some View {
        PlatformNavigationStack {
            Form {
                Section {
                    TextField(
                        NSLocalizedString("USER_AGENT_CUSTOM_PLACEHOLDER", comment: ""),
                        text: $customInput,
                        axis: .vertical
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote)
                } footer: {
                    Text(NSLocalizedString("USER_AGENT_CUSTOM_SHEET_FOOTER", comment: ""))
                }
            }
            .navigationTitle(NSLocalizedString("USER_AGENT_ADD_CUSTOM", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("CANCEL")) {
                        showCustomSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("SAVE")) {
                        let trimmed = customInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        applySelection(trimmed)
                        showCustomSheet = false
                    }
                    .disabled(customInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func selectionRow(
        title: String,
        subtitle: String?,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: subtitle == nil ? .center : .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private func applySelection(_ value: String) {
        UserAgentProvider.setUserAgent(value.isEmpty ? nil : value)
        storedUserAgent = UserAgentProvider.storedUserAgent()
        pickerActive = false
    }
}
