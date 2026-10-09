import Foundation
import Observation
import RememberMeCore

/// Estado de Ajustes: permisos de Calendar y Reminders y listas de Reminders.
@MainActor
@Observable
final class SettingsViewModel {
    private(set) var calendarPermission: EventStorePermission = .notDetermined
    private(set) var remindersPermission: EventStorePermission = .notDetermined
    private(set) var lists: ReminderListsState = .idle
    private(set) var requestError: String?

    let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// Lee los permisos y, si hay acceso total a Reminders, las listas. No pide nada.
    func refresh() async {
        calendarPermission = environment.access.permission(for: .events)
        remindersPermission = environment.access.permission(for: .reminders)
        lists = await environment.loadReminderLists.load()
    }

    /// Solo se llama cuando el usuario pulsa "Permitir acceso".
    func requestAccess(for entity: EventStoreEntity) async {
        requestError = nil
        do {
            _ = try await environment.access.requestAccessIfNeeded(for: entity)
        } catch let error as EventStoreError {
            requestError = error.userMessage
        } catch {
            requestError = error.localizedDescription
        }
        await refresh()
    }

    func permission(for entity: EventStoreEntity) -> EventStorePermission {
        switch entity {
        case .events:
            return calendarPermission
        case .reminders:
            return remindersPermission
        }
    }
}
