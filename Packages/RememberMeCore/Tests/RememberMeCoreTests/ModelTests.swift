import Foundation
import XCTest
@testable import RememberMeCore

final class ModelTests: XCTestCase {

    // MARK: - TaskField

    func testUserProvidedFieldDoesNotNeedConfirmation() {
        let field = TaskField.userProvided("Llamar al taller")
        XCTAssertEqual(field.origin, .userProvided)
        XCTAssertEqual(field.confirmation, .notRequired)
        XCTAssertNil(field.confidence)
        XCTAssertFalse(field.needsConfirmation)
    }

    func testInferredFieldsNeedConfirmation() {
        let byRule = TaskField.deterministicRule(TaskKind.shopping, confidence: .high)
        let byAI = TaskField.aiInferred(TaskKind.appointment, confidence: .low)
        XCTAssertTrue(byRule.needsConfirmation)
        XCTAssertEqual(byRule.origin, .deterministicRule)
        XCTAssertEqual(byRule.confidence, .high)
        XCTAssertTrue(byAI.needsConfirmation)
        XCTAssertEqual(byAI.origin, .aiInferred)
    }

    func testRuleDefaultDoesNotNeedConfirmation() {
        let field = TaskField.ruleDefault(ReminderPolicy.noReminder)
        XCTAssertEqual(field.origin, .deterministicRule)
        XCTAssertFalse(field.needsConfirmation)
    }

    func testConfidenceRejectsValuesOutsideRange() {
        XCTAssertNil(Confidence(1.5))
        XCTAssertNil(Confidence(-0.1))
        XCTAssertNil(Confidence(.nan))
        XCTAssertEqual(Confidence(0.5)?.value, 0.5)
        XCTAssertLessThan(Confidence.low, Confidence.high)
    }

    // MARK: - TaskIntent

    func testNewIntentDefaults() {
        let intent = TaskIntent(
            id: TaskIntentID(Fixtures.fixedID),
            action: .ruleDefault(.createTask),
            title: .userProvided("Comprar pilas"),
            kind: .ruleDefault(.task)
        )
        XCTAssertEqual(intent.validationState, .notValidated)
        XCTAssertEqual(intent.reminderPolicy.value, .noReminder)
        XCTAssertFalse(intent.reminderPolicy.needsConfirmation)
        XCTAssertNil(intent.notes)
        XCTAssertNil(intent.deadline)
        XCTAssertNil(intent.scheduledAt)
        XCTAssertNil(intent.timeZone)
        XCTAssertNil(intent.location)
        XCTAssertEqual(intent.destination, .appleReminders)
        XCTAssertTrue(intent.fieldsPendingConfirmation.isEmpty)
        XCTAssertFalse(intent.requiresTimeZone)
    }

    func testActionDestinations() {
        XCTAssertEqual(TaskAction.createTask.destination, .appleReminders)
        XCTAssertEqual(TaskAction.createCalendarEvent.destination, .appleCalendar)
        let reference = ExistingEventReference(userDescription: "mi cita", day: Fixtures.day(2026, 10, 8))
        XCTAssertEqual(TaskAction.addReminderToExistingEvent(reference).destination, .appleCalendar)
    }

    func testUserEditMarksFieldAsUserProvidedAndResetsValidation() {
        let intent = Fixtures.intent()
            .updatingScheduledAt(.timed(Fixtures.at(2026, 10, 9, 10)))
        XCTAssertEqual(intent.scheduledAt?.origin, .userProvided)
        XCTAssertEqual(intent.scheduledAt?.confirmation, .notRequired)
        XCTAssertEqual(intent.validationState, .notValidated)
        XCTAssertEqual(intent.id, TaskIntentID(Fixtures.fixedID))
    }

    func testChangingKindToAppointmentChangesAction() {
        let intent = Fixtures.intent().updatingKind(.appointment)
        XCTAssertEqual(intent.kind.value, .appointment)
        XCTAssertEqual(intent.action.value, .createCalendarEvent)
        XCTAssertEqual(intent.destination, .appleCalendar)
    }

    func testCodableRoundTrip() throws {
        let mercadona = try XCTUnwrap(TaskLocation(text: "Mercadona"))
        let intent = TaskIntent(
            id: TaskIntentID(Fixtures.fixedID),
            action: .ruleDefault(.createTask),
            title: .userProvided("Comprar leche"),
            kind: .deterministicRule(.shopping, confidence: .high),
            deadline: .userProvided(Deadline(date: .allDay(Fixtures.day(2026, 11, 20)), boundary: .exclusive)),
            scheduledAt: .deterministicRule(.timed(Fixtures.at(2026, 10, 9, 10)), confidence: .medium),
            timeZone: .ruleDefault(Fixtures.madrid),
            location: .deterministicRule(mercadona, confidence: .medium),
            reminderPolicy: .userProvided(.beforeDeadline(.days(3)))
        )
        let data = try JSONEncoder().encode(intent)
        let decoded = try JSONDecoder().decode(TaskIntent.self, from: data)
        XCTAssertEqual(decoded, intent)
    }

    func testDecodingRejectsNonexistentDay() {
        let json = Data(#"{"year":2026,"month":2,"day":30}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(CalendarDay.self, from: json))
    }

    // MARK: - Fechas

    func testCalendarDayRejectsNonexistentDates() {
        XCTAssertNil(CalendarDay(year: 2026, month: 2, day: 29))
        XCTAssertNotNil(CalendarDay(year: 2028, month: 2, day: 29))
        XCTAssertNil(CalendarDay(year: 2026, month: 4, day: 31))
        XCTAssertNil(CalendarDay(year: 2026, month: 13, day: 1))
        XCTAssertNil(CalendarDay(year: 2026, month: 1, day: 0))
        XCTAssertNil(CalendarDay(year: 1900, month: 2, day: 29))
        XCTAssertNotNil(CalendarDay(year: 2000, month: 2, day: 29))
    }

    func testTimeOfDayRange() {
        XCTAssertNil(TimeOfDay(hour: 24))
        XCTAssertNil(TimeOfDay(hour: 10, minute: 60))
        XCTAssertNil(TimeOfDay(hour: -1))
        XCTAssertEqual(TimeOfDay(hour: 23, minute: 59)?.description, "23:59")
    }

    func testAllDayDateHasNoTime() {
        let date = TaskDate.allDay(Fixtures.day(2026, 11, 20))
        XCTAssertTrue(date.isAllDay)
        XCTAssertNil(date.time)
        XCTAssertNil(date.localDateTime)
        XCTAssertNotEqual(date, TaskDate.timed(Fixtures.at(2026, 11, 20, 0)))
    }

    func testDeadlineBoundary() {
        let november20 = TaskDate.allDay(Fixtures.day(2026, 11, 20))
        XCTAssertEqual(Deadline(date: november20, boundary: .exclusive).lastValidDay, Fixtures.day(2026, 11, 19))
        XCTAssertEqual(Deadline(date: november20, boundary: .inclusive).lastValidDay, Fixtures.day(2026, 11, 20))
        let midnight = TaskDate.timed(Fixtures.at(2026, 11, 20, 0))
        XCTAssertEqual(Deadline(date: midnight, boundary: .exclusive).lastValidDay, Fixtures.day(2026, 11, 19))
    }

    // MARK: - Ubicación

    func testLocationIsPlainTextWithoutCoordinates() throws {
        let location = try XCTUnwrap(TaskLocation(text: "  Mercadona "))
        XCTAssertEqual(location.text, "Mercadona")
        let storedProperties = Mirror(reflecting: location).children.compactMap { $0.label }
        XCTAssertEqual(storedProperties, ["text"], "TaskLocation solo debe guardar el texto del usuario")
        XCTAssertNil(TaskLocation(text: "   "))
    }
}
