import Foundation

/// What the app calls itself when it has to write its name into a file.
nonisolated enum AppVersion {

    /// "Words 1.0.0 (1)" — the version a person reads, and the build behind it
    /// for a bug report that says "it was written by this one".
    static var described: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        return switch (version, build) {
        case let (version?, build?): "Words \(version) (\(build))"
        case let (version?, nil): "Words \(version)"
        default: "Words"
        }
    }
}
