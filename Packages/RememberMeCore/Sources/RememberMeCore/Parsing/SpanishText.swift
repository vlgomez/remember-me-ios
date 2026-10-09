/// Palabra del texto original junto con su forma normalizada (minúsculas y sin tildes).
struct Token: Sendable, Hashable {
    let original: String
    let normalized: String

    var startsWithUppercase: Bool {
        original.first?.isUppercase ?? false
    }
}

/// Utilidades de texto para el español. No usa APIs de Foundation dependientes de la plataforma.
enum SpanishText {
    private static let accentFolding: [Character: Character] = [
        "á": "a", "à": "a", "ä": "a", "â": "a",
        "é": "e", "è": "e", "ë": "e", "ê": "e",
        "í": "i", "ì": "i", "ï": "i", "î": "i",
        "ó": "o", "ò": "o", "ö": "o", "ô": "o",
        "ú": "u", "ù": "u", "ü": "u", "û": "u",
        "ñ": "n"
    ]

    private static let edgePunctuation: Set<Character> = [
        ",", ".", ";", ":", "!", "¡", "?", "¿", "\"", "'", "(", ")", "«", "»", "“", "”"
    ]

    /// Minúsculas y sin tildes: "Mañana" → "manana".
    static func normalize(_ text: String) -> String {
        String(text.lowercased().map { accentFolding[$0] ?? $0 })
    }

    /// Separa por espacios y quita la puntuación de los extremos de cada palabra
    /// (conserva la interior, como en "10:30" o "20/11").
    static func tokenize(_ text: String) -> [Token] {
        text.split(whereSeparator: { $0.isWhitespace }).compactMap { piece -> Token? in
            var word = piece
            while let first = word.first, edgePunctuation.contains(first) {
                word = word.dropFirst()
            }
            while let last = word.last, edgePunctuation.contains(last) {
                word = word.dropLast()
            }
            guard !word.isEmpty else { return nil }
            let original = String(word)
            return Token(original: original, normalized: normalize(original))
        }
    }

    static func capitalizingFirstLetter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}

/// Números escritos en cifras o con palabras (solo los que admite la gramática).
enum SpanishNumbers {
    private static let words: [String: Int] = [
        "un": 1, "uno": 1, "una": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5,
        "seis": 6, "siete": 7, "ocho": 8, "nueve": 9, "diez": 10, "once": 11, "doce": 12,
        "trece": 13, "catorce": 14, "quince": 15, "veinte": 20, "treinta": 30
    ]

    static func value(_ normalized: String) -> Int? {
        if !normalized.isEmpty, normalized.allSatisfy({ $0.isASCII && $0.isNumber }) {
            return Int(normalized)
        }
        return words[normalized]
    }
}

enum SpanishCalendarWords {
    static let months: [String: Int] = [
        "enero": 1, "febrero": 2, "marzo": 3, "abril": 4, "mayo": 5, "junio": 6,
        "julio": 7, "agosto": 8, "septiembre": 9, "setiembre": 9, "octubre": 10,
        "noviembre": 11, "diciembre": 12
    ]

    static let weekdays: [String: Weekday] = [
        "lunes": .monday, "martes": .tuesday, "miercoles": .wednesday, "jueves": .thursday,
        "viernes": .friday, "sabado": .saturday, "domingo": .sunday
    ]
}
