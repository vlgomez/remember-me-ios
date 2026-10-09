// Reconocimiento de expresiones españolas sobre una lista de tokens.
// La resolución a fechas concretas está en SpanishExpressionResolver.swift.

/// Expresión de día tal como aparece en el texto, sin resolver.
enum DayExpression: Sendable, Hashable {
    /// "hoy" (0), "mañana" (1), "pasado mañana" (2), "dentro de N días/semanas".
    case relative(days: Int)
    /// "el viernes", "este viernes", "el próximo viernes", "el viernes que viene".
    case weekday(Weekday, WeekdayQualifier)
    /// "el 20 de noviembre [de 2026]", "20/11[/2026]".
    case explicit(day: Int, month: Int, year: Int?)
}

enum WeekdayQualifier: Sendable, Hashable {
    case plain
    case this
    case next
}

/// Franja del día. `noon` solo aparece en "al mediodía".
enum DayPeriod: Sendable, Hashable {
    case morning
    case noon
    case afternoon
    case night
    case dawn
}

struct TimeExpression: Sendable, Hashable {
    let hour: Int
    let minute: Int
    let period: DayPeriod?

    func withPeriod(_ newPeriod: DayPeriod) -> TimeExpression {
        TimeExpression(hour: hour, minute: minute, period: newPeriod)
    }
}

struct DayMention: Sendable, Hashable {
    let expression: DayExpression
    let text: String
}

struct DeadlineMention: Sendable, Hashable {
    let boundary: Deadline.Boundary
    let expression: DayExpression
    /// Antelación indicada junto a la fecha límite ("tres días antes del 20 de noviembre").
    let lead: LeadTime?
    let text: String
}

struct TimeMention: Sendable, Hashable {
    let expression: TimeExpression
    let text: String
}

/// Franja sin hora concreta: "esta tarde", "por la mañana", "de madrugada".
struct VagueMention: Sendable, Hashable {
    let period: DayPeriod
    /// "esta tarde" implica hoy; "por la tarde" no implica ningún día.
    let day: DayExpression?
    let text: String
}

struct ScanResult: Sendable {
    var days: [DayMention] = []
    var deadlines: [DeadlineMention] = []
    var times: [TimeMention] = []
    var vagues: [VagueMention] = []
    var locations: [String] = []
    /// Tokens que no forman parte de ninguna expresión: con ellos se construye el título.
    var leftovers: [Token] = []
}

struct Matched<Value> {
    let value: Value
    let length: Int
}

struct SpanishGrammar {
    let tokens: [Token]

    // MARK: - Recorrido

    /// Recorre los tokens de izquierda a derecha y, en cada posición, prueba los reconocedores
    /// en orden de prioridad. Lo que no reconoce ninguno pasa al título.
    func scan() -> ScanResult {
        var result = ScanResult()
        var index = 0
        while index < tokens.count {
            if let match = matchLeadBeforeDeadline(at: index) {
                result.deadlines.append(
                    DeadlineMention(
                        boundary: .exclusive,
                        expression: match.value.day,
                        lead: match.value.lead,
                        text: text(from: index, length: match.length)
                    )
                )
                index += match.length
            } else if let match = matchDeadline(at: index) {
                result.deadlines.append(
                    DeadlineMention(
                        boundary: match.value.boundary,
                        expression: match.value.day,
                        lead: nil,
                        text: text(from: index, length: match.length)
                    )
                )
                index += match.length
            } else if let match = matchVaguePeriod(at: index) {
                result.vagues.append(
                    VagueMention(
                        period: match.value.period,
                        day: match.value.day,
                        text: text(from: index, length: match.length)
                    )
                )
                index += match.length
            } else if let match = matchTime(at: index) {
                result.times.append(TimeMention(expression: match.value, text: text(from: index, length: match.length)))
                index += match.length
            } else if let match = matchDay(at: index) {
                result.days.append(DayMention(expression: match.value, text: text(from: index, length: match.length)))
                index += match.length
            } else if let match = matchLocation(at: index) {
                result.locations.append(match.value)
                index += match.length
            } else {
                result.leftovers.append(tokens[index])
                index += 1
            }
        }
        return result
    }

    // MARK: - Días

    /// "pasado mañana", "hoy", "mañana", "dentro de N días", "el viernes", "el 20 de noviembre"...
    func matchDay(at index: Int) -> Matched<DayExpression>? {
        if word(index) == "pasado", word(index + 1) == "manana" {
            return Matched(value: .relative(days: 2), length: 2)
        }
        if word(index) == "hoy" {
            return Matched(value: .relative(days: 0), length: 1)
        }
        if word(index) == "manana" {
            return Matched(value: .relative(days: 1), length: 1)
        }
        if let match = matchDayCount(at: index) {
            return match
        }
        if let match = matchWeekday(at: index) {
            return match
        }
        return matchExplicitDate(at: index)
    }

    /// "dentro de 3 días", "en una semana".
    private func matchDayCount(at index: Int) -> Matched<DayExpression>? {
        var cursor = index
        if word(cursor) == "dentro", word(cursor + 1) == "de" {
            cursor += 2
        } else if word(cursor) == "en" {
            cursor += 1
        } else {
            return nil
        }
        guard let numberWord = word(cursor),
              let count = SpanishNumbers.value(numberWord),
              count > 0,
              let unit = word(cursor + 1) else {
            return nil
        }
        let days: Int
        switch unit {
        case "dia", "dias":
            days = count
        case "semana", "semanas":
            days = count * 7
        default:
            return nil
        }
        return Matched(value: .relative(days: days), length: cursor + 2 - index)
    }

    /// "el viernes", "viernes", "este viernes", "el próximo viernes", "el viernes que viene".
    private func matchWeekday(at index: Int) -> Matched<DayExpression>? {
        var cursor = index
        var qualifier = WeekdayQualifier.plain
        if word(cursor) == "el", word(cursor + 1) == "proximo" {
            qualifier = .next
            cursor += 2
        } else if word(cursor) == "proximo" {
            qualifier = .next
            cursor += 1
        } else if word(cursor) == "este" {
            qualifier = .this
            cursor += 1
        } else if word(cursor) == "el" {
            cursor += 1
        }
        guard let name = word(cursor), let weekday = SpanishCalendarWords.weekdays[name] else {
            return nil
        }
        cursor += 1
        if qualifier == .plain, word(cursor) == "que", word(cursor + 1) == "viene" {
            qualifier = .next
            cursor += 2
        }
        return Matched(value: .weekday(weekday, qualifier), length: cursor - index)
    }

    /// "el 20 de noviembre", "20 de noviembre de 2026", "el 20/11", "20/11/2026".
    private func matchExplicitDate(at index: Int) -> Matched<DayExpression>? {
        var cursor = index
        if word(cursor) == "el" {
            cursor += 1
        }
        guard let first = word(cursor) else { return nil }

        if let numeric = Self.parseNumericDate(first) {
            return Matched(
                value: .explicit(day: numeric.day, month: numeric.month, year: numeric.year),
                length: cursor + 1 - index
            )
        }

        guard let dayNumber = SpanishNumbers.value(first),
              word(cursor + 1) == "de",
              let monthName = word(cursor + 2),
              let month = SpanishCalendarWords.months[monthName] else {
            return nil
        }
        cursor += 3
        var year: Int?
        if word(cursor) == "de", let yearWord = word(cursor + 1), yearWord.count == 4, let parsedYear = Int(yearWord) {
            year = parsedYear
            cursor += 2
        }
        return Matched(value: .explicit(day: dayNumber, month: month, year: year), length: cursor - index)
    }

    /// "20/11" o "20/11/2026" (siempre día/mes, nunca mes/día).
    static func parseNumericDate(_ text: String) -> (day: Int, month: Int, year: Int?)? {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              parts.allSatisfy({ part in !part.isEmpty && part.allSatisfy { $0.isASCII && $0.isNumber } }),
              let day = Int(parts[0]),
              let month = Int(parts[1]) else {
            return nil
        }
        var year: Int?
        if parts.count == 3 {
            guard parts[2].count == 4, let parsedYear = Int(parts[2]) else { return nil }
            year = parsedYear
        }
        return (day: day, month: month, year: year)
    }

    // MARK: - Fechas límite

    /// "antes del 20 de noviembre", "antes de mañana", "para el viernes", "hasta el 20/11".
    func matchDeadline(at index: Int) -> Matched<(boundary: Deadline.Boundary, day: DayExpression)>? {
        var cursor = index
        let boundary: Deadline.Boundary
        if word(cursor) == "antes", word(cursor + 1) == "del" || word(cursor + 1) == "de" {
            boundary = .exclusive
            cursor += 2
        } else if word(cursor) == "para" || word(cursor) == "hasta" {
            boundary = .inclusive
            cursor += 1
        } else {
            return nil
        }
        guard let day = matchDay(at: cursor) else { return nil }
        return Matched(value: (boundary: boundary, day: day.value), length: cursor + day.length - index)
    }

    /// "tres días antes del 20 de noviembre", "2 horas antes del viernes".
    func matchLeadBeforeDeadline(at index: Int) -> Matched<(lead: LeadTime, day: DayExpression)>? {
        guard let numberWord = word(index),
              let count = SpanishNumbers.value(numberWord),
              count > 0,
              let unit = word(index + 1) else {
            return nil
        }
        let lead: LeadTime
        switch unit {
        case "dia", "dias":
            lead = .days(count)
        case "semana", "semanas":
            lead = .days(count * 7)
        case "hora", "horas":
            lead = .hours(count)
        default:
            return nil
        }
        guard word(index + 2) == "antes", word(index + 3) == "del" || word(index + 3) == "de" else {
            return nil
        }
        let cursor = index + 4
        guard let day = matchDay(at: cursor) else { return nil }
        return Matched(value: (lead: lead, day: day.value), length: cursor + day.length - index)
    }

    // MARK: - Horas y franjas

    /// "esta tarde" (hoy), "por la mañana", "por la noche", "de madrugada".
    func matchVaguePeriod(at index: Int) -> Matched<(period: DayPeriod, day: DayExpression?)>? {
        if word(index) == "esta", let period = Self.period(named: word(index + 1)) {
            return Matched(value: (period: period, day: .relative(days: 0)), length: 2)
        }
        if word(index) == "por", word(index + 1) == "la", let period = Self.period(named: word(index + 2)) {
            return Matched(value: (period: period, day: nil), length: 3)
        }
        if word(index) == "de", word(index + 1) == "madrugada" {
            return Matched(value: (period: .dawn, day: nil), length: 2)
        }
        return nil
    }

    /// "a las 10", "a la una", "a las 10:30", "a las 10 y media", "a las 9 menos cuarto",
    /// "a las 5 de la tarde", "a las 10h", "18:00", "al mediodía".
    func matchTime(at index: Int) -> Matched<TimeExpression>? {
        if word(index) == "al", word(index + 1) == "mediodia" {
            return Matched(value: TimeExpression(hour: 12, minute: 0, period: .noon), length: 2)
        }

        var cursor = index
        let hasPrefix = word(cursor) == "a" && (word(cursor + 1) == "las" || word(cursor + 1) == "la")
        if hasPrefix {
            cursor += 2
        }
        guard let first = word(cursor) else { return nil }

        var hour: Int
        var minute = 0
        var hasExplicitMinutes = false
        if let clock = Self.parseClock(first) {
            hour = clock.hour
            minute = clock.minute
            hasExplicitMinutes = clock.hasMinutes
        } else if hasPrefix, let number = SpanishNumbers.value(first) {
            hour = number
        } else {
            return nil
        }
        cursor += 1

        if !hasExplicitMinutes {
            if word(cursor) == "y", word(cursor + 1) == "media" {
                minute = 30
                cursor += 2
            } else if word(cursor) == "y", word(cursor + 1) == "cuarto" {
                minute = 15
                cursor += 2
            } else if word(cursor) == "menos", word(cursor + 1) == "cuarto" {
                minute = 45
                hour = hour <= 1 ? 12 : hour - 1
                cursor += 2
            } else if word(cursor) == "y",
                      let minuteWord = word(cursor + 1),
                      let minutes = SpanishNumbers.value(minuteWord),
                      (1...59).contains(minutes) {
                minute = minutes
                cursor += 2
            }
        }

        if word(cursor) == "en", word(cursor + 1) == "punto" {
            cursor += 2
        }

        var period: DayPeriod?
        if word(cursor) == "de", word(cursor + 1) == "la", let named = Self.period(named: word(cursor + 2)) {
            period = named
            cursor += 3
        } else if word(cursor) == "de", word(cursor + 1) == "madrugada" {
            period = .dawn
            cursor += 2
        }

        return Matched(value: TimeExpression(hour: hour, minute: minute, period: period), length: cursor - index)
    }

    /// "10:30" → (10, 30, true); "10h" → (10, 0, false). Un número suelto no es una hora.
    static func parseClock(_ text: String) -> (hour: Int, minute: Int, hasMinutes: Bool)? {
        if text.count > 1, text.hasSuffix("h") {
            let digits = text.dropLast()
            guard digits.allSatisfy({ $0.isASCII && $0.isNumber }), let hour = Int(digits) else { return nil }
            return (hour: hour, minute: 0, hasMinutes: false)
        }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[1].count == 2,
              parts.allSatisfy({ part in !part.isEmpty && part.allSatisfy { $0.isASCII && $0.isNumber } }),
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }
        return (hour: hour, minute: minute, hasMinutes: true)
    }

    static func period(named name: String?) -> DayPeriod? {
        guard let name else { return nil }
        switch name {
        case "manana":
            return .morning
        case "tarde":
            return .afternoon
        case "noche":
            return .night
        case "madrugada":
            return .dawn
        default:
            return nil
        }
    }

    // MARK: - Ubicación

    /// "en Mercadona", "en El Corte Inglés": "en" seguido de palabras que empiezan por mayúscula.
    /// El resultado es solo texto; no se geocodifica.
    func matchLocation(at index: Int) -> Matched<String>? {
        guard word(index) == "en" else { return nil }
        var cursor = index + 1
        var parts: [String] = []
        while cursor < tokens.count, tokens[cursor].startsWithUppercase {
            parts.append(tokens[cursor].original)
            cursor += 1
        }
        guard !parts.isEmpty else { return nil }
        return Matched(value: parts.joined(separator: " "), length: cursor - index)
    }

    // MARK: - Lista de la compra

    private static let shoppingVerbs: Set<String> = [
        "anadir", "anade", "anademe", "agregar", "agrega", "apuntar", "apunta", "apuntame",
        "poner", "pon", "meter", "mete"
    ]

    private static let shoppingListPhrases: [[String]] = [
        ["a", "la", "lista", "de", "la", "compra"],
        ["a", "mi", "lista", "de", "la", "compra"],
        ["en", "la", "lista", "de", "la", "compra"],
        ["en", "mi", "lista", "de", "la", "compra"],
        ["a", "la", "lista", "de", "compras"],
        ["a", "la", "compra"]
    ]

    /// "Añadir detergente a la lista de la compra" → artículo ["detergente"], resto [].
    static func matchShoppingList(_ tokens: [Token]) -> (item: [Token], rest: [Token])? {
        guard let first = tokens.first, shoppingVerbs.contains(first.normalized) else { return nil }
        let words = tokens.map(\.normalized)
        for start in 1..<tokens.count {
            for phrase in shoppingListPhrases where start + phrase.count <= words.count {
                if Array(words[start..<(start + phrase.count)]) == phrase {
                    return (item: Array(tokens[1..<start]), rest: Array(tokens[(start + phrase.count)...]))
                }
            }
        }
        return nil
    }

    // MARK: - Utilidades

    func word(_ index: Int) -> String? {
        tokens.indices.contains(index) ? tokens[index].normalized : nil
    }

    private func text(from index: Int, length: Int) -> String {
        tokens[index..<(index + length)].map(\.original).joined(separator: " ")
    }
}
