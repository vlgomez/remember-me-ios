import Foundation
import Observation
import RememberMeCore

/// Estado de la pestaña Calendario: permiso, carga y agenda de los próximos 7 días.
@MainActor
@Observable
final class AgendaViewModel {
    private(set) var state: AgendaState = .idle
    private(set) var isLoading = false
    /// Error al pedir acceso (por ejemplo, si faltara la clave de privacidad en Info.plist).
    private(set) var requestError: String?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// Consulta el permiso y, si hay acceso total, los eventos. Nunca muestra la petición del sistema.
    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        state = await environment.loadAgenda.load(days: 7)
    }

    /// Solo se llama cuando el usuario pulsa "Permitir acceso".
    func requestAccess() async {
        requestError = nil
        do {
            _ = try await environment.access.requestAccessIfNeeded(for: .events)
        } catch let error as EventStoreError {
            requestError = error.userMessage
        } catch {
            requestError = error.localizedDescription
        }
        await reload()
    }

    /// Título de una sección, por ejemplo "miércoles, 7 de octubre".
    func title(for day: CalendarDay) -> String {
        let today = environment.dates.today()
        let start = environment.dates.interval(for: day).start
        let formatted = start.formatted(.dateTime.weekday(.wide).day().month(.wide))
        switch today.days(until: day) {
        case 0:
            return "Hoy · \(formatted)"
        case 1:
            return "Mañana · \(formatted)"
        default:
            return formatted.prefix(1).uppercased() + String(formatted.dropFirst())
        }
    }
}
