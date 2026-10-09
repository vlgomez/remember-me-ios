/// Fecha de una tarea: o un día completo, o un día con hora.
///
/// Un día completo no tiene hora y no se puede convertir en un instante. Para obtener
/// su intervalo (que puede durar 23 o 25 horas por el horario de verano) se usa
/// `DateContext.interval(for:)`.
public enum TaskDate: Sendable, Hashable, Codable, CustomStringConvertible {
    case allDay(CalendarDay)
    case timed(LocalDateTime)

    public var day: CalendarDay {
        switch self {
        case .allDay(let day):
            return day
        case .timed(let local):
            return local.day
        }
    }

    /// `nil` para un día completo: la hora no se inventa.
    public var time: TimeOfDay? {
        switch self {
        case .allDay:
            return nil
        case .timed(let local):
            return local.time
        }
    }

    public var localDateTime: LocalDateTime? {
        switch self {
        case .allDay:
            return nil
        case .timed(let local):
            return local
        }
    }

    public var isAllDay: Bool {
        if case .allDay = self { return true }
        return false
    }

    public var description: String {
        switch self {
        case .allDay(let day):
            return "\(day) (día completo)"
        case .timed(let local):
            return local.description
        }
    }
}

/// Fecha límite: el momento en que la tarea deja de tener sentido.
///
/// Es distinta de la fecha de ejecución (`TaskIntent.scheduledAt`), que es cuándo se piensa hacer.
public struct Deadline: Sendable, Hashable, Codable {
    public enum Boundary: String, Sendable, Hashable, Codable {
        /// "antes del 20": el propio día 20 ya es tarde.
        case exclusive
        /// "para el 20", "hasta el 20": el día 20 todavía vale.
        case inclusive
    }

    public let date: TaskDate
    public let boundary: Boundary

    public init(date: TaskDate, boundary: Boundary) {
        self.date = date
        self.boundary = boundary
    }

    /// Último día en que la tarea puede completarse a tiempo.
    public var lastValidDay: CalendarDay {
        switch (boundary, date) {
        case (.inclusive, _):
            return date.day
        case (.exclusive, .allDay(let day)):
            return day.adding(days: -1)
        case (.exclusive, .timed(let local)):
            // "Antes del viernes a las 00:00" deja como último día el jueves.
            let isMidnight = local.time.hour == 0 && local.time.minute == 0
            return isMidnight ? local.day.adding(days: -1) : local.day
        }
    }
}
