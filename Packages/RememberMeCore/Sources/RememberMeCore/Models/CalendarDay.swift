import Foundation

/// Día de la semana con numeración ISO 8601 (lunes = 1).
public enum Weekday: Int, Sendable, Hashable, Codable, CaseIterable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday
}

/// Día del calendario gregoriano, sin hora ni zona horaria.
///
/// Representa "el 20 de noviembre" tal cual: no es un instante y no equivale a la
/// medianoche de ningún sitio. La aritmética de días se hace sobre días de calendario
/// (algoritmos de días civiles de Howard Hinnant), nunca sumando bloques de 24 horas.
public struct CalendarDay: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Devuelve `nil` si la fecha no existe en el calendario gregoriano (31 de abril, 29 de febrero de 2026...).
    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month),
              day >= 1,
              day <= CalendarDay.numberOfDays(inMonth: month, year: year) else {
            return nil
        }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Construye el día a partir del número de días transcurridos desde el 1 de enero de 1970.
    init(daysSinceEpoch: Int) {
        let z = daysSinceEpoch + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let resultDay = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        let resultMonth = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        self.year = yearOfEra + era * 400 + (resultMonth <= 2 ? 1 : 0)
        self.month = resultMonth
        self.day = resultDay
    }

    /// Número de días transcurridos desde el 1 de enero de 1970 (negativo antes de esa fecha).
    var daysSinceEpoch: Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let shiftedMonth = month > 2 ? month - 3 : month + 9
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    public static func numberOfDays(inMonth month: Int, year: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12:
            return 31
        case 4, 6, 9, 11:
            return 30
        case 2:
            return isLeapYear(year) ? 29 : 28
        default:
            return 0
        }
    }

    /// Suma (o resta, si es negativo) días de calendario.
    public func adding(days: Int) -> CalendarDay {
        CalendarDay(daysSinceEpoch: daysSinceEpoch + days)
    }

    /// Días de calendario hasta `other` (negativo si `other` es anterior).
    public func days(until other: CalendarDay) -> Int {
        other.daysSinceEpoch - daysSinceEpoch
    }

    public var weekday: Weekday {
        let z = daysSinceEpoch
        // 0 = domingo ... 6 = sábado
        let sundayBased = z >= -4 ? (z + 4) % 7 : (z + 5) % 7 + 6
        guard let weekday = Weekday(rawValue: sundayBased == 0 ? 7 : sundayBased) else {
            preconditionFailure("Día de la semana fuera de rango: \(sundayBased)")
        }
        return weekday
    }

    /// Lunes de la semana (ISO 8601) que contiene este día.
    public var startOfISOWeek: CalendarDay {
        adding(days: -(weekday.rawValue - 1))
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    private enum CodingKeys: String, CodingKey {
        case year, month, day
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let year = try container.decode(Int.self, forKey: .year)
        let month = try container.decode(Int.self, forKey: .month)
        let day = try container.decode(Int.self, forKey: .day)
        guard let value = CalendarDay(year: year, month: month, day: day) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "La fecha \(year)-\(month)-\(day) no existe."
                )
            )
        }
        self = value
    }
}
