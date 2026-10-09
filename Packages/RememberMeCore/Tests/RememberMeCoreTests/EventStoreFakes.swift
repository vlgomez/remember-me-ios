import Foundation
import XCTest
@testable import RememberMeCore

/// Doble de prueba de Calendar y Reminders. Simula permisos independientes por entidad,
/// guarda lo que se le pide crear y cuenta cuántas veces se muestra el diálogo de permisos.
///
/// Como el EventKit real, rechaza leer o escribir sin acceso total.
final class FakeEventStore: EventStoreAccessProviding, CalendarEventStoring, ReminderStoring, StoredItemChecking, @unchecked Sendable {
    struct State {
        var permissions: [EventStoreEntity: EventStorePermission] = [:]
        /// Respuesta del usuario al diálogo del sistema. Si no se indica, el estado no cambia.
        var answerToRequest: [EventStoreEntity: EventStorePermission] = [:]
        var requestFailure: (any Error)?
        var requestCounts: [EventStoreEntity: Int] = [:]

        var events: [CalendarEventSnapshot] = []
        var lists: [ReminderListSnapshot] = []
        var queriedIntervals: [DateInterval] = []
        var listQueries = 0
        var readFailure: (any Error)?

        var createdReminders: [ReminderDraft] = []
        var createdEvents: [CalendarEventDraft] = []
        var createFailure: (any Error)?
        var existingIdentifiers: Set<String> = []
        var checkedReferences: [StoredItemReference] = []
        var nextNumber = 1
    }

    private let lock = NSLock()
    private var state = State()

    init(events: EventStorePermission = .notDetermined, reminders: EventStorePermission = .notDetermined) {
        state.permissions = [.events: events, .reminders: reminders]
    }

    // MARK: - Configuración e inspección desde los tests

    func update(_ body: (inout State) -> Void) {
        withState(body)
    }

    var snapshot: State {
        withState { $0 }
    }

    func requestCount(for entity: EventStoreEntity) -> Int {
        withState { $0.requestCounts[entity] ?? 0 }
    }

    var totalRequests: Int {
        withState { $0.requestCounts.values.reduce(0, +) }
    }

    /// Simula que el usuario borra el elemento desde Calendar o Reminders.
    func deleteItem(identifier: String) {
        withState { _ = $0.existingIdentifiers.remove(identifier) }
    }

    // MARK: - EventStoreAccessProviding

    func permission(for entity: EventStoreEntity) -> EventStorePermission {
        withState { $0.permissions[entity] ?? .notDetermined }
    }

    func requestAccess(for entity: EventStoreEntity) async throws -> EventStorePermission {
        try withState { state in
            state.requestCounts[entity, default: 0] += 1
            if let failure = state.requestFailure {
                throw failure
            }
            let current = state.permissions[entity] ?? .notDetermined
            // iOS solo muestra el diálogo si el usuario no ha decidido.
            guard current == .notDetermined else { return current }
            let answer = state.answerToRequest[entity] ?? current
            state.permissions[entity] = answer
            return answer
        }
    }

    // MARK: - CalendarEventStoring

    func events(in interval: DateInterval) async throws -> [CalendarEventSnapshot] {
        try withState { state in
            try Self.requireFullAccess(.events, in: state)
            state.queriedIntervals.append(interval)
            if let failure = state.readFailure {
                throw failure
            }
            return state.events.filter { $0.start < interval.end && $0.end > interval.start }
        }
    }

    func createEvent(_ draft: CalendarEventDraft) async throws -> StoredItemReference {
        try withState { state in
            try Self.requireFullAccess(.events, in: state)
            if let failure = state.createFailure {
                throw failure
            }
            state.createdEvents.append(draft)
            let identifier = "event-\(state.nextNumber)"
            state.nextNumber += 1
            state.existingIdentifiers.insert(identifier)
            return StoredItemReference(destination: .appleCalendar, identifier: identifier, externalIdentifier: nil)
        }
    }

    // MARK: - ReminderStoring

    func reminderLists() async throws -> [ReminderListSnapshot] {
        try withState { state in
            try Self.requireFullAccess(.reminders, in: state)
            state.listQueries += 1
            if let failure = state.readFailure {
                throw failure
            }
            return state.lists
        }
    }

    func createReminder(_ draft: ReminderDraft) async throws -> StoredItemReference {
        try withState { state in
            try Self.requireFullAccess(.reminders, in: state)
            if let failure = state.createFailure {
                throw failure
            }
            state.createdReminders.append(draft)
            let identifier = "reminder-\(state.nextNumber)"
            state.nextNumber += 1
            state.existingIdentifiers.insert(identifier)
            return StoredItemReference(destination: .appleReminders, identifier: identifier, externalIdentifier: nil)
        }
    }

    // MARK: - StoredItemChecking

    func itemExists(_ reference: StoredItemReference) async throws -> Bool {
        try withState { state in
            try Self.requireFullAccess(reference.entity, in: state)
            state.checkedReferences.append(reference)
            return state.existingIdentifiers.contains(reference.identifier)
        }
    }

    // MARK: - Privado

    private static func requireFullAccess(_ entity: EventStoreEntity, in state: State) throws {
        let permission = state.permissions[entity] ?? .notDetermined
        guard permission == .fullAccess else {
            throw EventStoreError.accessNotGranted(entity, permission)
        }
    }

    private func withState<T>(_ body: (inout State) throws -> T) rethrows -> T {
        try lock.withLock {
            try body(&state)
        }
    }
}

/// Registro que no se puede leer ni escribir (disco lleno, archivo dañado...).
struct FailingRegistry: SavedItemRegistry {
    struct Failure: Error {}

    func record(for intentID: TaskIntentID) async throws -> SavedItemRecord? {
        throw Failure()
    }

    func save(_ record: SavedItemRecord) async throws {
        throw Failure()
    }
}

/// Error genérico (no `EventStoreError`) para comprobar cómo se envuelven los errores inesperados.
struct UnexpectedStoreError: Error, CustomStringConvertible {
    var description: String { "fallo inesperado" }
}

/// Datos para los tests de la Fase B. "Ahora" es el miércoles 7 de octubre de 2026, 09:00 en Madrid.
enum StoreFixtures {
    static let otherID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    /// Valida la intención con el reloj fijo de los tests y comprueba que se puede guardar.
    static func ready(
        _ intent: TaskIntent,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> TaskIntent {
        let result = TaskIntentValidator(dates: Fixtures.dates()).validate(intent)
        let validated = try XCTUnwrap(result.intent, file: file, line: line)
        XCTAssertEqual(validated.validationState, .readyToSave, "Mensajes: \(result.messages)", file: file, line: line)
        return validated
    }

    /// Cita con hora, aportada por el usuario.
    static func appointment(
        at local: LocalDateTime,
        reminderPolicy: ReminderPolicy = .noReminder
    ) -> TaskIntent {
        Fixtures.intent(
            title: "Dentista",
            kind: .appointment,
            action: .createCalendarEvent,
            scheduledAt: .timed(local),
            timeZone: Fixtures.madrid,
            reminderPolicy: reminderPolicy
        )
    }

    /// Misma tarea con otro identificador de intención.
    static func task(id: UUID, title: String, scheduledAt: TaskDate) -> TaskIntent {
        TaskIntent(
            id: TaskIntentID(id),
            action: .userProvided(.createTask),
            title: .userProvided(title),
            kind: .userProvided(.task),
            scheduledAt: .userProvided(scheduledAt)
        )
    }

    static func event(
        _ title: String,
        start: String,
        end: String,
        allDay: Bool = false
    ) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: "id-\(title)",
            title: title,
            start: Fixtures.instant(start),
            end: Fixtures.instant(end),
            isAllDay: allDay,
            calendarTitle: "Casa",
            location: nil
        )
    }
}
