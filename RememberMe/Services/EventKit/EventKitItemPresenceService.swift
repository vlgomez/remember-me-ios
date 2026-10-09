import EventKit
import RememberMeCore

/// Comprueba si un elemento creado por la app sigue existiendo en Calendar o Reminders.
///
/// Primero busca por `calendarItemIdentifier`. Si no aparece, prueba con
/// `calendarItemExternalIdentifier`, que se conserva cuando EventKit cambia el identificador
/// local tras una sincronización completa con el servidor.
final class EventKitItemPresenceService: StoredItemChecking, @unchecked Sendable {
    private let store: EKEventStore

    init(store: EKEventStore) {
        self.store = store
    }

    func itemExists(_ reference: StoredItemReference) async throws -> Bool {
        try EventKitGuard.requireFullAccess(reference.entity)
        if store.calendarItem(withIdentifier: reference.identifier) != nil {
            return true
        }
        if let external = reference.externalIdentifier, !external.isEmpty {
            return !store.calendarItems(withExternalIdentifier: external).isEmpty
        }
        return false
    }
}
