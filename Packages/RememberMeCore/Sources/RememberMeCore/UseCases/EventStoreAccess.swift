import Foundation

/// Consulta y solicitud de permisos de Calendar y Reminders.
///
/// Nunca pide permiso por su cuenta: `requestAccess` solo se llama cuando el usuario pulsa un
/// botón o intenta guardar algo. Al arrancar, la app solo consulta el estado.
public struct EventStoreAccessUseCase: Sendable {
    private let access: any EventStoreAccessProviding

    public init(access: any EventStoreAccessProviding) {
        self.access = access
    }

    public func permission(for entity: EventStoreEntity) -> EventStorePermission {
        access.permission(for: entity)
    }

    /// Muestra el diálogo del sistema solo si el usuario aún no ha decidido. En cualquier otro
    /// estado devuelve el estado actual: iOS no vuelve a preguntar, el cambio se hace en Ajustes.
    public func requestAccessIfNeeded(for entity: EventStoreEntity) async throws -> EventStorePermission {
        let current = access.permission(for: entity)
        guard current == .notDetermined else { return current }
        do {
            return try await access.requestAccess(for: entity)
        } catch let error as EventStoreError {
            throw error
        } catch {
            throw EventStoreError.operationFailed(String(describing: error))
        }
    }
}

/// Qué puede hacer el usuario ante un estado de permiso.
public enum AccessAction: String, Sendable, Hashable {
    /// Mostrar el diálogo del sistema.
    case requestAccess
    /// Abrir Ajustes: iOS ya no muestra el diálogo.
    case openSettings
    /// Nada que hacer (concedido, o restringido por el dispositivo).
    case noAction
}

/// Texto y acción para explicar un estado de permiso en la interfaz.
public struct AccessGuidance: Sendable, Hashable {
    public let title: String
    public let message: String
    public let action: AccessAction
    public let actionTitle: String?

    public init(entity: EventStoreEntity, permission: EventStorePermission) {
        let what = entity == .events ? "al calendario" : "a Recordatorios"
        let purpose = entity == .events
            ? "para mostrar tu agenda y guardar las citas que confirmes"
            : "para guardar las tareas y compras que confirmes y elegir en qué lista"

        switch permission {
        case .notDetermined:
            title = "Acceso \(what) pendiente"
            message = "Remember Me necesita acceso \(what) \(purpose). Solo se pedirá cuando pulses el botón."
            action = .requestAccess
            actionTitle = "Permitir acceso"
        case .fullAccess:
            title = "Acceso \(what) concedido"
            message = "Remember Me puede leer y guardar elementos."
            action = .noAction
            actionTitle = nil
        case .writeOnly:
            title = "Acceso \(what) limitado"
            message = "Solo puedes añadir eventos. Para ver tu agenda y evitar duplicados, elige «Acceso total» para Remember Me en Ajustes."
            action = .openSettings
            actionTitle = "Abrir Ajustes"
        case .denied:
            title = "Acceso \(what) denegado"
            message = "Has denegado el acceso \(what). Puedes activarlo en Ajustes, dentro de Remember Me."
            action = .openSettings
            actionTitle = "Abrir Ajustes"
        case .restricted:
            title = "Acceso \(what) restringido"
            message = "Este dispositivo restringe el acceso \(what) (por ejemplo, con Tiempo de uso o un perfil de gestión). Remember Me no puede cambiarlo."
            action = .noAction
            actionTitle = nil
        }
    }
}
