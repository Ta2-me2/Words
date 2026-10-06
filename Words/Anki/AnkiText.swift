import Foundation

/// What an Anki field holds once the markup is taken off it.
///
/// An Anki field is a fragment of a web page: text with tags in it, entities
/// where characters should be, references to sound files in Anki's own
/// `[sound:…]` syntax and to pictures in `<img>` tags. Words shows plain text in
/// its own layout, so the tags go, the entities become characters, and the
/// references are pulled out to be imported as files.
///
/// Tables are kept as lines rather than thrown away: a deck that explains a
/// grammar point in a table still says something worth reading, and the meaning
/// on a Words card scrolls.
nonisolated struct AnkiValue: Hashable, Sendable {
    var text: String
    var sounds: [String]
    var images: [String]

    var isEmpty: Bool { text.isEmpty && sounds.isEmpty && images.isEmpty }
}

nonisolated enum AnkiText {

    static func parse(_ raw: String) -> AnkiValue {
        var sounds: [String] = []
        var images: [String] = []
        var html = raw

        // [sound:file.mp3]
        while let open = html.range(of: "[sound:"),
              let close = html.range(of: "]", range: open.upperBound ..< html.endIndex) {
            let name = String(html[open.upperBound ..< close.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { sounds.append(name) }
            html.replaceSubrange(open.lowerBound ..< close.upperBound, with: " ")
        }

        var text = ""
        text.reserveCapacity(html.count)
        var index = html.startIndex
        var skipping: String?

        while index < html.endIndex {
            let character = html[index]
            guard character == "<", let end = html[index...].firstIndex(of: ">") else {
                if skipping == nil { text.append(character) }
                index = html.index(after: index)
                continue
            }

            let tag = html[html.index(after: index) ..< end]
            let name = tagName(tag)

            if let closing = skipping {
                if name == "/\(closing)" { skipping = nil }
            } else {
                switch name {
                case "script", "style":
                    skipping = name
                case "img":
                    if let source = attribute("src", in: tag) { images.append(source) }
                case "br", "/div", "/p", "/tr", "/li", "/h1", "/h2", "/h3", "/h4", "/h5", "/h6", "/table", "hr":
                    text.append("\n")
                case "li":
                    text.append("• ")
                case "/td", "/th":
                    text.append("  ·  ")
                default:
                    break
                }
            }
            index = html.index(after: end)
        }

        return AnkiValue(text: tidy(decodeEntities(text)), sounds: sounds, images: images)
    }

    /// Values an author puts in a field to say there is nothing in it.
    static func isPlaceholder(_ text: String) -> Bool {
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "n/a", "na", "n.a.", "-", "–", "—", "none", "null", "nil", "?", "…", "...": true
        default: false
        }
    }

    // MARK: - Pieces

    /// `div`, `/div`, `br` — whatever the tag is called, lower-cased, with the
    /// slash kept for a closing tag and anything after the name ignored.
    private static func tagName(_ tag: Substring) -> String {
        var body = tag.drop { $0.isWhitespace }
        let closing = body.first == "/"
        if closing { body = body.dropFirst().drop { $0.isWhitespace } }
        let name = body.prefix { $0.isLetter || $0.isNumber }.lowercased()
        return closing ? "/\(name)" : name
    }

    private static func attribute(_ name: String, in tag: Substring) -> String? {
        guard let range = tag.range(of: "\(name)=", options: .caseInsensitive) else { return nil }
        var rest = tag[range.upperBound...]
        if let quote = rest.first, quote == "\"" || quote == "'" {
            rest = rest.dropFirst()
            guard let end = rest.firstIndex(of: quote) else { return nil }
            return decodeEntities(String(rest[..<end]))
        }
        let value = rest.prefix { !$0.isWhitespace && $0 != ">" && $0 != "/" }
        return value.isEmpty ? nil : decodeEntities(String(value))
    }

    private static let named: [String: String] = [
        "nbsp": " ", "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "ndash": "–", "mdash": "—", "hellip": "…", "laquo": "«", "raquo": "»",
        "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“", "shy": "",
        "auml": "ä", "ouml": "ö", "uuml": "ü", "Auml": "Ä", "Ouml": "Ö", "Uuml": "Ü", "szlig": "ß",
        "eacute": "é", "egrave": "è", "ecirc": "ê", "agrave": "à", "ccedil": "ç", "ocirc": "ô",
    ]

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            guard text[index] == "&",
                  let semicolon = text[index...].prefix(12).firstIndex(of: ";")
            else {
                result.append(text[index])
                index = text.index(after: index)
                continue
            }

            let body = text[text.index(after: index) ..< semicolon]
            var replacement: String?
            if body.hasPrefix("#x") || body.hasPrefix("#X"), let code = UInt32(body.dropFirst(2), radix: 16) {
                replacement = Unicode.Scalar(code).map { String(Character($0)) }
            } else if body.hasPrefix("#"), let code = UInt32(body.dropFirst()) {
                replacement = Unicode.Scalar(code).map { String(Character($0)) }
            } else {
                replacement = named[String(body)]
            }

            if let replacement {
                result += replacement
                index = text.index(after: semicolon)
            } else {
                result.append(text[index])
                index = text.index(after: index)
            }
        }
        return result
    }

    /// One space between words, no blank lines stacked on blank lines, nothing
    /// hanging off either end.
    private static func tidy(_ text: String) -> String {
        let lines = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .components(separatedBy: .newlines)
            .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ") }
            // A table row ends with the separator its last cell left behind.
            .map { $0.hasSuffix(" ·") ? String($0.dropLast(2)) : $0 }

        var kept: [String] = []
        for line in lines {
            if line.isEmpty, kept.last?.isEmpty ?? true { continue }
            kept.append(line)
        }
        while kept.last?.isEmpty == true { kept.removeLast() }
        return kept.joined(separator: "\n")
    }
}
