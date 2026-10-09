import Foundation
import XCTest
@testable import RememberMeCore

final class ReminderRulesTests: XCTestCase {
    private let calculator = ReminderScheduleCalculator(dates: Fixtures.dates())

    func testDaysBeforeAllDayDeadlineGiveADayWithoutInventingATime() {
        let deadline = Deadline(date: .allDay(Fixtures.day(2026, 11, 20)), boundary: .exclusive)
        XCTAssertEqual(
            calculator.trigger(for: .beforeDeadline(.days(3)), deadline: deadline),
            .success(.dayWithoutTime(Fixtures.day(2026, 11, 17)))
        )
    }

    func testDaysBeforeTimedDeadlineKeepWallClockAcrossDaylightSaving() {
        // Del 27 al 24 de octubre se cruza el cambio de hora del 25: la hora de reloj se conserva.
        let deadline = Deadline(date: .timed(Fixtures.at(2026, 10, 27, 9)), boundary: .inclusive)
        XCTAssertEqual(
            calculator.trigger(for: .beforeDeadline(.days(3)), deadline: deadline),
            .success(.at(Fixtures.at(2026, 10, 24, 9)))
        )
    }

    func testHoursBeforeTimedDeadline() {
        let deadline = Deadline(date: .timed(Fixtures.at(2026, 10, 15, 10)), boundary: .inclusive)
        XCTAssertEqual(
            calculator.trigger(for: .beforeDeadline(.hours(2)), deadline: deadline),
            .success(.at(Fixtures.at(2026, 10, 15, 8)))
        )
        XCTAssertEqual(
            calculator.trigger(for: .beforeDeadline(.minutes(30)), deadline: deadline),
            .success(.at(Fixtures.at(2026, 10, 15, 9, 30)))
        )
    }

    func testHoursBeforeAllDayDeadlineAreRejected() {
        let deadline = Deadline(date: .allDay(Fixtures.day(2026, 11, 20)), boundary: .inclusive)
        XCTAssertEqual(
            calculator.trigger(for: .beforeDeadline(.hours(2)), deadline: deadline),
            .failure(.leadTimeRequiresTimedDeadline)
        )
    }

    func testLeadTimeWithoutDeadlineIsRejected() {
        XCTAssertEqual(calculator.trigger(for: .beforeDeadline(.days(1)), deadline: nil), .failure(.missingDeadline))
    }

    func testNonPositiveLeadTimeIsRejected() {
        let deadline = Deadline(date: .allDay(Fixtures.day(2026, 11, 20)), boundary: .inclusive)
        XCTAssertEqual(
            calculator.trigger(for: .beforeDeadline(.days(0)), deadline: deadline),
            .failure(.nonPositiveLeadTime)
        )
    }

    func testAbsoluteAndEmptyPolicies() {
        XCTAssertEqual(calculator.trigger(for: .noReminder, deadline: nil), .success(.noReminder))
        let moment = Fixtures.at(2026, 10, 9, 10)
        XCTAssertEqual(calculator.trigger(for: .at(moment), deadline: nil), .success(.at(moment)))
    }

    func testDefaultPolicy() {
        let timed = TaskDate.timed(Fixtures.at(2026, 10, 9, 10))
        let fromTimed = ReminderPolicyRules.defaultPolicy(scheduledAt: timed)
        XCTAssertEqual(fromTimed.value, .at(Fixtures.at(2026, 10, 9, 10)))
        XCTAssertTrue(fromTimed.needsConfirmation, "Proponer un aviso es una deducción")

        let fromAllDay = ReminderPolicyRules.defaultPolicy(scheduledAt: .allDay(Fixtures.day(2026, 10, 9)))
        XCTAssertEqual(fromAllDay.value, .noReminder, "No se inventa una hora para una fecha sin hora")
        XCTAssertFalse(fromAllDay.needsConfirmation)

        XCTAssertEqual(ReminderPolicyRules.defaultPolicy(scheduledAt: nil).value, .noReminder)
    }
}
