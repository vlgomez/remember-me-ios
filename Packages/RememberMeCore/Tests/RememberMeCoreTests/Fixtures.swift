import Foundation
@testable import RememberMeCore

/// Datos fijos para que los tests no dependan del reloj ni de la zona horaria de la máquina.
enum Fixtures {
    static let madrid = TimeZone(identifier: "Europe/Madrid")!
    static let utc = TimeZone(identifier: "UTC")!
    static let fixedID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// Miércoles 7 de octubre de 2026, 09:00 en Madrid (horario de verano, UTC+2).
    static let wednesdayMorning = "2026-10-07T09:00:00+02:00"
    /// Viernes 9 de octubre de 2026, 09:00 en Madrid.
    static let fridayMorning = "2026-10-09T09:00:00+02:00"
    /// Sábado 10 de octubre de 2026, 10:00 en Madrid.
    static let saturdayMorning = "2026-10-10T10:00:00+02:00"

    static func instant(_ iso8601: String) -> Date {
        guard let date = ISO8601DateFormatter().date(from: iso8601) else {
            fatalError("Fecha ISO 8601 no válida en los tests: \(iso8601)")
        }
        return date
    }

    static func dates(now iso8601: String = wednesdayMorning, timeZone: TimeZone = madrid) -> DateContext {
        DateContext.spain(dateProvider: FixedDateProvider(instant(iso8601)), timeZone: timeZone)
    }

    static func parsing(now iso8601: String = wednesdayMorning) -> ParsingContext {
        ParsingContext(dates: dates(now: iso8601), identifiers: FixedIdentifierProvider(fixedID))
    }

    static func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        guard let value = CalendarDay(year: year, month: month, day: day) else {
            fatalError("Día no válido en los tests: \(year)-\(month)-\(day)")
        }
        return value
    }

    static func time(_ hour: Int, _ minute: Int = 0) -> TimeOfDay {
        guard let value = TimeOfDay(hour: hour, minute: minute) else {
            fatalError("Hora no válida en los tests: \(hour):\(minute)")
        }
        return value
    }

    static func at(_ year: Int, _ month: Int, _ dayNumber: Int, _ hour: Int, _ minute: Int = 0) -> LocalDateTime {
        LocalDateTime(day: day(year, month, dayNumber), time: time(hour, minute))
    }

    /// Intención mínima construida a mano, con todos los campos aportados por el usuario.
    static func intent(
        title: String = "Tarea de prueba",
        kind: TaskKind = .task,
        action: TaskAction = .createTask,
        deadline: Deadline? = nil,
        scheduledAt: TaskDate? = nil,
        timeZone: TimeZone? = nil,
        reminderPolicy: ReminderPolicy = .noReminder
    ) -> TaskIntent {
        TaskIntent(
            id: TaskIntentID(fixedID),
            action: .userProvided(action),
            title: .userProvided(title),
            kind: .userProvided(kind),
            deadline: deadline.map { TaskField.userProvided($0) },
            scheduledAt: scheduledAt.map { TaskField.userProvided($0) },
            timeZone: timeZone.map { TaskField.userProvided($0) },
            reminderPolicy: .userProvided(reminderPolicy)
        )
    }
}
