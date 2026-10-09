import Foundation

// Puertos hacia Apple Calendar y Apple Reminders. La implementación real (EventKit) vive en la
// app, en Services/EventKit; el paquete RememberMeCore no importa EventKit. Los tests usan dobles.
//
// Las implementaciones deben lanzar `EventStoreError`.

/// Estado y solicitud de permisos. Calendar y Reminders se consultan por separado.
public protocol EventStoreAccessProviding: Sendable {
    /// Estado actual, sin mostrar ningún diálogo.
    func permission(for entity: EventStoreEntity) -> EventStorePermission
    /// Muestra el diálogo del sistema si el estado es `.notDetermined` y devuelve el estado resultante.
    func requestAccess(for entity: EventStoreEntity) async throws -> EventStorePermission
}

/// Lectura y creación de eventos de calendario.
public protocol CalendarEventStoring: Sendable {
    func events(in interval: DateInterval) async throws -> [CalendarEventSnapshot]
    func createEvent(_ draft: CalendarEventDraft) async throws -> StoredItemReference
}

/// Lectura de listas y creación de recordatorios.
public protocol ReminderStoring: Sendable {
    func reminderLists() async throws -> [ReminderListSnapshot]
    func createReminder(_ draft: ReminderDraft) async throws -> StoredItemReference
}

/// Comprueba si un elemento creado antes sigue existiendo (el usuario pudo borrarlo desde Calendar o Reminders).
public protocol StoredItemChecking: Sendable {
    func itemExists(_ reference: StoredItemReference) async throws -> Bool
}

/// Registro persistente de los elementos creados, indexado por intención.
///
/// Además de los elementos creados, guarda las marcas de intentos pendientes (`PendingCreation`)
/// que el caso de uso escribe antes de llamar a EventKit.
public protocol SavedItemRegistry: Sendable {
    func record(for intentID: TaskIntentID) async throws -> SavedItemRecord?

    /// Guarda el registro de un elemento creado y, en la misma escritura, borra la marca
    /// pendiente de esa intención.
    func save(_ record: SavedItemRecord) async throws

    /// Marca de un intento anterior que no llegó a confirmarse, si la hay.
    func pendingCreation(for intentID: TaskIntentID) async throws -> PendingCreation?

    /// Anota un intento antes de llamar a EventKit. Si falla, no se debe crear nada.
    func markPending(_ pending: PendingCreation) async throws

    /// Retira la marca cuando EventKit informó de que no creó el elemento.
    func clearPending(for intentID: TaskIntentID) async throws
}
