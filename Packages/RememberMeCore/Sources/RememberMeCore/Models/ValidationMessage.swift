public enum ValidationSeverity: String, Sendable, Hashable, Codable {
    case info
    case warning
    case error
}

public enum ValidationCode: String, Sendable, Hashable, Codable {
    case emptyTitle
    case actionKindMismatch
    case calendarEventRequiresTime
    case missingTimeZone
    case nonexistentLocalTime
    case repeatedLocalTime
    case dateInPast
    case deadlineInPast
    case scheduledAfterDeadline
    case reminderRequiresDeadline
    case leadTimeMustBePositive
    case leadTimeNeedsTimedDeadline
    case reminderNeedsTime
    case reminderInPast
    case pendingConfirmation

    /// Texto por defecto en español. La interfaz podrá localizarlo más adelante.
    public var spanishDescription: String {
        switch self {
        case .emptyTitle:
            return "Falta indicar qué hay que hacer."
        case .actionKindMismatch:
            return "El tipo de tarea no encaja con dónde se va a guardar."
        case .calendarEventRequiresTime:
            return "Un evento de calendario necesita fecha y hora."
        case .missingTimeZone:
            return "Falta la zona horaria de una fecha con hora."
        case .nonexistentLocalTime:
            return "Esa hora no existe ese día por el cambio de horario."
        case .repeatedLocalTime:
            return "Esa hora se repite ese día por el cambio de horario."
        case .dateInPast:
            return "La fecha ya ha pasado."
        case .deadlineInPast:
            return "La fecha límite ya ha pasado."
        case .scheduledAfterDeadline:
            return "La fecha de ejecución es posterior a la fecha límite."
        case .reminderRequiresDeadline:
            return "El aviso depende de una fecha límite que no está indicada."
        case .leadTimeMustBePositive:
            return "La antelación del aviso debe ser mayor que cero."
        case .leadTimeNeedsTimedDeadline:
            return "Para avisar con horas o minutos de antelación, la fecha límite necesita una hora."
        case .reminderNeedsTime:
            return "Ya se sabe el día del aviso; falta elegir la hora."
        case .reminderInPast:
            return "El momento del aviso ya ha pasado."
        case .pendingConfirmation:
            return "Este dato se ha deducido y hay que confirmarlo."
        }
    }
}

public struct ValidationMessage: Sendable, Hashable, Codable {
    public let code: ValidationCode
    public let severity: ValidationSeverity
    public let field: TaskFieldKey?

    public init(code: ValidationCode, severity: ValidationSeverity, field: TaskFieldKey?) {
        self.code = code
        self.severity = severity
        self.field = field
    }

    public static func error(_ code: ValidationCode, field: TaskFieldKey?) -> ValidationMessage {
        ValidationMessage(code: code, severity: .error, field: field)
    }

    public static func warning(_ code: ValidationCode, field: TaskFieldKey?) -> ValidationMessage {
        ValidationMessage(code: code, severity: .warning, field: field)
    }

    public static func info(_ code: ValidationCode, field: TaskFieldKey?) -> ValidationMessage {
        ValidationMessage(code: code, severity: .info, field: field)
    }

    public var text: String {
        code.spanishDescription
    }
}
