import AppKit
import FoundationModels
import SwiftUI
import WordsCompanion

/// Words › Settings… — the app's own preferences.
///
/// Most of what a learner sets belongs to a language and lives with it. What
/// is here is the app's: how it looks, and which model answers questions about
/// a card.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettings()
            }
            Tab("AI Companion", systemImage: "sparkles") {
                CompanionSettings()
            }
        }
        .frame(width: 560)
    }
}

private struct GeneralSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(AppSettings.Appearance.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Which model answers beside the cards, and installing the ones that run on
/// this Mac.
struct CompanionSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(CompanionInstaller.self) private var installer

    /// The model waiting for the learner to agree to its licence.
    @State private var confirming: CompanionModel?
    @State private var removing: CompanionModel?

    var body: some View {
        Form {
            Section {
                appleRow
                ForEach(CompanionModel.all) { model in
                    localRow(model)
                }
            } header: {
                Text("Model")
            } footer: {
                Text("The companion answers questions about the card in front of you during a sitting — the word, the sentence, the grammar.")
            }

            Section {
                LabeledContent("Stored in") {
                    Button("Show in Finder") { showFolder() }
                        .buttonStyle(.link)
                }
            } footer: {
                Text("Models you install run entirely on this Mac. Nothing you ask them leaves it.")
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { installer.refresh() }
        .alert(
            "Install \(confirming?.name ?? "")?",
            isPresented: .init(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            presenting: confirming
        ) { model in
            Button("Install") { begin(model) }
            Button("Read the \(model.licenseName)") { NSWorkspace.shared.open(model.licenseURL) }
            Button("Cancel", role: .cancel) { }
        } message: { model in
            Text("\(bytes(model.downloadBytes)) is downloaded from Hugging Face. \(model.name) is made by \(model.maker) and provided under the \(model.licenseName); by installing it you agree to them.")
        }
        .alert(
            "Remove \(removing?.name ?? "")?",
            isPresented: .init(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            presenting: removing
        ) { model in
            Button("Remove", role: .destructive) {
                if settings.companionID == model.id { settings.companionID = AppSettings.appleCompanion }
                Task { await installer.remove(model) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { model in
            Text("It frees \(bytes(sizeOf(model))). You can install it again at any time.")
        }
    }

    // MARK: - Apple Intelligence

    private var appleRow: some View {
        CompanionRow(
            isSelected: settings.companionID == AppSettings.appleCompanion,
            isSelectable: true,
            title: "Apple Intelligence",
            detail: "Built into macOS. Nothing to download. Russian is not among its languages yet."
        ) {
            settings.companionID = AppSettings.appleCompanion
        } status: {
            switch CardAssistant.readiness(for: nil) {
            case .ready:
                Label("Ready", systemImage: "checkmark.circle")
                    .foregroundStyle(Palette.secondaryText)
            case .turnedOff:
                Button("Turn On…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            case .preparing:
                Text("Getting ready…")
                    .foregroundStyle(Palette.secondaryText)
            case .unsupported, .notInstalled:
                Text("Not available on this Mac")
                    .foregroundStyle(Palette.secondaryText)
            }
        }
    }

    // MARK: - Models on this Mac

    @ViewBuilder
    private func localRow(_ model: CompanionModel) -> some View {
        let state = installer.state(of: model)
        let installed = installer.isInstalled(model)
        let supported = CardAssistant.canRunLocalModels

        CompanionRow(
            isSelected: settings.companionID == model.id,
            isSelectable: installed && supported,
            title: "\(model.name)",
            detail: "By \(model.maker). Runs on this Mac and speaks Russian among 140 languages\(model.seesPictures ? ", and looks at a card’s picture" : ""). \(bytes(model.downloadBytes)) download."
        ) {
            settings.companionID = model.id
        } status: {
            if !supported {
                Text("Needs macOS 27")
                    .foregroundStyle(Palette.secondaryText)
            } else {
                switch state {
                case .notInstalled:
                    Button("Install…") { confirming = model }
                case .downloading(let fraction, let received, let total):
                    HStack(spacing: 8) {
                        VStack(alignment: .trailing, spacing: 2) {
                            ProgressView(value: fraction)
                                .frame(width: 120)
                            Text("\(bytes(received)) of \(bytes(total))")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(Palette.secondaryText)
                        }
                        Button("Stop", systemImage: "xmark.circle.fill") { installer.cancel(model) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(Palette.secondaryText)
                            .help("Stop the download. What has arrived is kept for next time.")
                    }
                case .installed(let size):
                    HStack(spacing: 8) {
                        Text(bytes(size))
                            .monospacedDigit()
                            .foregroundStyle(Palette.secondaryText)
                        Button("Remove…") { removing = model }
                    }
                case .failed(let message):
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Palette.warning)
                            .help(message)
                        Button("Try Again") { begin(model) }
                    }
                }
            }
        }
    }

    /// Downloads a model and, when it is there, makes it the companion: the
    /// learner asked for it, and being asked to choose it afterwards is a step
    /// that answers itself.
    private func begin(_ model: CompanionModel) {
        installer.install(model) { settings.companionID = model.id }
    }

    private func sizeOf(_ model: CompanionModel) -> Int64 {
        if case .installed(let size) = installer.state(of: model) { return size }
        return model.downloadBytes
    }

    private func showFolder() {
        let folder = CompanionStore.directory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    /// Plain "0 kB" at the start of a download rather than the "Zero kB" the
    /// formatter spells out by default.
    private func bytes(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .file, spellsOutZero: false))
    }
}

/// One model to choose: a round selection mark, its name and what it is, and
/// on the right whatever it needs — installing, a download, removing.
private struct CompanionRow<Status: View>: View {
    let isSelected: Bool
    let isSelectable: Bool
    let title: String
    let detail: String
    let choose: () -> Void
    @ViewBuilder var status: () -> Status

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: choose) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Palette.selection : Palette.tertiaryText)
            }
            .buttonStyle(.plain)
            .disabled(!isSelectable)
            .accessibilityLabel(isSelected ? "\(title), chosen" : "Choose \(title)")

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(isSelectable || isSelected ? 1 : 0.8)

            Spacer(minLength: 12)

            status()
                .controlSize(.small)
        }
        .padding(.vertical, 3)
        .contentShape(.rect)
        .onTapGesture { if isSelectable { choose() } }
    }
}
