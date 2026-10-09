import Foundation
import XCTest
@testable import RememberMeCore

final class EventStoreAccessTests: XCTestCase {
    // MARK: - Solicitud de permisos

    func testRequestsAccessOnlyWhileUndecided() async throws {
        let store = FakeEventStore(events: .notDetermined)
        store.update { $0.answerToRequest[.events] = .fullAccess }
        let useCase = EventStoreAccessUseCase(access: store)

        let first = try await useCase.requestAccessIfNeeded(for: .events)
        XCTAssertEqual(first, .fullAccess)
        XCTAssertEqual(store.requestCount(for: .events), 1)

        let second = try await useCase.requestAccessIfNeeded(for: .events)
        XCTAssertEqual(second, .fullAccess)
        XCTAssertEqual(store.requestCount(for: .events), 1, "Con el permiso ya decidido no se vuelve a preguntar")
    }

    func testDecidedStatesNeverShowTheSystemPrompt() async throws {
        for permission in [EventStorePermission.denied, .restricted, .writeOnly, .fullAccess] {
            let store = FakeEventStore(events: permission, reminders: permission)
            let useCase = EventStoreAccessUseCase(access: store)

            let events = try await useCase.requestAccessIfNeeded(for: .events)
            let reminders = try await useCase.requestAccessIfNeeded(for: .reminders)

            XCTAssertEqual(events, permission)
            XCTAssertEqual(reminders, permission)
            XCTAssertEqual(store.totalRequests, 0, "\(permission)")
        }
    }

    func testUserCanDeclineThePrompt() async throws {
        let store = FakeEventStore(reminders: .notDetermined)
        store.update { $0.answerToRequest[.reminders] = .denied }

        let result = try await EventStoreAccessUseCase(access: store).requestAccessIfNeeded(for: .reminders)

        XCTAssertEqual(result, .denied)
        XCTAssertEqual(store.requestCount(for: .reminders), 1)
    }

    func testCalendarAndRemindersPermissionsAreIndependent() async throws {
        let store = FakeEventStore(events: .fullAccess, reminders: .notDetermined)
        store.update { $0.answerToRequest[.reminders] = .denied }
        let useCase = EventStoreAccessUseCase(access: store)

        XCTAssertEqual(useCase.permission(for: .events), .fullAccess)
        XCTAssertEqual(useCase.permission(for: .reminders), .notDetermined)

        _ = try await useCase.requestAccessIfNeeded(for: .reminders)

        XCTAssertEqual(useCase.permission(for: .events), .fullAccess, "Denegar Reminders no afecta a Calendar")
        XCTAssertEqual(useCase.permission(for: .reminders), .denied)
        XCTAssertEqual(store.requestCount(for: .events), 0)
    }

    func testUnexpectedRequestErrorsAreWrapped() async {
        let store = FakeEventStore(events: .notDetermined)
        store.update { $0.requestFailure = UnexpectedStoreError() }

        do {
            _ = try await EventStoreAccessUseCase(access: store).requestAccessIfNeeded(for: .events)
            XCTFail("Se esperaba un error")
        } catch {
            XCTAssertEqual(error as? EventStoreError, .operationFailed("fallo inesperado"))
        }
    }

    // MARK: - Explicaciones para la interfaz

    func testGuidanceOffersTheRightActionForEachState() {
        let expected: [EventStorePermission: (AccessAction, String?)] = [
            .notDetermined: (.requestAccess, "Permitir acceso"),
            .fullAccess: (.noAction, nil),
            .writeOnly: (.openSettings, "Abrir Ajustes"),
            .denied: (.openSettings, "Abrir Ajustes"),
            .restricted: (.noAction, nil)
        ]
        XCTAssertEqual(Set(expected.keys), Set(EventStorePermission.allCases))

        for entity in EventStoreEntity.allCases {
            for (permission, (action, actionTitle)) in expected {
                let guidance = AccessGuidance(entity: entity, permission: permission)
                XCTAssertEqual(guidance.action, action, "\(entity) \(permission)")
                XCTAssertEqual(guidance.actionTitle, actionTitle, "\(entity) \(permission)")
                XCTAssertFalse(guidance.title.isEmpty)
                XCTAssertFalse(guidance.message.isEmpty)
            }
        }
    }

    func testGuidanceNamesTheRightApp() {
        let calendar = AccessGuidance(entity: .events, permission: .denied)
        let reminders = AccessGuidance(entity: .reminders, permission: .denied)

        XCTAssertTrue(calendar.title.contains("calendario"), calendar.title)
        XCTAssertTrue(reminders.title.contains("Recordatorios"), reminders.title)
        XCTAssertTrue(calendar.message.contains("Ajustes"), "Al denegar hay que explicar dónde activarlo")
    }

    func testOnlyFullAccessAllowsReadingAndWriting() {
        let allowed = EventStorePermission.allCases.filter(\.allowsReadingAndWriting)
        XCTAssertEqual(allowed, [.fullAccess])
    }
}
