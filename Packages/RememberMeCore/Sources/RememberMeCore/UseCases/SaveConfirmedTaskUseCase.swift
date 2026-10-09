import Foundation

/// Opciones que el usuario elige al guardar, además de la intención.
public struct SaveOptions: Sendable, Hashable {
    /// Duración de un evento de calendario. La intención no la contiene y no se inventa:
    /// es obligatoria para crear eventos (la Fase C la pedirá en la vista previa).
    public var eventDuration: TimeInterval?
    /// Calendario de destino. `nil` usa el calendario por defecto.
    public var calendarIdentifier: String?
    /// Lista de Reminders de destino. `nil` usa la lista por defecto.
    public var reminderListIdentifier: String?
    /// Si la intención ya se guardó y el elemento se borró después desde Calendar o Reminders,
    /// solo se vuelve a crear si el usuario lo pide explícitamente.
    public var recreateIfMissing: Bool
    /// Si un intento anterior de guardar esta intención no llegó a confirmarse
    /// (`SaveError.unconfirmedPreviousAttempt`), solo se vuelve a crear si el usuario lo pide
    /// explícitamente, sabiendo que puede quedar un duplicado.
    public var createDespiteUnconfirmedAttempt: Bool

    public init(
        eventDuration: TimeInterval? = nil,
        calendarIdentifier: String? = nil,
        reminderListIdentifier: String? = nil,
        recreateIfMissing: Bool = false,
        createDespiteUnconfirmedAttempt: Bool = false
    ) {
        self.eventDuration = eventDuration
        self.calendarIdentifier = calendarIdentifier
        self.reminderListIdentifier = reminderListIdentifier
        self.recreateIfMissing = recreateIfMissing
        self.createDespiteUnconfirmedAttempt = createDespiteUnconfirmedAttempt
    }
}

/// Resultado de guardar una intención.
public enum SaveOutcome: Sendable, Hashable {
    /// Se creó el elemento.
    case saved(SavedItemRecord)
    /// Esta intención ya se había guardado y el elemento sigue existiendo: no se crea otro.
    case alreadySaved(SavedItemRecord)
    /// Esta intención ya se guardó, pero el elemento ya no existe. No se recrea sin `recreateIfMissing`.
    case previouslySavedButMissing(SavedItemRecord)
    /// Un guardado anterior de esta sesión creó el elemento, pero no pudo registrarlo
    /// (`SaveError.createdButNotRegistered`). Ahora se ha registrado sin crear nada nuevo.
    case registrationRecovered(SavedItemRecord)

    /// Registro asociado al resultado, sea nuevo o anterior.
    public var record: SavedItemRecord {
        switch self {
        case .saved(let record),
             .alreadySaved(let record),
             .previouslySavedButMissing(let record),
             .registrationRecovered(let record):
            return record
        }
    }
}

public enum SaveError: Error, Sendable, Hashable {
    /// La intención no está lista: tiene aclaraciones pendientes, errores o datos deducidos sin confirmar.
    case notReadyToSave(ValidationState)
    /// Añadir avisos a eventos existentes llegará en una fase posterior.
    case unsupportedAction
    /// Un evento necesita fecha, hora y zona horaria.
    case missingEventTime
    case missingEventDuration
    case invalidEventDuration
    /// La hora local no existe ese día por el cambio de horario.
    case unresolvableDate
    /// No hay acceso total al destino.
    case permission(EventStoreEntity, EventStorePermission)
    case store(EventStoreError)
    /// No se pudo leer el registro o anotar el intento antes de crear. No se ha creado nada.
    case registry(String)
    /// EventKit creó el elemento, pero su referencia no se pudo guardar en el registro.
    /// El elemento existe; un reintento en esta sesión solo completa el registro, sin crear otro.
    case createdButNotRegistered(SavedItemRecord)
    /// Hay un intento anterior de guardar esta intención cuyo resultado no se pudo confirmar
    /// (por ejemplo, la app se cerró o el registro falló justo después de crear). Puede que el
    /// elemento ya exista. No se crea nada sin `createDespiteUnconfirmedAttempt`.
    case unconfirmedPreviousAttempt(PendingCreation)
}

/// Convierte una intención validada en borradores de EventKit, sin inventar datos.
public struct EventStoreDraftBuilder: Sendable {
    public let dates: DateContext

    public init(dates: DateContext) {
        self.dates = dates
    }

    /// Recordatorio: vence en la fecha de ejecución; si no la hay, en el último día válido de la fecha límite.
    public func reminderDraft(for intent: TaskIntent, listIdentifier: String?) throws -> ReminderDraft {
        let due: TaskDate?
        var notes = intent.notes?.value
        if let scheduled = intent.scheduledAt?.value {
            due = scheduled
            if let deadline = intent.deadline?.value {
                // La fecha límite no cabe en el recordatorio si ya hay fecha de ejecución: se conserva en las notas.
                notes = [notes, Self.deadlineNote(deadline)].compactMap { $0 }.joined(separator: "\n")
            }
        } else if let deadline = intent.deadline?.value {
            switch deadline.date {
            case .allDay:
                due = .allDay(deadline.lastValidDay)
            case .timed:
                due = deadline.date
            }
        } else {
            due = nil
        }

        let zone = due?.isAllDay == false ? (intent.timeZone?.value ?? dates.timeZone) : nil
        return ReminderDraft(
            title: intent.title.value.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes,
            location: intent.location?.value.text,
            due: due,
            timeZone: zone,
            alarm: try alarmInstant(for: intent).instant,
            listIdentifier: listIdentifier
        )
    }

    /// Evento: empieza a la hora confirmada y dura lo que indique el usuario.
    public func eventDraft(for intent: TaskIntent, duration: TimeInterval?, calendarIdentifier: String?) throws -> CalendarEventDraft {
        guard case .timed(let local)? = intent.scheduledAt?.value, let zone = intent.timeZone?.value else {
            throw SaveError.missingEventTime
        }
        guard let duration else { throw SaveError.missingEventDuration }
        guard duration > 0, duration.isFinite else { throw SaveError.invalidEventDuration }

        let context = dates.withTimeZone(zone)
        guard let start = context.instant(for: local) else { throw SaveError.unresolvableDate }

        return CalendarEventDraft(
            title: intent.title.value.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: intent.notes?.value,
            location: intent.location?.value.text,
            start: start,
            end: start.addingTimeInterval(duration),
            timeZone: zone,
            alarm: try alarmInstant(for: intent).instant,
            calendarIdentifier: calendarIdentifier
        )
    }

    /// Instante de la alarma según la política de aviso confirmada.
    ///
    /// - Aviso a una hora concreta: alarma en ese instante (si todavía no ha pasado).
    /// - Aviso N días antes de una fecha sin hora: se conoce el día pero no la hora, así que no
    ///   se crea alarma y se devuelve ese día como pendiente.
    public func alarmInstant(for intent: TaskIntent) throws -> (instant: Date?, pendingDay: CalendarDay?) {
        let context = dates.withTimeZone(intent.timeZone?.value ?? dates.timeZone)
        let calculator = ReminderScheduleCalculator(dates: context)
        switch calculator.trigger(for: intent.reminderPolicy.value, deadline: intent.deadline?.value) {
        case .success(.noReminder):
            return (nil, nil)
        case .success(.dayWithoutTime(let day)):
            return (nil, day)
        case .success(.at(let local)):
            guard let instant = context.instant(for: local) else { throw SaveError.unresolvableDate }
            return (instant > context.now() ? instant : nil, nil)
        case .failure:
            throw SaveError.notReadyToSave(.invalid)
        }
    }

    static func deadlineNote(_ deadline: Deadline) -> String {
        let day = deadline.date.day
        var text = String(format: "%02d/%02d/%04d", day.day, day.month, day.year)
        if let time = deadline.date.time {
            text += " a las \(time)"
        }
        switch deadline.boundary {
        case .exclusive:
            return "Fecha límite: antes del \(text)"
        case .inclusive:
            return "Fecha límite: \(text)"
        }
    }
}

/// Guarda en Calendar o Reminders una intención ya confirmada.
///
/// Garantías:
/// - Solo guarda intenciones en estado `.readyToSave` que siguen siéndolo al revalidarlas ahora.
/// - Comprueba que hay datos suficientes (por ejemplo, la duración de un evento) antes de pedir permiso.
/// - Pide permiso únicamente si el usuario aún no ha decidido, porque se llama al pulsar "Guardar".
/// - No crea duplicados: si la intención ya se guardó, devuelve el registro existente.
/// - No modifica ni borra elementos existentes, y no recrea un elemento borrado sin confirmación.
///
/// ## Fallos entre EventKit y el registro
///
/// Crear en EventKit y escribir en el registro local no son una transacción atómica. Para que un
/// fallo entre las dos operaciones no acabe en un duplicado silencioso:
///
/// 1. Antes de crear se anota el intento en el registro (`markPending`). Si esa escritura falla,
///    no se llama a EventKit (`SaveError.registry`).
/// 2. Si EventKit lanza un error, se retira la marca: se da por hecho que no creó nada.
/// 3. Si EventKit crea el elemento pero la escritura final falla, se lanza
///    `SaveError.createdButNotRegistered` con la referencia, que además se guarda en memoria.
///    Un reintento en la misma sesión solo vuelve a escribir el registro
///    (`SaveOutcome.registrationRecovered`), sin llamar a EventKit.
/// 4. Si no hay referencia en memoria (la app se reinició) pero sí una marca pendiente, no se crea
///    nada: se lanza `SaveError.unconfirmedPreviousAttempt` y decide el usuario
///    (`SaveOptions.createDespiteUnconfirmedAttempt`).
public struct SaveConfirmedTaskUseCase: Sendable {
    private let access: any EventStoreAccessProviding
    private let calendar: any CalendarEventStoring
    private let reminders: any ReminderStoring
    private let presence: any StoredItemChecking
    private let registry: any SavedItemRegistry
    private let dates: DateContext
    /// Elementos creados en esta sesión cuyo registro falló. Se comparte entre copias del caso de uso.
    private let unregistered = UnregisteredCreations()

    public init(
        access: any EventStoreAccessProviding,
        calendar: any CalendarEventStoring,
        reminders: any ReminderStoring,
        presence: any StoredItemChecking,
        registry: any SavedItemRegistry,
        dates: DateContext
    ) {
        self.access = access
        self.calendar = calendar
        self.reminders = reminders
        self.presence = presence
        self.registry = registry
        self.dates = dates
    }

    public func save(_ intent: TaskIntent, options: SaveOptions = SaveOptions()) async throws -> SaveOutcome {
        // 1. Solo intenciones confirmadas y sin aclaraciones pendientes.
        guard intent.validationState == .readyToSave else {
            throw SaveError.notReadyToSave(intent.validationState)
        }
        let revalidated = TaskIntentValidator(dates: dates).validate(intent)
        guard let current = revalidated.intent, current.validationState == .readyToSave else {
            throw SaveError.notReadyToSave(revalidated.intent?.validationState ?? .invalid)
        }

        // 2. Destino y borrador. Se preparan antes de pedir permiso: no tiene sentido mostrar el
        //    diálogo del sistema si faltan datos para guardar (por ejemplo, la duración de un evento).
        let builder = EventStoreDraftBuilder(dates: dates)
        let alarm = try builder.alarmInstant(for: current)
        let entity: EventStoreEntity
        let draft: PreparedDraft
        switch current.action.value {
        case .createTask:
            entity = .reminders
            draft = try .reminder(builder.reminderDraft(for: current, listIdentifier: options.reminderListIdentifier))
        case .createCalendarEvent:
            entity = .events
            draft = try .event(builder.eventDraft(
                for: current,
                duration: options.eventDuration,
                calendarIdentifier: options.calendarIdentifier
            ))
        case .addReminderToExistingEvent:
            throw SaveError.unsupportedAction
        }

        // 3. Permiso (solo se pregunta si el usuario no ha decidido aún).
        var permission = access.permission(for: entity)
        if permission == .notDetermined {
            permission = try await storeCall { try await access.requestAccess(for: entity) }
        }
        guard permission == .fullAccess else {
            throw SaveError.permission(entity, permission)
        }

        // 4. Duplicados: la referencia persistente manda, no el título.
        let previous = try await registryCall { try await registry.record(for: current.id) }
        if let existing = previous {
            await unregistered.forget(current.id)
            let stillExists = try await storeCall { try await presence.itemExists(existing.reference) }
            if stillExists {
                return .alreadySaved(existing)
            }
            if !options.recreateIfMissing {
                return .previouslySavedButMissing(existing)
            }
        } else if let created = await unregistered.record(for: current.id) {
            // Este proceso sabe qué creó EventKit: se completa el registro sin volver a crear.
            return try await recoverRegistration(of: created)
        } else if let pending = try await registryCall({ try await registry.pendingCreation(for: current.id) }),
                  !options.createDespiteUnconfirmedAttempt {
            // Un intento anterior pudo crear el elemento y no hay forma de saberlo con certeza.
            throw SaveError.unconfirmedPreviousAttempt(pending)
        }

        // 5. Anotar el intento antes de crear. Si no se puede anotar, no se crea nada.
        let pending = PendingCreation(
            intentID: current.id,
            destination: current.destination,
            title: current.title.value.trimmingCharacters(in: .whitespacesAndNewlines),
            startedAt: dates.now()
        )
        try await registryCall { try await registry.markPending(pending) }

        // 6. Creación. Si EventKit lanza un error, no guardó el elemento: se retira la marca.
        //    Si tampoco se puede retirar, el siguiente intento preguntará al usuario (es más
        //    prudente preguntar de más que duplicar).
        let reference: StoredItemReference
        do {
            switch draft {
            case .reminder(let reminderDraft):
                reference = try await storeCall { try await reminders.createReminder(reminderDraft) }
            case .event(let eventDraft):
                reference = try await storeCall { try await calendar.createEvent(eventDraft) }
            }
        } catch {
            try? await registry.clearPending(for: current.id)
            throw error
        }

        // 7. Registro definitivo (borra la marca en la misma escritura).
        let record = SavedItemRecord(
            intentID: current.id,
            reference: reference,
            alertChannel: alarm.instant == nil ? AlertChannel.noAlert : AlertChannel.eventKitAlarm,
            pendingAlertDay: alarm.pendingDay,
            savedAt: dates.now()
        )
        do {
            try await registry.save(record)
        } catch {
            // El elemento existe en EventKit, pero no hay referencia persistida. Se recuerda en
            // memoria para que un reintento solo complete el registro; la marca pendiente sigue
            // en disco por si la app se cierra antes.
            await unregistered.remember(record)
            throw SaveError.createdButNotRegistered(record)
        }
        await unregistered.forget(current.id)
        return .saved(record)
    }

    /// Completa el registro de un elemento que EventKit ya creó en esta sesión. No crea nada.
    /// Si el usuario lo borró entretanto, se registra igualmente y no se recrea sin confirmación.
    private func recoverRegistration(of created: SavedItemRecord) async throws -> SaveOutcome {
        do {
            try await registry.save(created)
        } catch {
            throw SaveError.createdButNotRegistered(created)
        }
        await unregistered.forget(created.intentID)
        let stillExists = try await storeCall { try await presence.itemExists(created.reference) }
        return stillExists ? .registrationRecovered(created) : .previouslySavedButMissing(created)
    }

    private enum PreparedDraft: Sendable {
        case reminder(ReminderDraft)
        case event(CalendarEventDraft)
    }

    private func storeCall<T: Sendable>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as SaveError {
            throw error
        } catch let error as EventStoreError {
            throw SaveError.store(error)
        } catch {
            throw SaveError.store(.operationFailed(String(describing: error)))
        }
    }

    private func registryCall<T: Sendable>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            throw SaveError.registry(String(describing: error))
        }
    }
}

/// Elementos que EventKit creó en esta sesión pero cuyo registro no se pudo guardar.
///
/// Solo vive en memoria: si la app se cierra, se pierde, y queda la marca pendiente persistida
/// (`PendingCreation`) para que el siguiente intento pregunte al usuario.
actor UnregisteredCreations {
    private var records: [UUID: SavedItemRecord] = [:]

    func record(for intentID: TaskIntentID) -> SavedItemRecord? {
        records[intentID.uuid]
    }

    func remember(_ record: SavedItemRecord) {
        records[record.intentID.uuid] = record
    }

    func forget(_ intentID: TaskIntentID) {
        records[intentID.uuid] = nil
    }
}
