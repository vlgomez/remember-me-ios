import Foundation
import XCTest
@testable import RememberMeCore

/// "Ahora" es el miércoles 7 de octubre de 2026, 09:00 en Madrid.
final class SaveConfirmedTaskTests: XCTestCase {
    private struct SUT {
        let useCase: SaveConfirmedTaskUseCase
        let store: FakeEventStore
        let registry: InMemorySavedItemRegistry
    }

    private func makeSUT(
        events: EventStorePermission = .fullAccess,
        reminders: EventStorePermission = .fullAccess
    ) -> SUT {
        let store = FakeEventStore(events: events, reminders: reminders)
        let registry = InMemorySavedItemRegistry()
        let useCase = SaveConfirmedTaskUseCase(
            access: store,
            calendar: store,
            reminders: store,
            presence: store,
            registry: registry,
            dates: Fixtures.dates()
        )
        return SUT(useCase: useCase, store: store, registry: registry)
    }

    private func assertSaveFails(
        _ expected: SaveError,
        _ operation: () async throws -> SaveOutcome,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            let outcome = try await operation()
            XCTFail("Se esperaba \(expected) y se obtuvo \(outcome)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? SaveError, expected, file: file, line: line)
        }
    }

    // MARK: - Solo se guarda lo confirmado

    func testIntentWaitingForConfirmationIsNotSaved() async throws {
        let interpreted = try await InterpretTaskUseCase(parser: DeterministicSpanishParser(), context: Fixtures.parsing())
            .interpret("Llamar al taller el viernes a las 10")
        let intent = try XCTUnwrap(interpreted.intent)
        XCTAssertEqual(intent.validationState, .needsConfirmation)
        let sut = makeSUT(reminders: .notDetermined)

        await assertSaveFails(.notReadyToSave(.needsConfirmation)) { try await sut.useCase.save(intent) }

        XCTAssertEqual(sut.store.totalRequests, 0, "No se pide permiso para algo que no se va a guardar")
        XCTAssertTrue(sut.store.snapshot.createdReminders.isEmpty)
    }

    func testAmbiguousIntentIsNotSaved() async throws {
        let interpreted = try await InterpretTaskUseCase(parser: DeterministicSpanishParser(), context: Fixtures.parsing())
            .interpret("Llamar a mamá mañana a las 5")
        let intent = try XCTUnwrap(interpreted.intent)
        XCTAssertEqual(intent.validationState, .needsClarification)
        let sut = makeSUT(reminders: .notDetermined)

        await assertSaveFails(.notReadyToSave(.needsClarification)) { try await sut.useCase.save(intent) }

        XCTAssertEqual(sut.store.totalRequests, 0)
        XCTAssertTrue(sut.store.snapshot.createdReminders.isEmpty)
    }

    func testUnvalidatedIntentIsNotSaved() async {
        let sut = makeSUT()

        await assertSaveFails(.notReadyToSave(.notValidated)) { try await sut.useCase.save(Fixtures.intent()) }

        XCTAssertTrue(sut.store.snapshot.createdReminders.isEmpty)
    }

    func testConfirmedInterpretationIsSaved() async throws {
        let interpret = InterpretTaskUseCase(parser: DeterministicSpanishParser(), context: Fixtures.parsing())
        let result = try await interpret.interpret("Llamar al taller el viernes a las 10")
        let interpreted = try XCTUnwrap(result.intent)
        let confirmation = try interpret.confirm(interpreted, shownIn: IntentPreview(showing: interpreted))
        let confirmed = try XCTUnwrap(confirmation.intent)
        XCTAssertEqual(confirmed.validationState, .readyToSave)
        let sut = makeSUT()

        let outcome = try await sut.useCase.save(confirmed)

        guard case .saved = outcome else { return XCTFail("Resultado inesperado: \(outcome)") }
        let draft = try XCTUnwrap(sut.store.snapshot.createdReminders.first)
        XCTAssertEqual(draft.due, .timed(Fixtures.at(2026, 10, 9, 10)))
        XCTAssertEqual(draft.alarm, Fixtures.instant("2026-10-09T10:00:00+02:00"))
    }

    // MARK: - Recordatorios: fechas

    func testAllDayReminderHasNoTime() async throws {
        let intent = try StoreFixtures.ready(Fixtures.intent(scheduledAt: .allDay(Fixtures.day(2026, 10, 9))))
        let sut = makeSUT()

        let outcome = try await sut.useCase.save(intent)

        let draft = try XCTUnwrap(sut.store.snapshot.createdReminders.first)
        XCTAssertEqual(draft.due, .allDay(Fixtures.day(2026, 10, 9)))
        XCTAssertEqual(draft.dueDateComponents, DateComponents(year: 2026, month: 10, day: 9))
        XCTAssertNil(draft.dueDateComponents?.hour, "Un día completo no se convierte en medianoche")
        XCTAssertNil(draft.timeZone)
        XCTAssertNil(draft.alarm)
        XCTAssertEqual(outcome.record.alertChannel, .noAlert)
        XCTAssertNil(outcome.record.pendingAlertDay)
    }

    func testTimedReminderKeepsTimeZoneAndAlarm() async throws {
        let local = Fixtures.at(2026, 10, 9, 10)
        let intent = try StoreFixtures.ready(Fixtures.intent(
            scheduledAt: .timed(local),
            timeZone: Fixtures.madrid,
            reminderPolicy: .at(local)
        ))
        let sut = makeSUT()

        let outcome = try await sut.useCase.save(intent)

        let draft = try XCTUnwrap(sut.store.snapshot.createdReminders.first)
        XCTAssertEqual(
            draft.dueDateComponents,
            DateComponents(timeZone: Fixtures.madrid, year: 2026, month: 10, day: 9, hour: 10, minute: 0)
        )
        XCTAssertEqual(draft.alarm, Fixtures.instant("2026-10-09T10:00:00+02:00"))
        XCTAssertEqual(outcome.record.alertChannel, .eventKitAlarm)
        XCTAssertEqual(outcome.record.reference.destination, .appleReminders)
    }

    func testReminderWithoutPolicyHasNoAlarm() async throws {
        let intent = try StoreFixtures.ready(Fixtures.intent(
            scheduledAt: .timed(Fixtures.at(2026, 10, 9, 10)),
            timeZone: Fixtures.madrid
        ))
        let sut = makeSUT()

        let outcome = try await sut.useCase.save(intent)

        XCTAssertNil(sut.store.snapshot.createdReminders.first?.alarm)
        XCTAssertEqual(outcome.record.alertChannel, .noAlert)
    }

    func testAlarmInThePastIsNotCreated() async throws {
        let earlier = Fixtures.at(2026, 10, 7, 8)
        let intent = try StoreFixtures.ready(Fixtures.intent(
            scheduledAt: .timed(earlier),
            timeZone: Fixtures.madrid,
            reminderPolicy: .at(earlier)
        ))
        let sut = makeSUT()

        let outcome = try await sut.useCase.save(intent)

        let draft = try XCTUnwrap(sut.store.snapshot.createdReminders.first)
        XCTAssertEqual(draft.due, .timed(earlier), "La fecha que dijo el usuario se conserva")
        XCTAssertNil(draft.alarm, "No se crea una alarma que ya ha pasado")
        XCTAssertEqual(outcome.record.alertChannel, .noAlert)
    }

    func testExclusiveDeadlineUsesTheLastValidDay() async throws {
        let deadline = Deadline(date: .allDay(Fixtures.day(2026, 11, 20)), boundary: .exclusive)
        let intent = try StoreFixtures.ready(Fixtures.intent(deadline: deadline))
        let sut = makeSUT()

        _ = try await sut.useCase.save(intent)

        let draft = try XCTUnwrap(sut.store.snapshot.createdReminders.first)
        XCTAssertEqual(draft.due, .allDay(Fixtures.day(2026, 11, 19)), "«Antes del 20» vence el 19")
        XCTAssertNil(draft.notes)
    }

    func testInclusiveDeadlineUsesTheSameDay() async throws {
        let deadline = Deadline(date: .allDay(Fixtures.day(2026, 11, 20)), boundary: .inclusive)
        let intent = try StoreFixtures.ready(Fixtures.intent(deadline: deadline))
        let sut = makeSUT()

        _ = try await sut.useCase.save(intent)

        XCTAssertEqual(sut.store.snapshot.createdReminders.first?.due, .allDay(Fixtures.day(2026, 11, 20)))
    }

    func testScheduledDateWinsAndDeadlineIsKeptInNotes() async throws {
        let deadline = Deadline(date: .allDay(Fixtures.day(2026, 11, 20)), boundary: .exclusive)
        let base = Fixtures.intent(deadline: deadline, scheduledAt: .allDay(Fixtures.day(2026, 11, 10)))
        let intent = try StoreFixtures.ready(base.updatingNotes("Llevar el recibo"))
        let sut = makeSUT()

        _ = try await sut.useCase.save(intent)

        let draft = try XCTUnwrap(sut.store.snapshot.createdReminders.first)
        XCTAssertEqual(draft.due, .allDay(Fixtures.day(2026, 11, 10)))
        XCTAssertEqual(draft.notes, "Llevar el recibo\nFecha límite: antes del 20/11/2026")
    }

    func testTimedDeadlineNoteIncludesTheTime() async throws {
        let deadline = Deadline(date: .timed(Fixtures.at(2026, 11, 20, 18, 30)), boundary: .inclusive)
        let intent = try StoreFixtures.ready(Fixtures.intent(
            deadline: deadline,
            scheduledAt: .allDay(Fixtures.day(2026, 11, 10)),
            timeZone: Fixtures.madrid
        ))
        let sut = makeSUT()

        _ = try await sut.useCase.save(intent)

        XCTAssertEqual(sut.store.snapshot.createdReminders.first?.notes, "Fecha límite: 20/11/2026 a las 18:30")
    }

    func testDaysBeforeAnAllDayDeadlineLeavesTheAlertPending() async throws {
        let deadline = Deadline(date: .allDay(Fixtures.day(2026, 11, 20)), boundary: .inclusive)
        let intent = try StoreFixtures.ready(Fixtures.intent(deadline: deadline, reminderPolicy: .beforeDeadline(.days(3))))
        let sut = makeSUT()

        let outcome = try await sut.useCase.save(intent)

        XCTAssertNil(sut.store.snapshot.createdReminders.first?.alarm, "Sin hora no se inventa una alarma")
        XCTAssertEqual(outcome.record.pendingAlertDay, Fixtures.day(2026, 11, 17))
        XCTAssertEqual(outcome.record.alertChannel, .noAlert)
    }

    func testLocationIsSavedAsTypedText() async throws {
        let location = try XCTUnwrap(TaskLocation(text: "  Mercadona "))
        let intent = try StoreFixtures.ready(Fixtures.intent(title: "Comprar leche").updatingLocation(location))
        let sut = makeSUT()

        _ = try await sut.useCase.save(intent)

        XCTAssertEqual(sut.store.snapshot.createdReminders.first?.location, "Mercadona")
    }

    func testChosenReminderListIsUsed() async throws {
        let intent = try StoreFixtures.ready(Fixtures.intent())
        let sut = makeSUT()

        _ = try await sut.useCase.save(intent, options: SaveOptions(reminderListIdentifier: "lista-compra"))

        XCTAssertEqual(sut.store.snapshot.createdReminders.first?.listIdentifier, "lista-compra")
    }

    // MARK: - Eventos

    func testEventNeedsAnExplicitDurationBeforeAskingPermission() async throws {
        let intent = try StoreFixtures.ready(StoreFixtures.appointment(at: Fixtures.at(2026, 10, 9, 10)))
        let sut = makeSUT(events: .notDetermined)

        await assertSaveFails(.missingEventDuration) { try await sut.useCase.save(intent) }

        XCTAssertEqual(sut.store.totalRequests, 0, "Sin duración no se muestra el diálogo de permisos")
        XCTAssertTrue(sut.store.snapshot.createdEvents.isEmpty)
    }

    func testEventRejectsNonPositiveDuration() async throws {
        let intent = try StoreFixtures.ready(StoreFixtures.appointment(at: Fixtures.at(2026, 10, 9, 10)))
        let sut = makeSUT()

        for duration: TimeInterval in [0, -1_800, .infinity] {
            await assertSaveFails(.invalidEventDuration) {
                try await sut.useCase.save(intent, options: SaveOptions(eventDuration: duration))
            }
        }
        XCTAssertTrue(sut.store.snapshot.createdEvents.isEmpty)
    }

    func testEventStartsAtTheConfirmedTime() async throws {
        let intent = try StoreFixtures.ready(StoreFixtures.appointment(
            at: Fixtures.at(2026, 10, 9, 10),
            reminderPolicy: .at(Fixtures.at(2026, 10, 9, 9, 30))
        ))
        let sut = makeSUT()

        let outcome = try await sut.useCase.save(
            intent,
            options: SaveOptions(eventDuration: 3_600, calendarIdentifier: "cal-casa")
        )

        let draft = try XCTUnwrap(sut.store.snapshot.createdEvents.first)
        XCTAssertEqual(draft.start, Fixtures.instant("2026-10-09T10:00:00+02:00"))
        XCTAssertEqual(draft.end, Fixtures.instant("2026-10-09T11:00:00+02:00"))
        XCTAssertEqual(draft.timeZone, Fixtures.madrid)
        XCTAssertEqual(draft.calendarIdentifier, "cal-casa")
        XCTAssertEqual(draft.alarm, Fixtures.instant("2026-10-09T09:30:00+02:00"))
        XCTAssertEqual(outcome.record.reference.destination, .appleCalendar)
        XCTAssertEqual(outcome.record.alertChannel, .eventKitAlarm)
        XCTAssertTrue(sut.store.snapshot.createdReminders.isEmpty)
    }

    func testEventAfterDaylightSavingChangeUsesWallClockTime() async throws {
        // El 25 de octubre de 2026 Madrid vuelve a UTC+1.
        let intent = try StoreFixtures.ready(StoreFixtures.appointment(at: Fixtures.at(2026, 10, 25, 10)))
        let sut = makeSUT()

        _ = try await sut.useCase.save(intent, options: SaveOptions(eventDuration: 1_800))

        let draft = try XCTUnwrap(sut.store.snapshot.createdEvents.first)
        XCTAssertEqual(draft.start, Fixtures.instant("2026-10-25T10:00:00+01:00"))
        XCTAssertEqual(draft.end, Fixtures.instant("2026-10-25T10:30:00+01:00"))
    }

    func testAddingAnAlertToAnExistingEventIsNotSupportedYet() async throws {
        let reference = ExistingEventReference(userDescription: "mi cita", day: Fixtures.day(2026, 10, 9))
        let intent = try StoreFixtures.ready(Fixtures.intent(action: .addReminderToExistingEvent(reference)))
        let sut = makeSUT(events: .notDetermined)

        await assertSaveFails(.unsupportedAction) { try await sut.useCase.save(intent) }

        XCTAssertEqual(sut.store.totalRequests, 0)
    }

    // MARK: - Duplicados

    func testSavingTheSameIntentTwiceCreatesOneItem() async throws {
        let intent = try StoreFixtures.ready(Fixtures.intent(scheduledAt: .allDay(Fixtures.day(2026, 10, 9))))
        let sut = makeSUT()

        let first = try await sut.useCase.save(intent)
        let second = try await sut.useCase.save(intent)

        guard case .saved(let record) = first else { return XCTFail("Resultado inesperado: \(first)") }
        XCTAssertEqual(second, .alreadySaved(record))
        XCTAssertEqual(sut.store.snapshot.createdReminders.count, 1)
        XCTAssertEqual(sut.store.snapshot.checkedReferences, [record.reference])
    }

    func testDuplicatesAreDetectedByIdentifierNotByTitle() async throws {
        let day = TaskDate.allDay(Fixtures.day(2026, 10, 9))
        let first = try StoreFixtures.ready(StoreFixtures.task(id: Fixtures.fixedID, title: "Comprar pan", scheduledAt: day))
        let second = try StoreFixtures.ready(StoreFixtures.task(id: StoreFixtures.otherID, title: "Comprar pan", scheduledAt: day))
        let sut = makeSUT()

        _ = try await sut.useCase.save(first)
        let outcome = try await sut.useCase.save(second)

        guard case .saved = outcome else { return XCTFail("Resultado inesperado: \(outcome)") }
        XCTAssertEqual(sut.store.snapshot.createdReminders.count, 2, "Dos intenciones distintas pueden tener el mismo título")
        let records = await sut.registry.allRecords()
        XCTAssertEqual(records.count, 2)
    }

    func testDeletedItemIsNotRecreatedWithoutAskingTheUser() async throws {
        let intent = try StoreFixtures.ready(Fixtures.intent(scheduledAt: .allDay(Fixtures.day(2026, 10, 9))))
        let sut = makeSUT()
        let original = try await sut.useCase.save(intent).record
        sut.store.deleteItem(identifier: original.reference.identifier)

        let retry = try await sut.useCase.save(intent)

        XCTAssertEqual(retry, .previouslySavedButMissing(original))
        XCTAssertEqual(sut.store.snapshot.createdReminders.count, 1)

        let recreated = try await sut.useCase.save(intent, options: SaveOptions(recreateIfMissing: true))

        guard case .saved(let record) = recreated else { return XCTFail("Resultado inesperado: \(recreated)") }
        XCTAssertNotEqual(record.reference.identifier, original.reference.identifier)
        XCTAssertEqual(sut.store.snapshot.createdReminders.count, 2)
        let stored = await sut.registry.record(for: intent.id)
        XCTAssertEqual(stored, record, "El registro apunta al elemento nuevo")
    }

    func testUnreadableRegistryPreventsCreation() async throws {
        let intent = try StoreFixtures.ready(Fixtures.intent())
        let store = FakeEventStore(events: .fullAccess, reminders: .fullAccess)
        let useCase = SaveConfirmedTaskUseCase(
            access: store,
            calendar: store,
            reminders: store,
            presence: store,
            registry: FailingRegistry(),
            dates: Fixtures.dates()
        )

        do {
            let outcome = try await useCase.save(intent)
            XCTFail("Se esperaba un error y se obtuvo \(outcome)")
        } catch {
            guard case .registry? = error as? SaveError else {
                return XCTFail("Error inesperado: \(error)")
            }
        }
        XCTAssertTrue(store.snapshot.createdReminders.isEmpty, "Sin registro no se puede garantizar que no haya duplicados")
    }

    // MARK: - Permisos al guardar

    func testUndecidedPermissionIsRequestedOnceWhenSaving() async throws {
        let intent = try StoreFixtures.ready(Fixtures.intent())
        let sut = makeSUT(reminders: .notDetermined)
        sut.store.update { $0.answerToRequest[.reminders] = .fullAccess }

        let outcome = try await sut.useCase.save(intent)

        guard case .saved = outcome else { return XCTFail("Resultado inesperado: \(outcome)") }
        XCTAssertEqual(sut.store.requestCount(for: .reminders), 1)
        XCTAssertEqual(sut.store.requestCount(for: .events), 0)
    }

    func testDeniedPermissionStopsWithoutPrompting() async throws {
        let intent = try StoreFixtures.ready(Fixtures.intent())
        let sut = makeSUT(reminders: .denied)

        await assertSaveFails(.permission(.reminders, .denied)) { try await sut.useCase.save(intent) }

        XCTAssertEqual(sut.store.totalRequests, 0)
        XCTAssertTrue(sut.store.snapshot.createdReminders.isEmpty)
        let records = await sut.registry.allRecords()
        XCTAssertTrue(records.isEmpty)
    }

    func testUserDecliningThePromptStopsTheSave() async throws {
        let intent = try StoreFixtures.ready(Fixtures.intent())
        let sut = makeSUT(reminders: .notDetermined)
        sut.store.update { $0.answerToRequest[.reminders] = .denied }

        await assertSaveFails(.permission(.reminders, .denied)) { try await sut.useCase.save(intent) }

        XCTAssertEqual(sut.store.requestCount(for: .reminders), 1)
        XCTAssertTrue(sut.store.snapshot.createdReminders.isEmpty)
    }

    func testWriteOnlyCalendarAccessIsNotEnough() async throws {
        let intent = try StoreFixtures.ready(StoreFixtures.appointment(at: Fixtures.at(2026, 10, 9, 10)))
        let sut = makeSUT(events: .writeOnly)

        await assertSaveFails(.permission(.events, .writeOnly)) {
            try await sut.useCase.save(intent, options: SaveOptions(eventDuration: 3_600))
        }

        XCTAssertTrue(sut.store.snapshot.createdEvents.isEmpty)
    }

    func testStoreFailureLeavesNoRecord() async throws {
        let intent = try StoreFixtures.ready(Fixtures.intent())
        let sut = makeSUT()
        sut.store.update { $0.createFailure = EventStoreError.containerReadOnly(.reminders) }

        await assertSaveFails(.store(.containerReadOnly(.reminders))) { try await sut.useCase.save(intent) }

        let records = await sut.registry.allRecords()
        XCTAssertTrue(records.isEmpty)
    }
}
