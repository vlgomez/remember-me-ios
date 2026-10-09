import Foundation
import XCTest
@testable import RememberMeCore

final class ValidationTests: XCTestCase {
    private func makeUseCase(now: String = Fixtures.wednesdayMorning) -> InterpretTaskUseCase {
        InterpretTaskUseCase(parser: DeterministicSpanishParser(), context: Fixtures.parsing(now: now))
    }

    private let validator = TaskIntentValidator(dates: Fixtures.dates())

    // MARK: - Campos inferidos y vista previa

    func testInferredFieldsRequireConfirmation() async throws {
        let result = try await makeUseCase().interpret("Llamar al taller el viernes a las 10")
        let intent = try XCTUnwrap(result.intent)
        XCTAssertEqual(intent.validationState, .needsConfirmation)
        XCTAssertEqual(intent.fieldsPendingConfirmation, [.scheduledAt, .reminderPolicy])
        XCTAssertTrue(result.messages.contains(.info(.pendingConfirmation, field: .scheduledAt)))
    }

    func testConfirmingWithTheShownPreviewMakesItReady() async throws {
        let useCase = makeUseCase()
        let interpreted = try await useCase.interpret("Llamar al taller el viernes a las 10")
        let intent = try XCTUnwrap(interpreted.intent)

        let confirmed = try useCase.confirm(intent, shownIn: IntentPreview(showing: intent))
        let confirmedIntent = try XCTUnwrap(confirmed.intent)
        XCTAssertEqual(confirmedIntent.validationState, .readyToSave)
        XCTAssertEqual(confirmedIntent.scheduledAt?.confirmation, .confirmed)
        XCTAssertEqual(confirmedIntent.scheduledAt?.origin, .deterministicRule, "Confirmar no cambia el origen")
        XCTAssertTrue(confirmedIntent.fieldsPendingConfirmation.isEmpty)
    }

    func testPreviewOfAnOlderVersionCannotConfirm() async throws {
        let useCase = makeUseCase()
        let interpreted = try await useCase.interpret("Llamar al taller el viernes a las 10")
        let intent = try XCTUnwrap(interpreted.intent)
        let preview = IntentPreview(showing: intent)

        let edited = useCase.revalidate(intent.updatingTitle("Llamar al taller de Paco"))
        let editedIntent = try XCTUnwrap(edited.intent)
        XCTAssertEqual(editedIntent.validationState, .needsConfirmation)

        XCTAssertThrowsError(try useCase.confirm(editedIntent, shownIn: preview)) { error in
            XCTAssertEqual(error as? ConfirmationError, .previewDoesNotMatchIntent)
        }
    }

    func testCannotConfirmWhileClarificationIsPending() async throws {
        let useCase = makeUseCase()
        let interpreted = try await useCase.interpret("Llamar a mamá mañana a las 5")
        let intent = try XCTUnwrap(interpreted.intent)
        XCTAssertEqual(intent.validationState, .needsClarification)

        XCTAssertThrowsError(try useCase.confirm(intent, shownIn: IntentPreview(showing: intent))) { error in
            XCTAssertEqual(error as? ConfirmationError, .intentNotAwaitingConfirmation(.needsClarification))
        }
    }

    func testOnlyUserProvidedDataIsReadyWithoutConfirmation() async throws {
        let result = try await makeUseCase().interpret("Llamar al banco mañana")
        XCTAssertEqual(result.intent?.validationState, .readyToSave)
    }

    func testShoppingListItemIsReady() async throws {
        let result = try await makeUseCase().interpret("Añadir detergente a la lista de la compra")
        XCTAssertEqual(result.intent?.validationState, .readyToSave)
    }

    // MARK: - Reglas del validador

    func testExecutionAfterExclusiveDeadlineIsInvalid() {
        let deadline = Deadline(date: .allDay(Fixtures.day(2026, 11, 20)), boundary: .exclusive)
        let intent = Fixtures.intent(deadline: deadline, scheduledAt: .allDay(Fixtures.day(2026, 11, 20)))
        let result = validator.validate(intent)
        XCTAssertEqual(result.intent?.validationState, .invalid)
        XCTAssertTrue(result.messages.contains(.error(.scheduledAfterDeadline, field: .scheduledAt)))
    }

    func testExecutionOnInclusiveDeadlineIsValid() {
        let deadline = Deadline(date: .allDay(Fixtures.day(2026, 11, 20)), boundary: .inclusive)
        let intent = Fixtures.intent(deadline: deadline, scheduledAt: .allDay(Fixtures.day(2026, 11, 20)))
        let result = validator.validate(intent)
        XCTAssertEqual(result.intent?.validationState, .readyToSave)
    }

    func testPastDateIsAWarningNotAnError() {
        let intent = Fixtures.intent(scheduledAt: .allDay(Fixtures.day(2026, 10, 1)))
        let result = validator.validate(intent)
        XCTAssertTrue(result.messages.contains(.warning(.dateInPast, field: .scheduledAt)))
        XCTAssertEqual(result.intent?.validationState, .readyToSave)
    }

    func testNonexistentLocalTimeIsAnError() {
        let intent = Fixtures.intent(
            scheduledAt: .timed(Fixtures.at(2027, 3, 28, 2, 30)),
            timeZone: Fixtures.madrid
        )
        let result = validator.validate(intent)
        XCTAssertTrue(result.messages.contains(.error(.nonexistentLocalTime, field: .scheduledAt)))
        XCTAssertEqual(result.intent?.validationState, .invalid)
    }

    func testRepeatedLocalTimeIsAWarning() {
        let intent = Fixtures.intent(
            scheduledAt: .timed(Fixtures.at(2026, 10, 25, 2, 30)),
            timeZone: Fixtures.madrid
        )
        let result = validator.validate(intent)
        XCTAssertTrue(result.messages.contains(.warning(.repeatedLocalTime, field: .scheduledAt)))
    }

    func testTimedDateWithoutTimeZoneIsAnError() {
        let intent = Fixtures.intent(scheduledAt: .timed(Fixtures.at(2026, 10, 9, 10)))
        let result = validator.validate(intent)
        XCTAssertTrue(result.messages.contains(.error(.missingTimeZone, field: .timeZone)))
    }

    func testUseCaseFillsTheDeviceTimeZone() throws {
        let intent = Fixtures.intent(scheduledAt: .timed(Fixtures.at(2026, 10, 9, 10)))
        let result = makeUseCase().revalidate(intent)
        let revalidated = try XCTUnwrap(result.intent)
        XCTAssertEqual(revalidated.timeZone?.value, Fixtures.madrid)
        XCTAssertFalse(revalidated.timeZone?.needsConfirmation ?? true)
        XCTAssertEqual(revalidated.validationState, .readyToSave)
    }

    func testAllDayDateNeedsNoTimeZone() {
        let intent = Fixtures.intent(scheduledAt: .allDay(Fixtures.day(2026, 10, 9)))
        let result = validator.validate(intent)
        XCTAssertFalse(result.messages.contains { $0.code == .missingTimeZone })
        XCTAssertEqual(result.intent?.validationState, .readyToSave)
    }

    func testCalendarEventNeedsATime() {
        let intent = Fixtures.intent(
            kind: .appointment,
            action: .createCalendarEvent,
            scheduledAt: .allDay(Fixtures.day(2026, 10, 8))
        )
        let result = validator.validate(intent)
        XCTAssertTrue(result.messages.contains(.error(.calendarEventRequiresTime, field: .scheduledAt)))
        XCTAssertEqual(result.intent?.validationState, .invalid)
    }

    func testKindAndActionMustMatch() {
        let intent = Fixtures.intent(kind: .appointment, action: .createTask)
        let result = validator.validate(intent)
        XCTAssertTrue(result.messages.contains(.error(.actionKindMismatch, field: .action)))
    }

    func testEmptyTitleIsAnError() {
        let result = validator.validate(Fixtures.intent(title: "  "))
        XCTAssertTrue(result.messages.contains(.error(.emptyTitle, field: .title)))
    }

    func testReminderBeforeAllDayDeadlineAsksForTheTime() async throws {
        let result = try await makeUseCase().interpret("Comprar regalo tres días antes del 20 de noviembre")
        XCTAssertTrue(result.messages.contains(.info(.reminderNeedsTime, field: .reminderPolicy)))
        XCTAssertEqual(result.intent?.validationState, .needsConfirmation)
    }

    func testClarificationTakesPrecedenceOverErrors() async throws {
        let result = try await makeUseCase().interpret("Cita con el dentista el jueves")
        XCTAssertEqual(result.intent?.validationState, .needsClarification)
        XCTAssertTrue(result.messages.contains(.error(.calendarEventRequiresTime, field: .scheduledAt)))
    }
}
