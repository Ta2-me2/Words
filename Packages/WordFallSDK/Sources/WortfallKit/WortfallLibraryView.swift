import SwiftUI
import WortfallCore

/// A host-owned folder of words. No built-in decks or combined "all words" option.
public struct WortfallDeck: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let cards: [VocabularyCard]
    public init(id: String, name: String, cards: [VocabularyCard]) { self.id = id; self.name = name; self.cards = cards }
}

/// In-scene menu, mode and collection selection, gameplay and detailed statistics.
/// One RealityKit scene is retained across menu, statistics and gameplay transitions.
public struct WortfallLibraryView: View {
    private let libraryID: String
    private let decks: [WortfallDeck]
    private let hostSelection: Binding<String?>?
    @ObservedObject private var progress: WortfallProgress
    @StateObject private var session: GameSession
    @State private var localDeckID: String?
    @State private var activeDeckName = ""
    @State private var activeCardCount = 0
    @State private var settingsVisible = false
    @State private var mode: StudyMode = .wordToTranslation
    @State private var level = 1
    @State private var menuVisible = true
    @State private var statisticsVisible = false
    @State private var exitError: String?
    @State private var saving = false
    private let panelColor = Color(rgb: 0x171C2C)
    private let accent = Color(rgb: 0xF39B94)

    public init(libraryID: String, decks: [WortfallDeck], selectedDeckID: Binding<String?>? = nil, progress: WortfallProgress, onAnswer: ((AnswerRecord) -> Void)? = nil, onLevelEnd: ((LevelResult) -> Void)? = nil) {
        self.libraryID = libraryID; self.decks = decks; self.hostSelection = selectedDeckID; self.progress = progress
        _localDeckID = State(initialValue: decks.first?.id)
        let sceneDeck = (try? VocabularyDeck(cards: decks.first?.cards ?? [])) ?? .demo
        let session = GameSession(deck: sceneDeck, onAnswer: { answer in
            progress.record(answer); onAnswer?(answer)
        }, onLevelEnd: { result in
            progress.record(result); onLevelEnd?(result)
        })
        session.inputSuspended = true
        _session = StateObject(wrappedValue: session)
    }
    private var selection: Binding<String?> {
        hostSelection ?? Binding(get: { localDeckID }, set: { localDeckID = $0 })
    }
    private var selectedDeck: WortfallDeck? { decks.first { $0.id == selection.wrappedValue } }
    private var selectedCards: [VocabularyCard] { selectedDeck?.cards ?? [] }
    private var scopeID: String { "\(libraryID.utf8.count):\(libraryID)/deck/\(selection.wrappedValue ?? "")" }
    private var scopeNames: [String: String] {
        Dictionary(decks.map { ("\(libraryID.utf8.count):\(libraryID)/deck/\($0.id)", $0.name) }, uniquingKeysWith: { first, _ in first })
    }
    private var resumable: Bool { session.snapshot.isPaused && [.playing, .rebound, .finishing].contains(session.snapshot.phase) }
    private var unlocked: Int { progress.snapshot.unlockedLevel(scopeID: scopeID, mode: mode) }
    private var validationError: String? {
        guard selectedDeck != nil else { return "Choose a deck from your app to start." }
        guard Set(decks.map(\.id)).count == decks.count else { return "Deck IDs must be unique." }
        do { _ = try VocabularyDeck(cards: selectedCards, mode: mode); return nil }
        catch { return error.localizedDescription }
    }
    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                WortfallGameView(session: session, onExit: returnToMenu)
                    .allowsHitTesting(!menuVisible)
                if menuVisible && !session.isLoading {
                    LinearGradient(colors: [.black.opacity(0.38), .clear], startPoint: .leading, endPoint: .trailing).allowsHitTesting(false)
                    if statisticsVisible {
                        statisticsPanel(height: geometry.size.height - 48)
                            .frame(width: min(800, geometry.size.width - 64))
                            .frame(maxWidth: .infinity)
                    } else {
                        ScrollView {
                            menuPanel
                        }.scrollIndicators(.hidden)
                            .frame(width: 380)
                            .frame(maxHeight: min(640, geometry.size.height - 48))
                            .background(panelColor.opacity(0.97), in: RoundedRectangle(cornerRadius: 28))
                            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.09)))
                            .shadow(color: .black.opacity(0.3), radius: 28, y: 12)
                            .padding(.leading, geometry.size.width < 950 ? 28 : 48)
                    }
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear { level = unlocked }
        .onChange(of: mode) { _, _ in level = unlocked }
        .onChange(of: selection.wrappedValue) { _, _ in if !resumable { level = unlocked } }
        .onChange(of: session.snapshot.isPaused) { _, paused in
            if paused && [.playing, .rebound, .finishing].contains(session.snapshot.phase) {
                level = session.engine.level; session.inputSuspended = true; menuVisible = true
            }
        }
        .alert("Could not save progress", isPresented: Binding(get: { exitError != nil }, set: { if !$0 { exitError = nil } })) {
            Button("Try again", action: finishReturnToMenu)
            Button("Keep playing", role: .cancel) { exitError = nil }
        } message: { Text(exitError ?? "") }
    }
    private var menuPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("WordFall").font(.system(size: 10, weight: .heavy)).tracking(2.8).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Button { settingsVisible.toggle() } label: {
                    Image(systemName: "gearshape.fill").frame(width: 26, height: 26)
                }.buttonStyle(.plain).accessibilityLabel("Settings")
                    .popover(isPresented: $settingsVisible) {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Settings").font(.headline)
                            Toggle("Game Sounds", isOn: $session.soundEnabled)
                            Toggle("Reduce Motion Effects", isOn: $session.reducedMotion)
                        }.padding(22).frame(width: 260).preferredColorScheme(.dark)
                    }
                Button { session.soundEnabled.toggle() } label: {
                    Image(systemName: session.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .frame(width: 26, height: 26)
                }.buttonStyle(.plain).help("Game sounds").accessibilityLabel("Game sounds")
            }
            VStack(alignment: .leading, spacing: -3) {
                Text("Words.").foregroundStyle(.white)
                Text("Speed.").foregroundStyle(accent)
                Text("Wonder.").foregroundStyle(Color(rgb: 0xB6AEF0))
            }.font(.system(size: 43, weight: .black, design: .rounded))
            Text("Find your word. Catch your rhythm.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.58))
            HStack(spacing: 0) {
                miniStat("Total points", progress.snapshot.earnedPoints.formatted())
                miniStat("Levels", progress.snapshot.totalCompletedLevels.formatted())
                miniStat("Correct", progress.snapshot.totalAttempts == 0 ? "—" : "\(Int(progress.snapshot.correctAnswerRate * 100))%")
            }.padding(.vertical, 12).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            VStack(spacing: 12) {
                if resumable {
                    HStack { Text("Deck"); Spacer(); Text(activeDeckName).foregroundStyle(.secondary) }
                } else {
                    Picker("Deck", selection: selection) {
                        if selectedDeck == nil { Text("Select a deck").tag(nil as String?) }
                        ForEach(decks) { Text($0.name).tag(Optional($0.id)) }
                    }.disabled(decks.isEmpty)
                }
                Picker("Study mode", selection: $mode) { ForEach(StudyMode.allCases) { Text($0.title).tag($0) } }
                HStack {
                    Stepper("Level \(level)", value: $level, in: 1...max(1, unlocked))
                    Spacer()
                    Text("\(resumable ? activeCardCount : selectedCards.count) words · \(Int(LevelProfile(number: level).length)) m")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).fixedSize()
                }
            }.font(.system(size: 12)).controlSize(.regular).disabled(resumable)
            if !resumable, let error = validationError { Label(error, systemImage: "info.circle").font(.caption).foregroundStyle(accent) }
            Button(action: start) {
                HStack { Text(resumable ? "Continue game" : "Let’s slide"); Spacer(); Image(systemName: "arrow.right") }
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(rgb: 0x252438)).padding(16)
                    .background(accent, in: RoundedRectangle(cornerRadius: 15))
                    .opacity(resumable || validationError == nil ? 1 : 0.4)
            }.buttonStyle(.plain).disabled(!resumable && validationError != nil)
            HStack {
                Text("MOUSE · ← → · 1 2 3").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.white.opacity(0.4))
                Spacer()
                Button { statisticsVisible = true } label: { Label("Statistics", systemImage: "chart.bar.xaxis").font(.system(size: 12, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Color(rgb: 0xB6AEF0))
            }
            if resumable { Button("End run", action: finishReturnToMenu).buttonStyle(.plain).font(.caption).foregroundStyle(.secondary) }
            if let error = progress.saveError {
                Text("Save failed: \(error)").font(.caption).foregroundStyle(accent)
                Button("Retry save") { Task { try? await progress.flush() } }
            }
        }.padding(26).foregroundStyle(Color(rgb: 0xECEEFA))
            .environment(\.colorScheme, .dark)
    }
    private func miniStat(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
            Text(name).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 16)
    }
    private func statisticsPanel(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button { statisticsVisible = false } label: { Label("Back to menu", systemImage: "arrow.left") }
                    .buttonStyle(.plain).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("YOUR LEARNING JOURNEY").font(.system(size: 9, weight: .bold)).tracking(1.8).foregroundStyle(.secondary)
            }.padding(24)
            Divider().overlay(.white.opacity(0.07))
            ScrollView {
                WortfallDashboardView(progress: progress, scopeNames: scopeNames).padding(24)
            }
        }.frame(height: min(690, height))
            .background(panelColor.opacity(0.98), in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.1)))
            .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
            .foregroundStyle(Color(rgb: 0xECEEFA)).environment(\.colorScheme, .dark)
    }
    private func start() {
        if resumable { menuVisible = false; session.resume(); return }
        guard let deck = try? VocabularyDeck(cards: selectedCards, mode: mode) else { return }
        activeDeckName = selectedDeck?.name ?? "Deck"
        activeCardCount = selectedCards.count
        guard !session.isLoading else { return }
        menuVisible = false
        Task {
            await session.prepare(deck: deck, level: level, scopeID: scopeID)
            session.start()
        }
    }
    private func returnToMenu() {
        if [.playing, .rebound, .finishing].contains(session.engine.phase) {
            session.pause(); level = session.engine.level; session.inputSuspended = true; menuVisible = true; statisticsVisible = false
            Task { try? await progress.flush() }
        } else { finishReturnToMenu() }
    }
    private func finishReturnToMenu() {
        guard !saving else { return }
        session.pause(); saving = true
        Task {
            defer { saving = false }
            do {
                try await progress.flush()
                level = unlocked
                // Reset to a ready preview while retaining all meshes at the same level.
                let deck = (try? VocabularyDeck(cards: selectedCards, mode: mode)) ?? .demo
                await session.prepare(deck: deck, level: level, scopeID: scopeID)
                session.inputSuspended = true
                menuVisible = true; statisticsVisible = false
            } catch { exitError = error.localizedDescription }
        }
    }
}
