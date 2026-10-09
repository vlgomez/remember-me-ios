import EventKit
import Foundation
import RememberMeCore

/// Dependencias compartidas por las pantallas.
///
/// Las pantallas solo ven casos de uso de `RememberMeCore`; EventKit queda encerrado en
/// `Services/EventKit`. Crear el entorno no pide ningún permiso: los permisos se piden cuando
/// el usuario pulsa un botón que los necesita.
struct AppEnvironment: Sendable {
    let dates: DateContext
    let access: EventStoreAccessUseCase
    let loadAgenda: LoadAgendaUseCase
    let loadReminderLists: LoadReminderListsUseCase
    let saveTask: SaveConfirmedTaskUseCase
    let interpret: InterpretTaskUseCase

    static func live() -> AppEnvironment {
        let dates = DateContext.spain()
        // Un único EKEventStore para toda la app, como recomienda Apple.
        let store = EKEventStore()
        let accessService = EventKitAccessService(store: store)
        let calendarService = EventKitCalendarService(store: store)
        let reminderService = EventKitReminderService(store: store)
        let presenceService = EventKitItemPresenceService(store: store)

        return AppEnvironment(
            dates: dates,
            access: EventStoreAccessUseCase(access: accessService),
            loadAgenda: LoadAgendaUseCase(access: accessService, calendar: calendarService, dates: dates),
            loadReminderLists: LoadReminderListsUseCase(access: accessService, reminders: reminderService),
            saveTask: SaveConfirmedTaskUseCase(
                access: accessService,
                calendar: calendarService,
                reminders: reminderService,
                presence: presenceService,
                registry: SavedItemStorage.makeRegistry(),
                dates: dates
            ),
            interpret: InterpretTaskUseCase(
                parser: DeterministicSpanishParser(),
                context: ParsingContext(dates: dates)
            )
        )
    }
}
