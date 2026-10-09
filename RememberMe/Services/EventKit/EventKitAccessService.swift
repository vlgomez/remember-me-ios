import EventKit
import RememberMeCore

/// Estado y petición de permisos de Calendar y Reminders con EventKit (iOS 17+).
///
/// Calendar y Reminders tienen permisos independientes. La app pide acceso total en los dos
/// casos: necesita leer la agenda y comprobar si los elementos que creó siguen existiendo, y
/// Reminders no ofrece un acceso de solo escritura. Las claves de `Info.plist` correspondientes
/// son `NSCalendarsFullAccessUsageDescription` y `NSRemindersFullAccessUsageDescription`.
///
/// `@unchecked Sendable`: comparte un único `EKEventStore`, como recomienda Apple, y solo
/// guarda esa referencia inmutable.
final class EventKitAccessService: EventStoreAccessProviding, @unchecked Sendable {
    private let store: EKEventStore

    init(store: EKEventStore) {
        self.store = store
    }

    func permission(for entity: EventStoreEntity) -> EventStorePermission {
        Self.permission(from: EKEventStore.authorizationStatus(for: entity.ekEntityType))
    }

    /// Solo muestra el diálogo del sistema si el usuario no ha decidido. EventKit no vuelve a
    /// preguntar después de una respuesta: el cambio se hace en Ajustes.
    func requestAccess(for entity: EventStoreEntity) async throws -> EventStorePermission {
        guard permission(for: entity) == .notDetermined else {
            return permission(for: entity)
        }
        do {
            switch entity {
            case .events:
                _ = try await store.requestFullAccessToEvents()
            case .reminders:
                _ = try await store.requestFullAccessToReminders()
            }
        } catch {
            throw EventStoreError.operationFailed(error.localizedDescription)
        }
        return permission(for: entity)
    }

    static func permission(from status: EKAuthorizationStatus) -> EventStorePermission {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .fullAccess:
            return .fullAccess
        case .writeOnly:
            return .writeOnly
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            // Un estado que esta versión no conoce no da acceso: se trata como denegado,
            // que lleva al usuario a revisar Ajustes.
            return .denied
        }
    }
}

extension EventStoreEntity {
    var ekEntityType: EKEntityType {
        switch self {
        case .events:
            return .event
        case .reminders:
            return .reminder
        }
    }
}

extension Notification.Name {
    /// Cambios en Calendar o Reminders hechos fuera de la app (o por la propia app).
    /// Las vistas lo usan sin importar EventKit.
    static let eventStoreDidChange = Notification.Name.EKEventStoreChanged
}
