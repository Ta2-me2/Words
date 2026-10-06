import SwiftUI
import UniformTypeIdentifiers

/// Adding a folder of recordings to a vocabulary in one go.
///
/// Files are matched to words by their names, because that is what a folder of
/// recordings actually looks like. Nothing is added until the matching has been
/// shown — including the files that matched nothing, which are the ones the
/// owner will want to rename.
struct AudioMatchSheet: View {
    let profile: LanguageProfile

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var urls: [URL] = []
    @State private var plan = AudioMatchPlan()
    @State private var isTargeted = false
    @State private var isWorking = false
    @State private var added: Int?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Add Recordings",
                subtitle: "Files are matched to words by their name — “Mutter.m4a” to Mutter."
            )

            content
                .padding(.horizontal, Metrics.cardPadding)

            Divider()

            HStack(spacing: 10) {
                if let added {
                    Label("Added \(added) \(added == 1 ? "recording" : "recordings")", systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(Palette.secondaryText)
                }

                Spacer(minLength: 0)

                Button(added == nil ? "Cancel" : "Done", role: added == nil ? .cancel : nil) { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button(title) { performImport() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(plan.matches.isEmpty || isWorking)
            }
            .padding(Metrics.cardPadding)
        }
        .frame(width: 560, height: 460)
    }

    private var title: String {
        if isWorking { return "Adding…" }
        let count = plan.matches.count
        guard count > 0 else { return "Add" }
        return "Add \(count) \(count == 1 ? "Recording" : "Recordings")"
    }

    // MARK: - Choosing files

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
            dropZone

            if !plan.isEmpty {
                Text(summary)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryText)

                matches
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Metrics.rowSpacing)
    }

    private var dropZone: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .imageScale(.large)
                .foregroundStyle(Palette.secondaryText)

            Text(urls.isEmpty
                 ? "Drop audio files or a folder here"
                 : "\(urls.count) \(urls.count == 1 ? "file" : "files") chosen")
                .foregroundStyle(Palette.secondaryText)

            Spacer(minLength: 0)

            Button("Choose…") { choose() }
        }
        .padding(Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: .rect(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(isTargeted ? Palette.selection : Palette.separator, lineWidth: isTargeted ? 1.5 : 1)
        }
        .animation(.easeOut(duration: 0.12), value: isTargeted)
        .dropDestination(for: URL.self) { dropped, _ in
            take(dropped)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private var summary: String {
        var parts = ["\(plan.matches.count) matched"]
        let replacing = plan.matches.count { $0.replacesExisting }
        if replacing > 0 { parts.append("\(replacing) would be replaced") }
        if !plan.unmatched.isEmpty { parts.append("\(plan.unmatched.count) not found") }
        return parts.joined(separator: " · ")
    }

    private var matches: some View {
        Table(rows) {
            TableColumn("Word") { row in
                Text(row.term)
                    .font(.body.weight(row.isMatch ? .medium : .regular))
                    .foregroundStyle(row.isMatch ? Palette.primaryText : Palette.tertiaryText)
            }
            .width(min: 100, ideal: 150)

            TableColumn("File") { row in
                Text(row.filename)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 120, ideal: 200)

            TableColumn("") { row in
                if row.note.isEmpty {
                    EmptyView()
                } else {
                    Text(row.note)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            .width(min: 70, ideal: 90)
        }
        .alternatingRowBackgrounds(.disabled)
        .frame(height: 210)
    }

    /// Matches first, then the files that found nothing — those are the ones
    /// worth reading.
    private var rows: [Row] {
        plan.matches.map {
            Row(id: $0.id, term: $0.term, filename: $0.filename,
                note: $0.replacesExisting ? "Replaces" : "", isMatch: true)
        }
        + plan.unmatched.map {
            Row(id: UUID(), term: "—", filename: $0, note: "No word", isMatch: false)
        }
    }

    private struct Row: Identifiable {
        let id: UUID
        let term: String
        let filename: String
        let note: String
        let isMatch: Bool
    }

    // MARK: - Files

    private func choose() {
        // NSOpenPanel rather than `fileImporter`: this one has to accept a
        // folder and a handful of files in the same breath.
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio]
        panel.prompt = "Choose"
        panel.message = "Choose the recordings, or the folder they are in."

        guard panel.runModal() == .OK else { return }
        take(panel.urls)
    }

    private func take(_ dropped: [URL]) {
        var files: [URL] = []

        for url in dropped {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) else { continue }

            if isDirectory.boolValue {
                let contents = (try? FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.contentTypeKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                files.append(contentsOf: contents.filter(isAudio))
            } else if isAudio(url) {
                files.append(url)
            }
        }

        urls = files
        added = nil
        plan = AudioMatcher.plan(
            filenames: files.map(\.lastPathComponent),
            entries: store.library.entries(in: profile.id),
            language: profile.learningCode
        )
    }

    private func isAudio(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return ["m4a", "mp3", "wav", "aiff", "aac", "caf"].contains(url.pathExtension.lowercased())
        }
        return type.conforms(to: .audio)
    }

    private func performImport() {
        let byName = Dictionary(uniqueKeysWithValues: urls.map { ($0.lastPathComponent, $0) })
        let items = plan.matches.compactMap { match -> (url: URL, entryID: UUID)? in
            guard let url = byName[match.filename] else { return nil }
            return (url, match.entryID)
        }

        isWorking = true
        Task {
            let count = await store.attachAudio(items, kind: .imported)
            isWorking = false
            added = count
            urls = []
            plan = AudioMatchPlan()
        }
    }
}
