import Foundation
import RememberMeCore

/// Dependencias compartidas por las pantallas.
///
/// En la Fase A solo contiene el contexto de fechas. Los servicios de EventKit y
/// notificaciones se añadirán aquí en las fases B y D, detrás de protocolos.
struct AppEnvironment: Sendable {
    let dates: DateContext

    static func live() -> AppEnvironment {
        AppEnvironment(dates: .spain())
    }
}
