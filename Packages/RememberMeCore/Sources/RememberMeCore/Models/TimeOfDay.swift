import Foundation

/// Hora del reloj local (hora y minuto), sin fecha ni zona horaria.
public struct TimeOfDay: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let hour: Int
    public let minute: Int

    /// Devuelve `nil` si la hora no está en 0...23 o el minuto en 0...59.
    public init?(hour: Int, minute: Int = 0) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }

    public var description: String {
        String(format: "%02d:%02d", hour, minute)
    }

    private enum CodingKeys: String, CodingKey {
        case hour, minute
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hour = try container.decode(Int.self, forKey: .hour)
        let minute = try container.decode(Int.self, forKey: .minute)
        guard let value = TimeOfDay(hour: hour, minute: minute) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "La hora \(hour):\(minute) no es válida."
                )
            )
        }
        self = value
    }
}

/// Fecha y hora del reloj local, sin zona horaria. Se convierte en instante con `DateContext`.
public struct LocalDateTime: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let day: CalendarDay
    public let time: TimeOfDay

    public init(day: CalendarDay, time: TimeOfDay) {
        self.day = day
        self.time = time
    }

    public static func < (lhs: LocalDateTime, rhs: LocalDateTime) -> Bool {
        (lhs.day, lhs.time) < (rhs.day, rhs.time)
    }

    public var description: String {
        "\(day) \(time)"
    }
}
