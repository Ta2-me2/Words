import SwiftUI
import WortfallKit
import WortfallCore
import UniformTypeIdentifiers

@main
struct WortfallDemo: App {
    @StateObject private var host = DemoDeckSource()
    @NSApplicationDelegateAdaptor(DemoDelegate.self) private var delegate
    var body: some Scene {
        Window("WordFall", id: "main") { DemoRoot(delegate: delegate, host: host).frame(minWidth: 850, minHeight: 700) }
            .defaultSize(width: 1200, height: 820).windowStyle(.hiddenTitleBar)
            .commands { CommandMenu("Decks") { Button("Open decks…") { host.importing = true }.keyboardShortcut("o") } }
    }
}
private struct DemoRoot: View {
    let delegate: DemoDelegate
    @ObservedObject var host: DemoDeckSource
    @State private var progress: WortfallProgress?
    @State private var loadError: String?
    var body: some View {
        Group {
            if let progress { WortfallLibraryView(libraryID: "demo", decks: host.decks, progress: progress) }
            else if let loadError { VStack(spacing: 18) { Text("Could not load progress").font(.title2.bold()); Text(loadError).textSelection(.enabled); Button("Retry") { Task { await load() } } }.padding(40) }
            else { ProgressView("Loading your progress…") }
        }.task {
            if progress == nil { await load() }
            let args = ProcessInfo.processInfo.arguments
            if let index = args.firstIndex(of: "--decks"), args.indices.contains(index + 1), host.decks.isEmpty { host.read(URL(fileURLWithPath: args[index + 1])) }
        }
        .fileImporter(isPresented: $host.importing, allowedContentTypes: [.json]) { result in
            switch result { case .success(let url): host.read(url); case .failure(let error): host.error = error.localizedDescription }
        }
        .alert("Could not open decks", isPresented: Binding(get: { host.error != nil }, set: { if !$0 { host.error = nil } })) { Button("OK") { host.error = nil } } message: { Text(host.error ?? "") }
    }
    @MainActor private func load() async {
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            progress = try await WortfallProgress.open(storage: JSONProgressStorage(url: folder.appendingPathComponent("Wortfall/progress-v1.json")))
            delegate.progress = progress
            loadError = nil
        } catch { loadError = error.localizedDescription }
    }
}

@MainActor
private final class DemoDelegate: NSObject, NSApplicationDelegate {
    var progress: WortfallProgress?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let progress else { return .terminateNow }
        Task {
            do { try await progress.flush(); sender.reply(toApplicationShouldTerminate: true) }
            catch {
                let alert = NSAlert()
                alert.messageText = "Could not save progress"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "Keep app open")
                alert.runModal()
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
}

@MainActor
private final class DemoDeckSource: ObservableObject {
    @Published var decks: [WortfallDeck] = []
    @Published var importing = false
    @Published var error: String?
    func read(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try JSONDecoder().decode([WortfallDeck].self, from: Data(contentsOf: url))
            guard Set(values.map(\.id)).count == values.count else { throw VocabularyError.duplicateID }
            decks = values
        } catch { self.error = error.localizedDescription }
    }
}
