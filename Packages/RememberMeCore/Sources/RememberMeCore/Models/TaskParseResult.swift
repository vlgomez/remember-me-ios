/// Motivo por el que hay que preguntar al usuario.
public enum ClarificationReason: String, Sendable, Hashable, Codable {
    /// No se escribió nada.
    case emptyInput
    /// Solo había fechas u horas; falta saber qué hay que hacer.
    case missingTitle
    /// La expresión de día admite varias interpretaciones ("el próximo viernes" dicho un miércoles).
    case ambiguousDate
    /// La fecha no existe ("31 de febrero").
    case invalidDate
    /// La hora admite varias interpretaciones ("a las 5" sin "de la mañana/tarde").
    case ambiguousTime
    /// La hora no es válida ("a las 27").
    case invalidTime
    /// Se indicó una franja ("esta tarde") pero no una hora.
    case vagueTimeOfDay
    /// Hay hora pero no día, y hoy ya ha pasado.
    case missingDate
    /// Un compromiso (cita, reunión) sin hora.
    case missingTime
    /// El parser no sabe interpretar la frase con seguridad.
    case unsupportedExpression
}

/// Pregunta que hay que hacer al usuario antes de poder guardar.
public struct ClarificationRequest: Sendable, Hashable, Codable {
    public let field: TaskFieldKey
    public let reason: ClarificationReason
    /// Opciones concretas entre las que elegir, si las hay.
    public let options: [TaskDate]
    /// Día ya conocido cuando lo que falta es la hora.
    public let knownDay: CalendarDay?
    /// Fragmento del texto original que provocó la pregunta.
    public let fragment: String?

    public init(
        field: TaskFieldKey,
        reason: ClarificationReason,
        options: [TaskDate] = [],
        knownDay: CalendarDay? = nil,
        fragment: String? = nil
    ) {
        self.field = field
        self.reason = reason
        self.options = options
        self.knownDay = knownDay
        self.fragment = fragment
    }
}

/// Resultado de interpretar una frase.
public struct TaskParseResult: Sendable, Hashable {
    /// Intención interpretada. Es `nil` cuando no hay nada que interpretar o la frase no está soportada.
    public let intent: TaskIntent?
    /// Preguntas pendientes para el usuario.
    public let clarifications: [ClarificationRequest]
    /// Mensajes de validación.
    public let messages: [ValidationMessage]

    public init(
        intent: TaskIntent?,
        clarifications: [ClarificationRequest] = [],
        messages: [ValidationMessage] = []
    ) {
        self.intent = intent
        self.clarifications = clarifications
        self.messages = messages
    }

    public var needsClarification: Bool {
        !clarifications.isEmpty
    }
}
