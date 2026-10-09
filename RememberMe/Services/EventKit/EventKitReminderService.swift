import EventKit
import RememberMeCore

/// Listas y creación de recordatorios en Apple Reminders.
///
/// Solo crea recordatorios nuevos: no modifica, completa ni borra recordatorios existentes.
final class EventKitReminderService: ReminderStoring, @unchecked Sendable {
    private let store: EKEventStore

    init(store: EKEventStore) {
        self.store = store
    }

    func reminderLists() async throws -> [ReminderListSnapshot] {
        try EventKitGuard.requireFullAccess(.reminders)
        let defaultIdentifier = store.defaultCalendarForNewReminders()?.calendarIdentifier
        return store.calendars(for: .reminder).map { list in
            ReminderListSnapshot(
                id: list.calendarIdentifier,
                title: list.title,
                isDefault: list.calendarIdentifier == defaultIdentifier,
                allowsModifications: list.allowsContentModifications
            )
        }
    }

    func createReminder(_ draft: ReminderDraft) async throws -> StoredItemReference {
        try EventKitGuard.requireFullAccess(.reminders)
        let reminder = EKReminder(eventStore: store)
        reminder.title = draft.title
        reminder.notes = draft.notes
        reminder.location = draft.location
        reminder.calendar = try list(for: draft.listIdentifier)
        // Sin zona horaria, una fecha de día completo es "flotante": el mismo día en cualquier zona.
        reminder.timeZone = draft.timeZone
        reminder.dueDateComponents = draft.dueDateComponents
        if let alarm = draft.alarm {
            reminder.addAlarm(EKAlarm(absoluteDate: alarm))
        }
        do {
            try store.save(reminder, commit: true)
        } catch {
            throw EventStoreError.operationFailed(error.localizedDescription)
        }
        return StoredItemReference(
            destination: .appleReminders,
            identifier: reminder.calendarItemIdentifier,
            externalIdentifier: reminder.calendarItemExternalIdentifier
        )
    }

    private func list(for identifier: String?) throws -> EKCalendar {
        guard let identifier else {
            guard let list = store.defaultCalendarForNewReminders() else {
                throw EventStoreError.noDefaultContainer(.reminders)
            }
            return list
        }
        guard let list = store.calendar(withIdentifier: identifier),
              list.allowedEntityTypes.contains(.reminder) else {
            throw EventStoreError.containerNotFound(.reminders)
        }
        guard list.allowsContentModifications else {
            throw EventStoreError.containerReadOnly(.reminders)
        }
        return list
    }
}
