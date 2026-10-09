import Foundation
import RememberMeCore

// Textos para el usuario a partir de los estados y errores del dominio.

extension EventStoreEntity {
    /// Nombre de la app de Apple como aparece en Ajustes.
    var appName: String {
        switch self {
        case .events:
            return "Calendario"
        case .reminders:
            return "Recordatorios"
        }
    }
}

extension EventStorePermission {
    var label: String {
        switch self {
        case .notDetermined:
            return "Sin decidir"
        case .fullAccess:
            return "Acceso total"
        case .writeOnly:
            return "Solo añadir eventos"
        case .denied:
            return "Denegado"
        case .restricted:
            return "Restringido"
        }
    }
}

extension EventStoreError {
    var userMessage: String {
        switch self {
        case .accessNotGranted(let entity, _):
            return "Remember Me no tiene acceso total a \(entity.appName)."
        case .noDefaultContainer(.events):
            return "No hay un calendario predeterminado para eventos nuevos. Revísalo en Ajustes > Calendario."
        case .noDefaultContainer(.reminders):
            return "No hay una lista predeterminada en Recordatorios. Crea una lista en la app Recordatorios."
        case .containerNotFound(let entity):
            return "El destino elegido en \(entity.appName) ya no existe."
        case .containerReadOnly(let entity):
            return "El destino elegido en \(entity.appName) no admite cambios."
        case .operationFailed(let detail):
            return "No se pudo completar la operación: \(detail)"
        }
    }
}

extension SaveError {
    var userMessage: String {
        switch self {
        case .notReadyToSave:
            return "Revisa los datos: la entrada no está lista para guardarse."
        case .unsupportedAction:
            return "Añadir avisos a eventos existentes todavía no está disponible."
        case .missingEventTime:
            return "Un evento necesita fecha y hora."
        case .missingEventDuration:
            return "Elige la duración del evento."
        case .invalidEventDuration:
            return "La duración del evento no es válida."
        case .unresolvableDate:
            return "Esa hora no existe ese día por el cambio de horario."
        case .permission(let entity, let permission):
            return AccessGuidance(entity: entity, permission: permission).message
        case .store(let error):
            return error.userMessage
        case .registry:
            return "No se pudo leer el registro de elementos guardados. Para no crear duplicados, no se ha guardado nada."
        }
    }
}

extension ValidationMessage {
    var isError: Bool {
        severity == .error
    }
}
