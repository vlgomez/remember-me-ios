import Foundation
import XCTest
@testable import RememberMeCore

final class DateTests: XCTestCase {

    // MARK: - Aritmética de días de calendario

    func testAddingDaysAcrossMonthAndYear() {
        XCTAssertEqual(Fixtures.day(2026, 1, 31).adding(days: 1), Fixtures.day(2026, 2, 1))
        XCTAssertEqual(Fixtures.day(2026, 10, 30).adding(days: 3), Fixtures.day(2026, 11, 2))
        XCTAssertEqual(Fixtures.day(2026, 12, 31).adding(days: 1), Fixtures.day(2027, 1, 1))
        XCTAssertEqual(Fixtures.day(2027, 1, 1).adding(days: -1), Fixtures.day(2026, 12, 31))
        XCTAssertEqual(Fixtures.day(2028, 2, 28).adding(days: 1), Fixtures.day(2028, 2, 29))
        XCTAssertEqual(Fixtures.day(2028, 3, 1).adding(days: -1), Fixtures.day(2028, 2, 29))
        XCTAssertEqual(Fixtures.day(2026, 2, 28).adding(days: 1), Fixtures.day(2026, 3, 1))
        XCTAssertEqual(Fixtures.day(2026, 10, 9).days(until: Fixtures.day(2027, 10, 9)), 365)
    }

    func testWeekdays() {
        XCTAssertEqual(Fixtures.day(1970, 1, 1).weekday, .thursday)
        XCTAssertEqual(Fixtures.day(2000, 1, 1).weekday, .saturday)
        XCTAssertEqual(Fixtures.day(2026, 10, 9).weekday, .friday)
        XCTAssertEqual(Fixtures.day(2027, 1, 1).weekday, .friday)
        XCTAssertEqual(Fixtures.day(1969, 12, 31).weekday, .wednesday)
        XCTAssertEqual(Fixtures.day(2026, 10, 9).startOfISOWeek, Fixtures.day(2026, 10, 5))
        XCTAssertEqual(Fixtures.day(2026, 10, 11).startOfISOWeek, Fixtures.day(2026, 10, 5))
    }

    /// La aritmética propia debe coincidir con la de Foundation durante varios años.
    func testDayArithmeticMatchesFoundation() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Fixtures.utc
        let base = Fixtures.day(2024, 1, 1)
        let baseDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 12)))

        for offset in -800...1_600 {
            let shifted = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: baseDate))
            let components = calendar.dateComponents([.year, .month, .day, .weekday], from: shifted)
            let year = try XCTUnwrap(components.year)
            let month = try XCTUnwrap(components.month)
            let dayNumber = try XCTUnwrap(components.day)
            let expected = try XCTUnwrap(CalendarDay(year: year, month: month, day: dayNumber))
            let actual = base.adding(days: offset)
            XCTAssertEqual(actual, expected, "Desfase de \(offset) días")
            // Foundation: 1 = domingo ... 7 = sábado. ISO: 1 = lunes ... 7 = domingo.
            let foundationWeekday = try XCTUnwrap(components.weekday)
            let isoWeekday = foundationWeekday == 1 ? 7 : foundationWeekday - 1
            XCTAssertEqual(actual.weekday.rawValue, isoWeekday, "Día de la semana de \(actual)")
        }
    }

    // MARK: - Contexto inyectable

    func testTodayUsesInjectedTimeZone() {
        let instant = "2026-10-09T23:30:00Z"
        XCTAssertEqual(Fixtures.dates(now: instant, timeZone: Fixtures.madrid).today(), Fixtures.day(2026, 10, 10))
        XCTAssertEqual(Fixtures.dates(now: instant, timeZone: Fixtures.utc).today(), Fixtures.day(2026, 10, 9))
    }

    func testDateContextRejectsNonGregorianCalendar() {
        XCTAssertThrowsError(
            try DateContext(
                dateProvider: SystemDateProvider(),
                calendar: Calendar(identifier: .buddhist),
                timeZone: Fixtures.madrid
            )
        ) { error in
            XCTAssertEqual(error as? DateContext.ConfigurationError, .calendarMustBeGregorian)
        }
    }

    func testExactLocalTime() {
        let dates = Fixtures.dates()
        XCTAssertEqual(
            dates.resolve(Fixtures.at(2026, 10, 9, 10)),
            .exact(Fixtures.instant("2026-10-09T10:00:00+02:00"))
        )
    }

    // MARK: - Día completo frente a medianoche

    func testAllDayIntervalLengthFollowsDaylightSavingTime() {
        let dates = Fixtures.dates()
        XCTAssertEqual(dates.interval(for: Fixtures.day(2026, 10, 9)).duration, 24 * 3_600)
        // 25 de octubre de 2026: fin del horario de verano en Madrid (el día dura 25 horas).
        XCTAssertEqual(dates.interval(for: Fixtures.day(2026, 10, 25)).duration, 25 * 3_600)
        // 28 de marzo de 2027: inicio del horario de verano (el día dura 23 horas).
        XCTAssertEqual(dates.interval(for: Fixtures.day(2027, 3, 28)).duration, 23 * 3_600)
        XCTAssertEqual(dates.interval(for: Fixtures.day(2026, 10, 9)).start, Fixtures.instant("2026-10-09T00:00:00+02:00"))
    }

    // MARK: - Horario de verano

    func testThreeCalendarDaysAcrossDaylightSavingKeepWallClock() throws {
        let dates = Fixtures.dates()
        let start = Fixtures.at(2026, 10, 23, 10)
        let end = dates.adding(days: 3, to: start)
        XCTAssertEqual(end, Fixtures.at(2026, 10, 26, 10))

        let startInstant = try XCTUnwrap(dates.instant(for: start))
        let endInstant = try XCTUnwrap(dates.instant(for: end))
        // Tres días de calendario son 73 horas reales porque el 25 de octubre dura 25 horas.
        XCTAssertEqual(endInstant.timeIntervalSince(startInstant), 3 * 24 * 3_600 + 3_600)
    }

    func testNonexistentLocalTimeWhenClocksGoForward() {
        let dates = Fixtures.dates()
        // 28 de marzo de 2027: de 02:00 se pasa a 03:00.
        XCTAssertEqual(dates.resolve(Fixtures.at(2027, 3, 28, 2, 30)), .nonexistent)
        XCTAssertNil(dates.instant(for: Fixtures.at(2027, 3, 28, 2, 30)))
    }

    func testRepeatedLocalTimeWhenClocksGoBack() {
        let dates = Fixtures.dates()
        // 25 de octubre de 2026: de 03:00 se vuelve a 02:00, así que las 02:30 ocurren dos veces.
        XCTAssertEqual(
            dates.resolve(Fixtures.at(2026, 10, 25, 2, 30)),
            .repeated(
                earlier: Fixtures.instant("2026-10-25T02:30:00+02:00"),
                later: Fixtures.instant("2026-10-25T02:30:00+01:00")
            )
        )
    }
}
