import Foundation

// The domain model, the scheduler, the queue and the file store have no
// framework dependencies, so they can be checked without building or launching
// the app. Everything the learning loop promises is verified here.

var failures = 0

func check(_ label: String, _ condition: Bool) {
    print(condition ? "  PASS  \(label)" : "  FAIL  \(label)")
    if !condition { failures += 1 }
}

func section(_ title: String) { print("\n\(title)") }

let calendar = Calendar.current

/// A fixed moment, so nothing here depends on the hour the checks are run.
func moment(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

extension JSONDecoder {
    /// The decoder the app itself uses.
    static var words: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

func days(between start: Date, and end: Date) -> Int {
    calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
}

checkScheduler()
checkQueue()
checkDailyLimits()
checkLibrary()
checkWordTableOrder()
checkForgetting()
checkDecks()
await checkSubdecks()
checkInsights()
checkActivityLayout()
checkImport()
checkListPrompt()
checkAssistantBrief()
checkGames()
await checkPractice()
checkEndless()
await checkSession()
await checkPracticeOptions()
checkStreak()
await checkResume()
await checkAudio()
await checkAssociations()
await checkAnki()
await checkAnkiDecks()
checkVoiceCatalogue()
await checkPersistence()
await checkStore()

print("")
if failures == 0 {
    print("all checks passed")
} else {
    print("\(failures) check(s) failed")
    exit(1)
}
