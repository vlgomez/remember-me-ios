/// Antelación de un aviso respecto a una fecha límite.
public enum LeadTime: Sendable, Hashable, Codable {
    case minutes(Int)
    case hours(Int)
    /// Días de calendario: se conserva la hora de reloj aunque haya cambio de horario.
    case days(Int)

    public var amount: Int {
        switch self {
        case .minutes(let value), .hours(let value), .days(let value):
            return value
        }
    }
}

/// Política de aviso de una tarea.
public enum ReminderPolicy: Sendable, Hashable, Codable {
    /// Sin aviso programado.
    case noReminder
    /// Aviso en un momento concreto del reloj local.
    case at(LocalDateTime)
    /// Aviso con antelación respecto a la fecha límite.
    case beforeDeadline(LeadTime)

    /// `true` si la política fija una fecha y hora concretas (y, por tanto, necesita zona horaria).
    public var isAbsolute: Bool {
        if case .at = self { return true }
        return false
    }
}
