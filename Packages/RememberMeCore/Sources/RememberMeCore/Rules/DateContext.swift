import Foundation

/// Resultado de convertir una fecha y hora locales en un instante.
public enum LocalTimeResolution: Sendable, Hashable {
    /// La hora existe y es única.
    case exact(Date)
    /// La hora no existe ese día (salto adelante del horario de verano, p. ej. 02:30 del último domingo de marzo en Madrid).
    case nonexistent
    /// La hora ocurre dos veces ese día (vuelta atrás del horario de verano, p. ej. 02:30 del último domingo de octubre en Madrid).
    case repeated(earlier: Date, later: Date)
}

/// Reloj, calendario y zona horaria con los que se resuelven todas las fechas.
///
/// Todo lo que dependa de "ahora", del calendario o de la zona horaria pasa por aquí, para
/// que los tests sean deterministas.
public struct DateContext: Sendable {
    public enum ConfigurationError: Error, Sendable, Hashable {
        /// `CalendarDay` modela días gregorianos; otro calendario daría resultados incoherentes.
        case calendarMustBeGregorian
    }

    public let dateProvider: any DateProvider
    /// Calendario gregoriano configurado con `timeZone`.
    public let calendar: Calendar

    public var timeZone: TimeZone {
        calendar.timeZone
    }

    /// - Throws: `ConfigurationError.calendarMustBeGregorian` si el calendario no es gregoriano.
    public init(dateProvider: any DateProvider, calendar: Calendar, timeZone: TimeZone) throws {
        guard calendar.identifier == .gregorian else {
            throw ConfigurationError.calendarMustBeGregorian
        }
        self.init(validatedProvider: dateProvider, calendar: calendar, timeZone: timeZone)
    }

    private init(validatedProvider: any DateProvider, calendar: Calendar, timeZone: TimeZone) {
        var configured = calendar
        configured.timeZone = timeZone
        self.dateProvider = validatedProvider
        self.calendar = configured
    }

    /// Calendario gregoriano con configuración regional española y semana que empieza en lunes.
    public static func spain(
        dateProvider: any DateProvider = SystemDateProvider(),
        timeZone: TimeZone = .current
    ) -> DateContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "es_ES")
        calendar.firstWeekday = 2
        return DateContext(validatedProvider: dateProvider, calendar: calendar, timeZone: timeZone)
    }

    /// Mismo reloj y calendario en otra zona horaria.
    public func withTimeZone(_ zone: TimeZone) -> DateContext {
        DateContext(validatedProvider: dateProvider, calendar: calendar, timeZone: zone)
    }

    public func now() -> Date {
        dateProvider.now()
    }

    /// Día actual en la zona horaria del contexto.
    public func today() -> CalendarDay {
        day(containing: now())
    }

    public func day(containing date: Date) -> CalendarDay {
        localDateTime(containing: date).day
    }

    /// Fecha y hora del reloj local (redondeada al minuto) que corresponden a un instante.
    public func localDateTime(containing date: Date) -> LocalDateTime {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let year = components.year,
              let month = components.month,
              let dayNumber = components.day,
              let hour = components.hour,
              let minute = components.minute,
              let day = CalendarDay(year: year, month: month, day: dayNumber),
              let time = TimeOfDay(hour: hour, minute: minute) else {
            preconditionFailure("Calendar devolvió componentes incompletos para \(date).")
        }
        return LocalDateTime(day: day, time: time)
    }

    /// Convierte una fecha y hora locales en un instante, detectando horas inexistentes o repetidas.
    public func resolve(_ local: LocalDateTime) -> LocalTimeResolution {
        var components = DateComponents()
        components.year = local.day.year
        components.month = local.day.month
        components.day = local.day.day
        components.hour = local.time.hour
        components.minute = local.time.minute
        components.second = 0

        guard let candidate = calendar.date(from: components),
              localDateTime(containing: candidate) == local else {
            return .nonexistent
        }

        let shift = utcOffsetChange(around: candidate)
        if shift > 0 {
            let earlier = candidate.addingTimeInterval(-shift)
            if localDateTime(containing: earlier) == local {
                return .repeated(earlier: earlier, later: candidate)
            }
            let later = candidate.addingTimeInterval(shift)
            if localDateTime(containing: later) == local {
                return .repeated(earlier: candidate, later: later)
            }
        }
        return .exact(candidate)
    }

    /// Instante de una fecha y hora locales. Si la hora se repite, devuelve la primera aparición;
    /// si no existe, devuelve `nil`.
    public func instant(for local: LocalDateTime) -> Date? {
        switch resolve(local) {
        case .exact(let date):
            return date
        case .repeated(let earlier, _):
            return earlier
        case .nonexistent:
            return nil
        }
    }

    /// Intervalo de un día completo, de su inicio al inicio del día siguiente.
    /// Dura 23 o 25 horas los días de cambio de horario.
    public func interval(for day: CalendarDay) -> DateInterval {
        DateInterval(start: startOfDay(day), end: startOfDay(day.adding(days: 1)))
    }

    /// Misma hora de reloj `days` días de calendario después (o antes, si es negativo).
    public func adding(days: Int, to local: LocalDateTime) -> LocalDateTime {
        LocalDateTime(day: local.day.adding(days: days), time: local.time)
    }

    private func startOfDay(_ day: CalendarDay) -> Date {
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = 12
        guard let noon = calendar.date(from: components) else {
            preconditionFailure("Calendar no pudo construir el mediodía de \(day).")
        }
        return calendar.startOfDay(for: noon)
    }

    /// Diferencia absoluta del desfase UTC en torno a un instante (3600 s los días de cambio de horario en Madrid).
    private func utcOffsetChange(around date: Date) -> TimeInterval {
        let before = timeZone.secondsFromGMT(for: date.addingTimeInterval(-12 * 3_600))
        let after = timeZone.secondsFromGMT(for: date.addingTimeInterval(12 * 3_600))
        return TimeInterval(abs(after - before))
    }
}
