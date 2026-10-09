import Foundation

/// Identificador estable de una intención. Se genera una vez (con un `IdentifierProvider`
/// inyectable) y se conserva en todas las correcciones posteriores.
public struct TaskIntentID: Sendable, Hashable, Codable, CustomStringConvertible {
    public let uuid: UUID

    public init(_ uuid: UUID) {
        self.uuid = uuid
    }

    public var description: String { uuid.uuidString }
}

/// Nombres de los campos de `TaskIntent`, para aclaraciones, mensajes y confirmaciones.
public enum TaskFieldKey: String, Sendable, Hashable, Codable, CaseIterable {
    case action
    case title
    case notes
    case kind
    case deadline
    case scheduledAt
    case timeZone
    case location
    case reminderPolicy
}

/// Resultado de la última validación de una intención.
public enum ValidationState: String, Sendable, Hashable, Codable {
    /// La intención es nueva o ha cambiado desde la última validación.
    case notValidated
    /// Falta información que hay que preguntar al usuario.
    case needsClarification
    /// Hay errores que impiden guardarla.
    case invalid
    /// Es coherente, pero contiene datos deducidos que el usuario aún no ha visto y aceptado.
    case needsConfirmation
    /// Se puede guardar.
    case readyToSave
}

/// Intención interpretada a partir de lo que dijo o escribió el usuario.
///
/// Es inmutable desde fuera del paquete: las correcciones crean una copia (`updating...`)
/// que marca el campo como aportado por el usuario y devuelve el estado a `.notValidated`.
/// Solo `TaskIntentValidator` asigna un estado de validación.
public struct TaskIntent: Sendable, Hashable, Codable, Identifiable {
    public let id: TaskIntentID
    public private(set) var action: TaskField<TaskAction>
    public private(set) var title: TaskField<String>
    public private(set) var notes: TaskField<String>?
    public private(set) var kind: TaskField<TaskKind>
    /// Fecha límite: cuándo deja de tener sentido la tarea.
    public private(set) var deadline: TaskField<Deadline>?
    /// Fecha (y hora, si la hay) de ejecución: cuándo se piensa hacer.
    public private(set) var scheduledAt: TaskField<TaskDate>?
    /// Zona horaria de las fechas con hora. Es `nil` si no hay ninguna fecha con hora.
    public private(set) var timeZone: TaskField<TimeZone>?
    public private(set) var location: TaskField<TaskLocation>?
    public private(set) var reminderPolicy: TaskField<ReminderPolicy>
    public private(set) var validationState: ValidationState

    public init(
        id: TaskIntentID,
        action: TaskField<TaskAction>,
        title: TaskField<String>,
        notes: TaskField<String>? = nil,
        kind: TaskField<TaskKind>,
        deadline: TaskField<Deadline>? = nil,
        scheduledAt: TaskField<TaskDate>? = nil,
        timeZone: TaskField<TimeZone>? = nil,
        location: TaskField<TaskLocation>? = nil,
        reminderPolicy: TaskField<ReminderPolicy> = .ruleDefault(.noReminder)
    ) {
        self.id = id
        self.action = action
        self.title = title
        self.notes = notes
        self.kind = kind
        self.deadline = deadline
        self.scheduledAt = scheduledAt
        self.timeZone = timeZone
        self.location = location
        self.reminderPolicy = reminderPolicy
        self.validationState = .notValidated
    }

    public var destination: TaskDestination {
        action.value.destination
    }

    /// Campos con datos deducidos que todavía no se han confirmado en una vista previa.
    public var fieldsPendingConfirmation: Set<TaskFieldKey> {
        var keys = Set<TaskFieldKey>()
        if action.needsConfirmation { keys.insert(.action) }
        if title.needsConfirmation { keys.insert(.title) }
        if notes?.needsConfirmation == true { keys.insert(.notes) }
        if kind.needsConfirmation { keys.insert(.kind) }
        if deadline?.needsConfirmation == true { keys.insert(.deadline) }
        if scheduledAt?.needsConfirmation == true { keys.insert(.scheduledAt) }
        if timeZone?.needsConfirmation == true { keys.insert(.timeZone) }
        if location?.needsConfirmation == true { keys.insert(.location) }
        if reminderPolicy.needsConfirmation { keys.insert(.reminderPolicy) }
        return keys
    }

    /// `true` si alguna fecha tiene hora o el aviso es absoluto; en ese caso hace falta zona horaria.
    public var requiresTimeZone: Bool {
        scheduledAt?.value.isAllDay == false
            || deadline?.value.date.isAllDay == false
            || reminderPolicy.value.isAbsolute
    }

    // MARK: - Correcciones del usuario
    //
    // Estos métodos son para cambios que hace el usuario en la vista previa. Marcan el
    // campo como `userProvided` y obligan a validar de nuevo.

    public func updatingTitle(_ newTitle: String) -> TaskIntent {
        var copy = self
        copy.title = .userProvided(newTitle)
        copy.validationState = .notValidated
        return copy
    }

    public func updatingNotes(_ newNotes: String?) -> TaskIntent {
        var copy = self
        copy.notes = newNotes.map { TaskField.userProvided($0) }
        copy.validationState = .notValidated
        return copy
    }

    /// Cambia el tipo y ajusta la acción en consecuencia (salvo que la acción sea modificar un evento existente).
    public func updatingKind(_ newKind: TaskKind) -> TaskIntent {
        var copy = self
        copy.kind = .userProvided(newKind)
        if case .addReminderToExistingEvent = action.value {
            // Se mantiene la acción: el usuario está corrigiendo el tipo, no el destino.
        } else {
            copy.action = .ruleDefault(newKind == .appointment ? .createCalendarEvent : .createTask)
        }
        copy.validationState = .notValidated
        return copy
    }

    public func updatingScheduledAt(_ newDate: TaskDate?) -> TaskIntent {
        var copy = self
        copy.scheduledAt = newDate.map { TaskField.userProvided($0) }
        copy.validationState = .notValidated
        return copy
    }

    public func updatingDeadline(_ newDeadline: Deadline?) -> TaskIntent {
        var copy = self
        copy.deadline = newDeadline.map { TaskField.userProvided($0) }
        copy.validationState = .notValidated
        return copy
    }

    public func updatingLocation(_ newLocation: TaskLocation?) -> TaskIntent {
        var copy = self
        copy.location = newLocation.map { TaskField.userProvided($0) }
        copy.validationState = .notValidated
        return copy
    }

    public func updatingReminderPolicy(_ newPolicy: ReminderPolicy) -> TaskIntent {
        var copy = self
        copy.reminderPolicy = .userProvided(newPolicy)
        copy.validationState = .notValidated
        return copy
    }

    // MARK: - Uso interno del paquete

    func settingValidationState(_ state: ValidationState) -> TaskIntent {
        var copy = self
        copy.validationState = state
        return copy
    }

    /// Añade la zona horaria del contexto si hay fechas con hora y no se indicó ninguna.
    /// No es un dato inventado: es la zona horaria en la que el usuario está usando la app.
    func fillingMissingTimeZone(_ zone: TimeZone) -> TaskIntent {
        guard timeZone == nil, requiresTimeZone else { return self }
        var copy = self
        copy.timeZone = .ruleDefault(zone)
        copy.validationState = .notValidated
        return copy
    }

    func confirmingFields(_ keys: Set<TaskFieldKey>) -> TaskIntent {
        var copy = self
        for key in keys {
            switch key {
            case .action:
                copy.action = action.confirmed()
            case .title:
                copy.title = title.confirmed()
            case .notes:
                copy.notes = notes?.confirmed()
            case .kind:
                copy.kind = kind.confirmed()
            case .deadline:
                copy.deadline = deadline?.confirmed()
            case .scheduledAt:
                copy.scheduledAt = scheduledAt?.confirmed()
            case .timeZone:
                copy.timeZone = timeZone?.confirmed()
            case .location:
                copy.location = location?.confirmed()
            case .reminderPolicy:
                copy.reminderPolicy = reminderPolicy.confirmed()
            }
        }
        copy.validationState = .notValidated
        return copy
    }
}
