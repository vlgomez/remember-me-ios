import Foundation
import XCTest
@testable import RememberMeCore

/// Registro en memoria con fallos programables para simular un disco lleno o un error de escritura.
actor FlakyRegistry: SavedItemRegistry {
    struct Failure: Error, CustomStringConvertible {
        var description: String { "fallo de escritura simulado" }
    }

    private let inner = InMemorySavedItemRegistry()
    /// Número de llamadas a `save` que fallarán a partir de ahora.
    private var failingSaves: Int

    init(failingSaves: Int = 0) {
        self.failingSaves = failingSaves
    }

    func record(for intentID: TaskIntentID) async throws -> SavedItemRecord? {
        await inner.record(for: intentID)
    }

    func save(_ record: SavedItemRecord) async throws {
        if failingSaves > 0 {
            failingSaves -= 1
            throw Failure()
        }
        await inner.save(record)
    }
}

/// EventKit crea el elemento, pero la referencia no llega a guardarse en el registro local.
/// "Ahora" es el miércoles 7 de octubre de 2026, 09:00 en Madrid.
final class SaveRecoveryTests: XCTestCase {

    func testRetryAfterRegistryWriteFailureDoesNotCreateADuplicate() async throws {
        let intent = try StoreFixtures.ready(Fixtures.intent(scheduledAt: .allDay(Fixtures.day(2026, 10, 9))))
        let store = FakeEventStore(events: .fullAccess, reminders: .fullAccess)
        let registry = FlakyRegistry(failingSaves: 1)
        let useCase = SaveConfirmedTaskUseCase(
            access: store,
            calendar: store,
            reminders: store,
            presence: store,
            registry: registry,
            dates: Fixtures.dates()
        )

        do {
            let outcome = try await useCase.save(intent)
            XCTFail("Se esperaba un error controlado y se obtuvo \(outcome)")
        } catch {
            XCTAssertNotNil(error as? SaveError, "Error no controlado: \(error)")
        }
        XCTAssertEqual(store.snapshot.createdReminders.count, 1, "EventKit sí creó el recordatorio")

        // El usuario vuelve a pulsar "Guardar" y el registro ya funciona.
        _ = try? await useCase.save(intent)

        XCTAssertEqual(
            store.snapshot.createdReminders.count,
            1,
            "El reintento no debe crear otro recordatorio"
        )
    }
}
