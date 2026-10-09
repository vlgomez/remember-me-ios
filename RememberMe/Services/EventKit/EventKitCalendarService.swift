import EventKit
import RememberMeCore

/// Lectura y creación de eventos en Apple Calendar.
///
/// Solo crea eventos nuevos: no modifica ni borra eventos existentes.
final class EventKitCalendarService: CalendarEventStoring, @unchecked Sendable {
    private let store: EKEventStore

    init(store: EKEventStore) {
        self.store = store
    }

    func events(in interval: DateInterval) async throws -> [CalendarEventSnapshot] {
        try EventKitGuard.requireFullAccess(.events)
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        return store.events(matching: predicate).map { event in
            CalendarEventSnapshot(
                // Las repeticiones de un evento comparten identificador: se añade su inicio.
                id: "\(event.calendarItemIdentifier)|\(event.startDate.timeIntervalSince1970)",
                title: event.title ?? "",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                calendarTitle: event.calendar?.title,
                location: event.location
            )
        }
    }

    func createEvent(_ draft: CalendarEventDraft) async throws -> StoredItemReference {
        try EventKitGuard.requireFullAccess(.events)
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.notes = draft.notes
        event.location = draft.location
        event.calendar = try calendar(for: draft.calendarIdentifier)
        event.timeZone = draft.timeZone
        event.isAllDay = false
        event.startDate = draft.start
        event.endDate = draft.end
        if let alarm = draft.alarm {
            event.addAlarm(EKAlarm(absoluteDate: alarm))
        }
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw EventStoreError.operationFailed(error.localizedDescription)
        }
        return StoredItemReference(
            destination: .appleCalendar,
            identifier: event.calendarItemIdentifier,
            externalIdentifier: event.calendarItemExternalIdentifier
        )
    }

    private func calendar(for identifier: String?) throws -> EKCalendar {
        guard let identifier else {
            guard let calendar = store.defaultCalendarForNewEvents else {
                throw EventStoreError.noDefaultContainer(.events)
            }
            return calendar
        }
        guard let calendar = store.calendar(withIdentifier: identifier),
              calendar.allowedEntityTypes.contains(.event) else {
            throw EventStoreError.containerNotFound(.events)
        }
        guard calendar.allowsContentModifications else {
            throw EventStoreError.containerReadOnly(.events)
        }
        return calendar
    }
}

/// Comprobaciones comunes de permisos antes de llamar a EventKit.
enum EventKitGuard {
    static func requireFullAccess(_ entity: EventStoreEntity) throws {
        let permission = EventKitAccessService.permission(
            from: EKEventStore.authorizationStatus(for: entity.ekEntityType)
        )
        guard permission == .fullAccess else {
            throw EventStoreError.accessNotGranted(entity, permission)
        }
    }
}
