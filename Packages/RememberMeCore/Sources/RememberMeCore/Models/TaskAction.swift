/// Destino en el que acaba guardándose una tarea.
public enum TaskDestination: String, Sendable, Hashable, Codable, CaseIterable {
    case appleReminders
    case appleCalendar
}

/// Referencia a un evento que ya existe en el calendario, tal como la describió el usuario.
///
/// No contiene un identificador de EventKit. Localizar el evento (y preguntar si hay varios
/// o ninguno) queda para una fase posterior: en la Fase B, guardar esta acción devuelve
/// `SaveError.unsupportedAction` y no modifica ningún evento.
public struct ExistingEventReference: Sendable, Hashable, Codable {
    /// Descripción literal del usuario, por ejemplo "mi cita".
    public let userDescription: String
    /// Día en que el usuario sitúa el evento, si lo indicó.
    public let day: CalendarDay?

    public init(userDescription: String, day: CalendarDay?) {
        self.userDescription = userDescription
        self.day = day
    }
}

/// Qué hay que hacer con la intención interpretada.
public enum TaskAction: Sendable, Hashable, Codable {
    /// Crear un recordatorio (tarea o compra).
    case createTask
    /// Crear un evento de calendario (compromiso con hora).
    case createCalendarEvent
    /// Añadir un aviso a un evento que ya existe.
    case addReminderToExistingEvent(ExistingEventReference)

    public var destination: TaskDestination {
        switch self {
        case .createTask:
            return .appleReminders
        case .createCalendarEvent, .addReminderToExistingEvent:
            return .appleCalendar
        }
    }
}
