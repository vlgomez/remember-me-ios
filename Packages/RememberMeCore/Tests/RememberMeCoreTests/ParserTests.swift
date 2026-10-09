import Foundation
import XCTest
@testable import RememberMeCore

/// Salvo que se indique otra cosa, "ahora" es el miércoles 7 de octubre de 2026 a las 09:00 en Madrid.
final class ParserTests: XCTestCase {
    private let parser = DeterministicSpanishParser()

    private func parse(_ text: String, now: String = Fixtures.wednesdayMorning) -> TaskParseResult {
        parser.parseImmediately(text, context: Fixtures.parsing(now: now))
    }

    private func reasons(_ result: TaskParseResult) -> [ClarificationReason] {
        result.clarifications.map { $0.reason }
    }

    // MARK: - Frases de ejemplo de la Fase A

    func testComprarLecheMananaIsAnAllDayExecutionDate() throws {
        let result = parse("Comprar leche mañana")
        let intent = try XCTUnwrap(result.intent)
        XCTAssertEqual(intent.title.value, "Comprar leche")
        XCTAssertEqual(intent.kind.value, .shopping)
        XCTAssertEqual(intent.kind.origin, .deterministicRule)
        XCTAssertEqual(intent.action.value, .createTask)
        XCTAssertEqual(intent.scheduledAt?.value, TaskDate.allDay(Fixtures.day(2026, 10, 8)))
        XCTAssertEqual(intent.scheduledAt?.origin, .userProvided)
        XCTAssertNil(intent.scheduledAt?.value.time, "No se inventa una hora")
        XCTAssertNil(intent.deadline)
        XCTAssertNil(intent.timeZone)
        XCTAssertEqual(intent.reminderPolicy.value, .noReminder)
        XCTAssertEqual(reasons(result), [])
    }

    func testLlamarAlTallerElViernesALas10() throws {
        let result = parse("Llamar al taller el viernes a las 10")
        let intent = try XCTUnwrap(result.intent)
        XCTAssertEqual(intent.title.value, "Llamar al taller")
        XCTAssertEqual(intent.kind.value, .task)
        XCTAssertEqual(intent.action.value, .createTask)
        XCTAssertEqual(intent.scheduledAt?.value, TaskDate.timed(Fixtures.at(2026, 10, 9, 10)))
        // Qué viernes y "10 de la mañana" son deducciones: quedan pendientes de confirmar.
        XCTAssertEqual(intent.scheduledAt?.origin, .deterministicRule)
        XCTAssertEqual(intent.scheduledAt?.confirmation, .pending)
        XCTAssertEqual(intent.timeZone?.value, Fixtures.madrid)
        XCTAssertEqual(intent.reminderPolicy.value, .at(Fixtures.at(2026, 10, 9, 10)))
        XCTAssertEqual(reasons(result), [])
    }

    func testComprarRegaloAntesDel20DeNoviembreIsADeadline() throws {
        let result = parse("Comprar regalo antes del 20 de noviembre")
        let intent = try XCTUnwrap(result.intent)
        XCTAssertEqual(intent.title.value, "Comprar regalo")
        XCTAssertEqual(intent.kind.value, .shopping)
        let deadline = try XCTUnwrap(intent.deadline)
        XCTAssertEqual(deadline.value.date, TaskDate.allDay(Fixtures.day(2026, 11, 20)))
        XCTAssertEqual(deadline.value.boundary, .exclusive)
        XCTAssertEqual(deadline.value.lastValidDay, Fixtures.day(2026, 11, 19))
        XCTAssertEqual(deadline.origin, .deterministicRule, "El año se ha deducido")
        XCTAssertNil(intent.scheduledAt, "Una fecha límite no es una fecha de ejecución")
        XCTAssertEqual(intent.reminderPolicy.value, .noReminder)
        XCTAssertEqual(reasons(result), [])
    }

    func testDeadlineWithExplicitYearIsUserProvided() throws {
        let intent = try XCTUnwrap(parse("Comprar regalo antes del 20 de noviembre de 2026").intent)
        XCTAssertEqual(intent.deadline?.value.date, TaskDate.allDay(Fixtures.day(2026, 11, 20)))
        XCTAssertEqual(intent.deadline?.origin, .userProvided)
    }

    func testAnadirDetergenteALaListaDeLaCompra() throws {
        let result = parse("Añadir detergente a la lista de la compra")
        let intent = try XCTUnwrap(result.intent)
        XCTAssertEqual(intent.title.value, "Detergente")
        XCTAssertEqual(intent.kind.value, .shopping)
        XCTAssertEqual(intent.kind.origin, .userProvided)
        XCTAssertEqual(intent.destination, .appleReminders)
        XCTAssertNil(intent.scheduledAt)
        XCTAssertNil(intent.deadline)
        XCTAssertEqual(reasons(result), [])
    }

    // MARK: - Fecha límite frente a fecha de ejecución

    func testParaElViernesIsAnInclusiveDeadline() throws {
        let intent = try XCTUnwrap(parse("Entregar el informe para el viernes").intent)
        XCTAssertEqual(intent.title.value, "Entregar el informe")
        XCTAssertEqual(intent.deadline?.value.date, TaskDate.allDay(Fixtures.day(2026, 10, 9)))
        XCTAssertEqual(intent.deadline?.value.boundary, .inclusive)
        XCTAssertNil(intent.scheduledAt)
    }

    func testLeadTimeBeforeDeadline() throws {
        let intent = try XCTUnwrap(parse("Comprar regalo tres días antes del 20 de noviembre").intent)
        XCTAssertEqual(intent.title.value, "Comprar regalo")
        XCTAssertEqual(intent.deadline?.value.date, TaskDate.allDay(Fixtures.day(2026, 11, 20)))
        XCTAssertEqual(intent.reminderPolicy.value, .beforeDeadline(.days(3)))
        XCTAssertEqual(intent.reminderPolicy.origin, .userProvided)
        XCTAssertNil(intent.scheduledAt)
    }

    // MARK: - Cambios de mes y de año

    func testRelativeDaysCrossMonth() throws {
        let intent = try XCTUnwrap(parse("Llamar a Luis dentro de 3 días", now: "2026-10-30T09:00:00+01:00").intent)
        XCTAssertEqual(intent.title.value, "Llamar a Luis")
        XCTAssertEqual(intent.scheduledAt?.value, TaskDate.allDay(Fixtures.day(2026, 11, 2)))
        XCTAssertEqual(intent.scheduledAt?.origin, .userProvided)
    }

    func testPasadoMananaCrossesYear() throws {
        let intent = try XCTUnwrap(parse("Renovar el DNI pasado mañana", now: "2026-12-31T10:00:00+01:00").intent)
        XCTAssertEqual(intent.title.value, "Renovar el DNI")
        XCTAssertEqual(intent.scheduledAt?.value, TaskDate.allDay(Fixtures.day(2027, 1, 2)))
    }

    func testDateWithoutYearRollsOverToNextYear() throws {
        let intent = try XCTUnwrap(parse("Pagar el seguro el 5 de enero", now: "2026-12-20T10:00:00+01:00").intent)
        XCTAssertEqual(intent.title.value, "Pagar el seguro")
        XCTAssertEqual(intent.scheduledAt?.value, TaskDate.allDay(Fixtures.day(2027, 1, 5)))
        XCTAssertEqual(intent.scheduledAt?.origin, .deterministicRule)
    }

    func testNumericDateIsDayMonth() throws {
        let intent = try XCTUnwrap(parse("Pagar el seguro el 5/1/2027").intent)
        XCTAssertEqual(intent.scheduledAt?.value, TaskDate.allDay(Fixtures.day(2027, 1, 5)))
        XCTAssertEqual(intent.scheduledAt?.origin, .userProvided)
    }

    // MARK: - Horario de verano

    func testThreeDaysLaterAcrossDaylightSavingKeepsTheHour() throws {
        // El 25 de octubre de 2026 cambia la hora en Madrid.
        let intent = try XCTUnwrap(
            parse("Llamar al banco dentro de tres días a las 10 de la mañana", now: "2026-10-23T09:00:00+02:00").intent
        )
        XCTAssertEqual(intent.title.value, "Llamar al banco")
        XCTAssertEqual(intent.scheduledAt?.value, TaskDate.timed(Fixtures.at(2026, 10, 26, 10)))
        XCTAssertEqual(intent.scheduledAt?.origin, .userProvided)
    }

    // MARK: - Ambigüedad

    func testWeekdaySaidTheSameDayIsAmbiguous() throws {
        let result = parse("Llamar al taller el viernes a las 10", now: Fixtures.fridayMorning)
        let intent = try XCTUnwrap(result.intent)
        XCTAssertNil(intent.scheduledAt)
        XCTAssertEqual(reasons(result), [.ambiguousDate])
        XCTAssertEqual(
            result.clarifications.first?.options,
            [TaskDate.timed(Fixtures.at(2026, 10, 9, 10)), TaskDate.timed(Fixtures.at(2026, 10, 16, 10))]
        )
    }

    func testProximoViernesWithinTheSameWeekIsAmbiguous() throws {
        let result = parse("Revisar el coche el próximo viernes")
        XCTAssertNil(try XCTUnwrap(result.intent).scheduledAt)
        XCTAssertEqual(reasons(result), [.ambiguousDate])
        XCTAssertEqual(
            result.clarifications.first?.options,
            [TaskDate.allDay(Fixtures.day(2026, 10, 9)), TaskDate.allDay(Fixtures.day(2026, 10, 16))]
        )
    }

    func testProximoViernesFromTheWeekendIsResolved() throws {
        let result = parse("Revisar el coche el próximo viernes", now: Fixtures.saturdayMorning)
        let intent = try XCTUnwrap(result.intent)
        XCTAssertEqual(intent.title.value, "Revisar el coche")
        XCTAssertEqual(intent.scheduledAt?.value, TaskDate.allDay(Fixtures.day(2026, 10, 16)))
        XCTAssertEqual(intent.scheduledAt?.origin, .deterministicRule)
        XCTAssertEqual(reasons(result), [])
    }

    func testHourWithoutPeriodIsAmbiguous() throws {
        let result = parse("Llamar a mamá mañana a las 5")
        let intent = try XCTUnwrap(result.intent)
        XCTAssertEqual(intent.title.value, "Llamar a mamá")
        XCTAssertNil(intent.scheduledAt)
        XCTAssertEqual(reasons(result), [.ambiguousTime])
        XCTAssertEqual(
            result.clarifications.first?.options,
            [TaskDate.timed(Fixtures.at(2026, 10, 8, 5)), TaskDate.timed(Fixtures.at(2026, 10, 8, 17))]
        )
    }

    func testHourWithPeriodIsResolved() throws {
        let result = parse("Llamar a mamá mañana a las 5 de la tarde")
        XCTAssertEqual(result.intent?.scheduledAt?.value, TaskDate.timed(Fixtures.at(2026, 10, 8, 17)))
        XCTAssertEqual(result.intent?.scheduledAt?.origin, .userProvided)
        XCTAssertEqual(reasons(result), [])
    }

    func testVaguePeriodClarifiesTheHour() throws {
        let result = parse("Llamar a mamá mañana por la tarde a las 5")
        XCTAssertEqual(result.intent?.scheduledAt?.value, TaskDate.timed(Fixtures.at(2026, 10, 8, 17)))
        XCTAssertEqual(reasons(result), [])
    }

    func testVaguePeriodAloneAsksForTheTime() throws {
        let result = parse("Recuérdame comprar leche en Mercadona esta tarde")
        let intent = try XCTUnwrap(result.intent)
        XCTAssertEqual(intent.title.value, "Comprar leche")
        XCTAssertNil(intent.scheduledAt, "No se inventa una hora para \"esta tarde\"")
        XCTAssertEqual(reasons(result), [.vagueTimeOfDay])
        XCTAssertEqual(result.clarifications.first?.knownDay, Fixtures.day(2026, 10, 7))
    }

    func testTimeWithoutDayLaterTodayIsInferredAsToday() throws {
        let result = parse("Llamar a las 18:00")
        XCTAssertEqual(result.intent?.scheduledAt?.value, TaskDate.timed(Fixtures.at(2026, 10, 7, 18)))
        XCTAssertEqual(result.intent?.scheduledAt?.origin, .deterministicRule, "El día se ha deducido")
        XCTAssertEqual(reasons(result), [])
    }

    func testTimeWithoutDayAlreadyPastAsksForTheDay() throws {
        let result = parse("Llamar a las 8:00")
        XCTAssertNil(result.intent?.scheduledAt)
        XCTAssertEqual(reasons(result), [.missingDate])
        XCTAssertEqual(result.clarifications.first?.options, [TaskDate.timed(Fixtures.at(2026, 10, 8, 8))])
    }

    func testNonexistentDateAsksForClarification() throws {
        let result = parse("Llamar el 31 de febrero")
        XCTAssertNil(try XCTUnwrap(result.intent).scheduledAt)
        XCTAssertEqual(reasons(result), [.invalidDate])
    }

    func testAppointmentWithoutTimeAsksForTheTime() throws {
        let result = parse("Cita con el dentista el jueves")
        let intent = try XCTUnwrap(result.intent)
        XCTAssertEqual(intent.kind.value, .appointment)
        XCTAssertEqual(intent.action.value, .createCalendarEvent)
        XCTAssertEqual(intent.scheduledAt?.value, TaskDate.allDay(Fixtures.day(2026, 10, 8)))
        XCTAssertEqual(reasons(result), [.missingTime])
        XCTAssertEqual(result.clarifications.first?.knownDay, Fixtures.day(2026, 10, 8))
    }

    func testOnlyADateAsksForTheTitle() throws {
        let result = parse("mañana a las 10 de la mañana")
        XCTAssertEqual(result.intent?.title.value, "")
        XCTAssertEqual(reasons(result), [.missingTitle])
    }

    // MARK: - Sin fecha

    func testTaskWithoutDateGetsNoDate() throws {
        let result = parse("Comprar pilas")
        let intent = try XCTUnwrap(result.intent)
        XCTAssertNil(intent.scheduledAt)
        XCTAssertNil(intent.deadline)
        XCTAssertNil(intent.timeZone)
        XCTAssertEqual(intent.reminderPolicy.value, .noReminder)
        XCTAssertEqual(reasons(result), [])
    }

    // MARK: - Ubicación

    func testLocationIsKeptAsTextWithoutGeocoding() throws {
        let intent = try XCTUnwrap(parse("Comprar camisa en El Corte Inglés").intent)
        XCTAssertEqual(intent.title.value, "Comprar camisa")
        XCTAssertEqual(intent.location?.value.text, "El Corte Inglés")
        XCTAssertEqual(intent.location?.origin, .deterministicRule, "Que sea un lugar es una deducción")
    }

    func testLocationFromReminderSentence() throws {
        let intent = try XCTUnwrap(parse("Recuérdame comprar leche en Mercadona esta tarde").intent)
        XCTAssertEqual(intent.location?.value.text, "Mercadona")
    }

    // MARK: - Entradas no admitidas

    func testEmptyInput() {
        let result = parse("   ")
        XCTAssertNil(result.intent)
        XCTAssertEqual(reasons(result), [.emptyInput])
    }

    func testAlertAboutAnExistingEventIsNotSupportedYet() {
        let result = parse("Avísame dos horas antes de mi cita del jueves")
        XCTAssertNil(result.intent, "No se crea una tarea nueva a partir de una petición sobre un evento existente")
        XCTAssertEqual(reasons(result), [.unsupportedExpression])
    }

    // MARK: - Protocolo

    func testParserCanBeUsedThroughTheProtocol() async throws {
        let anyParser: any TaskIntentParser = DeterministicSpanishParser()
        let result = try await anyParser.parse("Comprar leche mañana", context: Fixtures.parsing())
        XCTAssertEqual(result.intent?.id, TaskIntentID(Fixtures.fixedID))
    }
}
