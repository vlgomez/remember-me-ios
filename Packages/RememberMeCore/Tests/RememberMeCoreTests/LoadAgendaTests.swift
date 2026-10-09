import Foundation
import XCTest
@testable import RememberMeCore

final class LoadAgendaTests: XCTestCase {
    private func makeAgenda(_ store: FakeEventStore) -> LoadAgendaUseCase {
        LoadAgendaUseCase(access: store, calendar: store, dates: Fixtures.dates())
    }

    // MARK: - Permisos

    func testAgendaNeverRequestsPermissionByItself() async {
        let store = FakeEventStore(events: .notDetermined)

        let state = await makeAgenda(store).load()

        XCTAssertEqual(state, .needsPermission)
        XCTAssertEqual(store.totalRequests, 0)
        XCTAssertTrue(store.snapshot.queriedIntervals.isEmpty)
    }

    func testAgendaWithoutFullAccessIsUnavailable() async {
        for permission in [EventStorePermission.denied, .restricted, .writeOnly] {
            let store = FakeEventStore(events: permission)

            let state = await makeAgenda(store).load()

            XCTAssertEqual(state, .unavailable(permission))
            XCTAssertEqual(store.totalRequests, 0)
            XCTAssertTrue(store.snapshot.queriedIntervals.isEmpty, "Sin acceso total no se consulta Calendar")
        }
    }

    // MARK: - Consulta

    func testEmptyAgendaCoversTheNextSevenLocalDays() async {
        let store = FakeEventStore(events: .fullAccess)

        let state = await makeAgenda(store).load(days: 7)

        let expected = DateInterval(
            start: Fixtures.instant("2026-10-07T00:00:00+02:00"),
            end: Fixtures.instant("2026-10-14T00:00:00+02:00")
        )
        XCTAssertEqual(state, .empty(expected))
        XCTAssertEqual(store.snapshot.queriedIntervals, [expected])
    }

    func testIntervalFollowsDaylightSavingChanges() async {
        // El 25 de octubre de 2026 termina el horario de verano en Madrid: ese día dura 25 horas.
        let store = FakeEventStore(events: .fullAccess)
        let agenda = LoadAgendaUseCase(
            access: store,
            calendar: store,
            dates: Fixtures.dates(now: "2026-10-24T12:00:00+02:00")
        )

        _ = await agenda.load(days: 2)

        XCTAssertEqual(store.snapshot.queriedIntervals, [
            DateInterval(
                start: Fixtures.instant("2026-10-24T00:00:00+02:00"),
                end: Fixtures.instant("2026-10-26T00:00:00+01:00")
            )
        ])
    }

    func testEventsAreGroupedByLocalDayAndSorted() async throws {
        let store = FakeEventStore(events: .fullAccess)
        store.update {
            $0.events = [
                StoreFixtures.event("Dentista", start: "2026-10-08T10:00:00+02:00", end: "2026-10-08T11:00:00+02:00"),
                StoreFixtures.event("Café", start: "2026-10-08T08:30:00+02:00", end: "2026-10-08T09:00:00+02:00"),
                StoreFixtures.event(
                    "Festivo",
                    start: "2026-10-08T00:00:00+02:00",
                    end: "2026-10-09T00:00:00+02:00",
                    allDay: true
                ),
                // 00:30 en Madrid es todavía el día 7 en UTC: debe agruparse en el día 8 local.
                StoreFixtures.event("Guardia", start: "2026-10-08T00:30:00+02:00", end: "2026-10-08T01:00:00+02:00"),
                // Empezó ayer y sigue hoy: aparece en el primer día de la agenda.
                StoreFixtures.event("Viaje", start: "2026-10-06T18:00:00+02:00", end: "2026-10-07T10:00:00+02:00")
            ]
        }

        let state = await makeAgenda(store).load()

        guard case .loaded(let days) = state else {
            return XCTFail("Estado inesperado: \(state)")
        }
        XCTAssertEqual(days.map(\.day), [Fixtures.day(2026, 10, 7), Fixtures.day(2026, 10, 8)])
        XCTAssertEqual(days[0].events.map(\.title), ["Viaje"])
        XCTAssertEqual(days[1].events.map(\.title), ["Festivo", "Guardia", "Café", "Dentista"])
    }

    func testStoreErrorsAreReported() async {
        let store = FakeEventStore(events: .fullAccess)
        store.update { $0.readFailure = EventStoreError.operationFailed("sin conexión") }

        let state = await makeAgenda(store).load()

        XCTAssertEqual(state, .failed(.operationFailed("sin conexión")))
    }

    func testUnexpectedErrorsAreWrapped() async {
        let store = FakeEventStore(events: .fullAccess)
        store.update { $0.readFailure = UnexpectedStoreError() }

        let state = await makeAgenda(store).load()

        XCTAssertEqual(state, .failed(.operationFailed("fallo inesperado")))
    }

    // MARK: - Listas de Reminders

    func testReminderListsNeverRequestPermissionByThemselves() async {
        let store = FakeEventStore(reminders: .notDetermined)

        let state = await LoadReminderListsUseCase(access: store, reminders: store).load()

        XCTAssertEqual(state, .needsPermission)
        XCTAssertEqual(store.totalRequests, 0)
        XCTAssertEqual(store.snapshot.listQueries, 0)
    }

    func testReminderListsWithoutAccessAreUnavailable() async {
        let store = FakeEventStore(reminders: .denied)

        let state = await LoadReminderListsUseCase(access: store, reminders: store).load()

        XCTAssertEqual(state, .unavailable(.denied))
        XCTAssertEqual(store.snapshot.listQueries, 0)
    }

    func testDefaultReminderListComesFirst() async {
        let store = FakeEventStore(reminders: .fullAccess)
        store.update {
            $0.lists = [
                ReminderListSnapshot(id: "3", title: "Trabajo", isDefault: false, allowsModifications: true),
                ReminderListSnapshot(id: "2", title: "Compra", isDefault: false, allowsModifications: true),
                ReminderListSnapshot(id: "1", title: "Recordatorios", isDefault: true, allowsModifications: true)
            ]
        }

        let state = await LoadReminderListsUseCase(access: store, reminders: store).load()

        guard case .loaded(let lists) = state else {
            return XCTFail("Estado inesperado: \(state)")
        }
        XCTAssertEqual(lists.map(\.title), ["Recordatorios", "Compra", "Trabajo"])
    }

    func testNoReminderListsIsEmpty() async {
        let store = FakeEventStore(reminders: .fullAccess)

        let state = await LoadReminderListsUseCase(access: store, reminders: store).load()

        XCTAssertEqual(state, .empty)
    }
}
