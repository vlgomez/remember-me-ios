import Foundation

/// Tipo de dato de Apple al que se pide acceso. Calendar y Reminders tienen permisos independientes.
public enum EventStoreEntity: String, Sendable, Hashable, Codable, CaseIterable {
    /// Eventos de Apple Calendar.
    case events
    /// Recordatorios de Apple Reminders.
    case reminders
}

/// Estado del permiso para una `EventStoreEntity`, independiente de EventKit.
public enum EventStorePermission: String, Sendable, Hashable, Codable, CaseIterable {
    /// El usuario todavía no ha decidido.
    case notDetermined
    /// Acceso total: leer y escribir.
    case fullAccess
    /// Solo añadir eventos (iOS 17). No permite leer la agenda ni comprobar duplicados.
    case writeOnly
    /// El usuario lo ha denegado. Solo se puede cambiar desde Ajustes.
    case denied
    /// Restringido por el dispositivo (Tiempo de uso, perfil de gestión). La app no puede cambiarlo.
    case restricted

    public var allowsReadingAndWriting: Bool {
        self == .fullAccess
    }
}

/// Errores de acceso a Calendar o Reminders, sin tipos de EventKit.
public enum EventStoreError: Error, Sendable, Hashable {
    /// Se intentó una operación sin acceso total.
    case accessNotGranted(EventStoreEntity, EventStorePermission)
    /// No hay calendario o lista por defecto donde guardar.
    case noDefaultContainer(EventStoreEntity)
    /// El calendario o la lista indicados no existen.
    case containerNotFound(EventStoreEntity)
    /// El calendario o la lista no admiten cambios (por ejemplo, un calendario suscrito).
    case containerReadOnly(EventStoreEntity)
    /// EventKit rechazó la operación.
    case operationFailed(String)
}

/// Evento existente de Calendar, copiado a un valor sin referencias a EventKit.
public struct CalendarEventSnapshot: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let calendarTitle: String?
    /// Ubicación tal y como está guardada en Calendar (texto).
    public let location: String?

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        calendarTitle: String?,
        location: String?
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarTitle = calendarTitle
        self.location = location
    }
}

/// Lista de Apple Reminders.
public struct ReminderListSnapshot: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let isDefault: Bool
    public let allowsModifications: Bool

    public init(id: String, title: String, isDefault: Bool, allowsModifications: Bool) {
        self.id = id
        self.title = title
        self.isDefault = isDefault
        self.allowsModifications = allowsModifications
    }
}

/// Referencia persistente a un elemento creado por la app en Calendar o Reminders.
public struct StoredItemReference: Sendable, Hashable, Codable {
    public let destination: TaskDestination
    /// `calendarItemIdentifier` de EventKit (local al dispositivo).
    public let identifier: String
    /// `calendarItemExternalIdentifier` de EventKit, si ya existe (sirve tras una sincronización).
    public let externalIdentifier: String?

    public init(destination: TaskDestination, identifier: String, externalIdentifier: String?) {
        self.destination = destination
        self.identifier = identifier
        self.externalIdentifier = externalIdentifier
    }

    public var entity: EventStoreEntity {
        switch destination {
        case .appleCalendar:
            return .events
        case .appleReminders:
            return .reminders
        }
    }
}

/// Quién se encarga de avisar de un elemento guardado. Sirve para no duplicar avisos:
/// si ya hay una alarma de EventKit, la Fase D no debe programar además una notificación local.
public enum AlertChannel: String, Sendable, Hashable, Codable {
    /// Sin aviso.
    case noAlert
    /// Alarma de EventKit dentro del propio evento o recordatorio.
    case eventKitAlarm
}

/// Registro de un elemento creado a partir de una intención, para evitar duplicados.
public struct SavedItemRecord: Sendable, Hashable, Codable {
    public let intentID: TaskIntentID
    public let reference: StoredItemReference
    public let alertChannel: AlertChannel
    /// Día de un aviso confirmado cuya hora aún no se ha elegido (p. ej., "tres días antes del 20").
    /// No se crea ninguna alarma hasta que el usuario elija la hora.
    public let pendingAlertDay: CalendarDay?
    public let savedAt: Date

    public init(
        intentID: TaskIntentID,
        reference: StoredItemReference,
        alertChannel: AlertChannel,
        pendingAlertDay: CalendarDay?,
        savedAt: Date
    ) {
        self.intentID = intentID
        self.reference = reference
        self.alertChannel = alertChannel
        self.pendingAlertDay = pendingAlertDay
        self.savedAt = savedAt
    }
}

/// Intento de creación anotado en el registro *antes* de pedir a EventKit que cree el elemento.
///
/// Crear un elemento en EventKit y escribir su referencia en el registro local son dos
/// operaciones independientes: no forman una transacción. Si la escritura final falla, o la app
/// se cierra entre las dos, esta marca queda como prueba de que hubo un intento cuyo resultado
/// no se pudo confirmar, y el siguiente guardado de la misma intención no crea nada sin
/// preguntar al usuario.
public struct PendingCreation: Sendable, Hashable, Codable {
    public let intentID: TaskIntentID
    public let destination: TaskDestination
    /// Título del elemento, para que el usuario pueda buscarlo en Calendar o Reminders.
    public let title: String
    public let startedAt: Date

    public init(intentID: TaskIntentID, destination: TaskDestination, title: String, startedAt: Date) {
        self.intentID = intentID
        self.destination = destination
        self.title = title
        self.startedAt = startedAt
    }
}

/// Datos de un recordatorio que se va a crear. Todo lo que contiene procede de una intención confirmada.
public struct ReminderDraft: Sendable, Hashable {
    public let title: String
    public let notes: String?
    /// Ubicación textual; no se geocodifica.
    public let location: String?
    /// Fecha de vencimiento: día completo o día con hora. `nil` si la tarea no tiene fecha.
    public let due: TaskDate?
    /// Zona horaria de `due` cuando tiene hora.
    public let timeZone: TimeZone?
    /// Instante de la alarma, solo si el usuario confirmó un aviso con hora concreta.
    public let alarm: Date?
    /// Lista de destino. `nil` usa la lista por defecto de Reminders.
    public let listIdentifier: String?

    public init(
        title: String,
        notes: String?,
        location: String?,
        due: TaskDate?,
        timeZone: TimeZone?,
        alarm: Date?,
        listIdentifier: String?
    ) {
        self.title = title
        self.notes = notes
        self.location = location
        self.due = due
        self.timeZone = timeZone
        self.alarm = alarm
        self.listIdentifier = listIdentifier
    }

    /// Componentes para `EKReminder.dueDateComponents`.
    ///
    /// Un día completo se expresa solo con año, mes y día, sin hora ni zona horaria, para que
    /// Reminders lo trate como "todo el día" y no como medianoche.
    public var dueDateComponents: DateComponents? {
        guard let due else { return nil }
        switch due {
        case .allDay(let day):
            return DateComponents(year: day.year, month: day.month, day: day.day)
        case .timed(let local):
            return DateComponents(
                timeZone: timeZone,
                year: local.day.year,
                month: local.day.month,
                day: local.day.day,
                hour: local.time.hour,
                minute: local.time.minute
            )
        }
    }
}

/// Datos de un evento de calendario que se va a crear.
public struct CalendarEventDraft: Sendable, Hashable {
    public let title: String
    public let notes: String?
    public let location: String?
    public let start: Date
    public let end: Date
    public let timeZone: TimeZone
    public let alarm: Date?
    /// Calendario de destino. `nil` usa el calendario por defecto.
    public let calendarIdentifier: String?

    public init(
        title: String,
        notes: String?,
        location: String?,
        start: Date,
        end: Date,
        timeZone: TimeZone,
        alarm: Date?,
        calendarIdentifier: String?
    ) {
        self.title = title
        self.notes = notes
        self.location = location
        self.start = start
        self.end = end
        self.timeZone = timeZone
        self.alarm = alarm
        self.calendarIdentifier = calendarIdentifier
    }
}
