import Foundation
import XCTest
@testable import RememberMeCore

/// Registro en memoria con fallos programables para simular un disco lleno o un error de escritura.
actor FlakyRegistry: SavedItemRegistry {
    struct Failure: Error, CustomStringConvertible {
        var description: String { "fallo de escritura simulado" }
    }

    let inner: InMemorySavedItemRegistry
    /// Número de llamadas a `save` que fallarán a partir de ahora.
    private var failingSaves: Int
    private var failMarkPending: Bool
    private var failClearPending: Bool

    init(
        inner: InMemorySavedItemRegistry = InMemorySavedItemRegistry(),
        failingSaves: Int = 0,
        failMarkPending: Bool = false,
        failClearPending: Bool = false
    ) {
        self.inner = inner
        self.failingSaves = failingSaves
        self.failMarkPending = failMarkPending
        self.failClearPending = failClearPending
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

    func pendingCreation(for intentID: TaskIntentID) async throws -> PendingCreation? {
        await inner.pendingCreation(for: intentID)
    }

    func markPending(_ pending: PendingCreation) async throws {
        if failMarkPending {
            throw Failure()
        }
        await inner.markPending(pending)
    }

    func clearPending(for intentID: TaskIntentID) async throws {
        if failClearPending {
            throw Failure()
        }
        await inner.clearPending(for: intentID)
    }
}

/// EventKit crea el elemento, pero la referencia no llega a guardarse en el registro local.
/// "Ahora" es el miércoles 7 de octubre de 2026, 09:00 en Madrid.
final class SaveRecoveryTests: XCTestCase {
    private struct SUT {
        let useCase: SaveConfirmedTaskUseCase
        let store: FakeEventStore
        let registry: FlakyRegistry
    }

    private func makeSUT(registry: FlakyRegistry, store: FakeEventStore? = nil) -> SUT {
        let store = store ?? FakeEventStore(events: .fullAccess, reminders: .fullAccess)
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

    /// Simula que la app se cierra y se abre de nuevo: mismo disco y mismo EventKit, pero
    /// un caso de uso nuevo sin nada en memoria.
    private func relaunch(_ sut: SUT) -> SUT {
        makeSUT(registry: sut.registry, store: sut.store)
    }

    private func reminderIntent() throws -> TaskIntent {
        try StoreFixtures.ready(Fixtures.intent(title: "Comprar pilas", scheduledAt: .allDay(Fixtures.day(2026, 10, 9))))
    }

    /// Ejecuta el guardado esperando un error y lo devuelve.
    private func saveError(
        _ operation: () async throws -> SaveOutcome,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> SaveError? {
        do {
            let outcome = try await operation()
            XCTFail("Se esperaba un error y se obtuvo \(outcome)", file: file, line: line)
            return nil
        } catch {
            let saveError = error as? SaveError
            XCTAssertNotNil(saveError, "Error no controlado: \(error)", file: file, line: line)
            return saveError
        }
    }

    // MARK: - Reproducción del fallo original

    func testRetryAfterRegistryWriteFailureDoesNotCreateADuplicate() async throws {
        let intent = try reminderIntent()
        let sut = makeSUT(registry: FlakyRegistry(failingSaves: 1))

        _ = await saveError { try await sut.useCase.save(intent) }
        XCTAssertEqual(sut.store.snapshot.createdReminders.count, 1, "EventKit sí creó el recordatorio")

        // El usuario vuelve a pulsar "Guardar" y el registro ya funciona.
        _ = try? await sut.useCase.save(intent)

        XCTAssertEqual(
            sut.store.snapshot.createdReminders.count,
            1,
            "El reintento no debe crear otro recordatorio"
        )
    }

    // MARK: - Error controlado

    func testRegistryFailureAfterCreatingReturnsTheCreatedReference() async throws {
        let intent = try reminderIntent()
        let sut = makeSUT(registry: FlakyRegistry(failingSaves: 1))

        let error = await saveError { try await sut.useCase.save(intent) }

        guard case .createdButNotRegistered(let record)? = error else {
            return XCTFail("Error inesperado: \(String(describing: error))")
        }
        XCTAssertEqual(record.intentID, intent.id)
        XCTAssertEqual(record.reference, StoredItemReference(destination: .appleReminders, identifier: "reminder-1", externalIdentifier: nil))
        let stored = await sut.registry.inner.record(for: intent.id)
        XCTAssertNil(stored, "La referencia no llegó a guardarse")
        let pending = await sut.registry.inner.pendingCreation(for: intent.id)
        XCTAssertEqual(pending?.intentID, intent.id, "La marca del intento sigue en disco")
        XCTAssertEqual(pending?.title, "Comprar pilas")
        XCTAssertEqual(pending?.destination, .appleReminders)
    }

    func testEventCreatedButNotRegisteredIsReportedToo() async throws {
        let intent = try StoreFixtures.ready(StoreFixtures.appointment(at: Fixtures.at(2026, 10, 9, 10)))
        let sut = makeSUT(registry: FlakyRegistry(failingSaves: 1))
        let options = SaveOptions(eventDuration: 3_600)

        let error = await saveError { try await sut.useCase.save(intent, options: options) }
        guard case .createdButNotRegistered(let record)? = error else {
            return XCTFail("Error inesperado: \(String(describing: error))")
        }
        XCTAssertEqual(record.reference.destination, .appleCalendar)

        let retry = try await sut.useCase.save(intent, options: options)

        XCTAssertEqual(retry, .registrationRecovered(record))
        XCTAssertEqual(sut.store.snapshot.createdEvents.count, 1)
    }

    // MARK: - Recuperación en la misma sesión

    func testRetryInTheSameSessionOnlyCompletesTheRegistration() async throws {
        let intent = try reminderIntent()
        let sut = makeSUT(registry: FlakyRegistry(failingSaves: 1))
        let error = await saveError { try await sut.useCase.save(intent) }
        guard case .createdButNotRegistered(let created)? = error else {
            return XCTFail("Error inesperado: \(String(describing: error))")
        }

        let retry = try await sut.useCase.save(intent)

        XCTAssertEqual(retry, .registrationRecovered(created))
        XCTAssertEqual(sut.store.snapshot.createdReminders.count, 1)
        let stored = await sut.registry.inner.record(for: intent.id)
        XCTAssertEqual(stored, created)
        let pending = await sut.registry.inner.allPending()
        XCTAssertTrue(pending.isEmpty, "Registrar borra la marca del intento")

        // A partir de aquí, el flujo normal: ya estaba guardado.
        let third = try await sut.useCase.save(intent)
        XCTAssertEqual(third, .alreadySaved(created))
        XCTAssertEqual(sut.store.snapshot.createdReminders.count, 1)
    }

    func testRetryWhileTheRegistryStillFailsNeverCreatesAgain() async throws {
        let intent = try reminderIntent()
        let sut = makeSUT(registry: FlakyRegistry(failingSaves: 2))

        let first = await saveError { try await sut.useCase.save(intent) }
        let second = await saveError { try await sut.useCase.save(intent) }

        guard case .createdButNotRegistered(let created)? = first else {
            return XCTFail("Error inesperado: \(String(describing: first))")
        }
        XCTAssertEqual(second, .createdButNotRegistered(created))
        XCTAssertEqual(sut.store.snapshot.createdReminders.count, 1)

        let third = try await sut.useCase.save(intent)
        XCTAssertEqual(third, .registrationRecovered(created))
        XCTAssertEqual(sut.store.snapshot.createdReminders.count, 1)
    }

    func testItemDeletedBeforeTheRecoveryIsNotRecreatedWithoutConfirmation() async throws {
        let intent = try reminderIntent()
        let sut = makeSUT(registry: FlakyRegistry(failingSaves: 1))
        let error = await saveError { try await sut.useCase.save(intent) }
        guard case .createdButNotRegistered(let created)? = error else {
            return XCTFail("Error inesperado: \(String(describing: error))")
        }
        sut.store.deleteItem(identifier: created.reference.identifier)

        let retry = try await sut.useCase.save(intent)

        XCTAssertEqual(retry, .previouslySavedButMissing(created))
        XCTAssertEqual(sut.store.snapshot.createdReminders.count, 1)

        let recreated = try await sut.useCase.save(intent, options: SaveOptions(recreateIfMissing: true))
        guard case .saved(let record) = recreated else { return XCTFail("Resultado inesperado: \(recreated)") }
        XCTAssertNotEqual(record.reference, created.reference)
        XCTAssertEqual(sut.store.snapshot.createdReminders.count, 2, "Solo se recrea con confirmación explícita")
    }

    // MARK: - Reconciliación tras reiniciar la app

    func testAfterRelaunchAnUnconfirmedAttemptIsNotRetriedBlindly() async throws {
        let intent = try reminderIntent()
        let sut = makeSUT(registry: FlakyRegistry(failingSaves: 1))
        _ = await saveError { try await sut.useCase.save(intent) }

        let relaunched = relaunch(sut)
        let error = await saveError { try await relaunched.useCase.save(intent) }

        guard case .unconfirmedPreviousAttempt(let pending)? = error else {
            return XCTFail("Error inesperado: \(String(describing: error))")
        }
        XCTAssertEqual(pending.intentID, intent.id)
        XCTAssertEqual(pending.title, "Comprar pilas")
        XCTAssertEqual(pending.startedAt, Fixtures.instant(Fixtures.wednesdayMorning))
        XCTAssertEqual(sut.store.snapshot.createdReminders.count, 1, "No se reintenta la creación a ciegas")

        // Sigue preguntando mientras el usuario no decida.
        let again = await saveError { try await relaunched.useCase.save(intent) }
        XCTAssertEqual(again, .unconfirmedPreviousAttempt(pending))
        XCTAssertEqual(sut.store.snapshot.createdReminders.count, 1)
    }

    func testUserCanExplicitlyCreateAfterAnUnconfirmedAttempt() async throws {
        let intent = try reminderIntent()
        let sut = makeSUT(registry: FlakyRegistry(failingSaves: 1))
        _ = await saveError { try await sut.useCase.save(intent) }
        let relaunched = relaunch(sut)

        let outcome = try await relaunched.useCase.save(
            intent,
            options: SaveOptions(createDespiteUnconfirmedAttempt: true)
        )

        guard case .saved(let record) = outcome else { return XCTFail("Resultado inesperado: \(outcome)") }
        XCTAssertEqual(record.reference.identifier, "reminder-2")
        XCTAssertEqual(sut.store.snapshot.createdReminders.count, 2, "El usuario eligió crear otro")
        let pending = await sut.registry.inner.allPending()
        XCTAssertTrue(pending.isEmpty)
        let stored = await sut.registry.inner.record(for: intent.id)
        XCTAssertEqual(stored, record)
    }

    // MARK: - Fallos antes o durante la creación

    func testPendingMarkFailurePreventsCreation() async throws {
        let intent = try reminderIntent()
        let sut = makeSUT(registry: FlakyRegistry(failMarkPending: true))

        let error = await saveError { try await sut.useCase.save(intent) }

        guard case .registry? = error else {
            return XCTFail("Error inesperado: \(String(describing: error))")
        }
        XCTAssertTrue(sut.store.snapshot.createdReminders.isEmpty, "Sin marca previa no se llama a EventKit")
    }

    func testEventKitFailureClearsTheMarkAndAllowsANormalRetry() async throws {
        let intent = try reminderIntent()
        let sut = makeSUT(registry: FlakyRegistry())
        sut.store.update { $0.createFailure = EventStoreError.operationFailed("sin espacio") }

        let error = await saveError { try await sut.useCase.save(intent) }

        XCTAssertEqual(error, .store(.operationFailed("sin espacio")))
        let pending = await sut.registry.inner.allPending()
        XCTAssertTrue(pending.isEmpty, "EventKit no creó nada: la marca se retira")

        sut.store.update { $0.createFailure = nil }
        let retry = try await sut.useCase.save(intent)
        guard case .saved = retry else { return XCTFail("Resultado inesperado: \(retry)") }
        XCTAssertEqual(sut.store.snapshot.createdReminders.count, 1)
    }

    func testMarkThatCannotBeClearedMakesTheNextAttemptAsk() async throws {
        let intent = try reminderIntent()
        let sut = makeSUT(registry: FlakyRegistry(failClearPending: true))
        sut.store.update { $0.createFailure = EventStoreError.operationFailed("sin espacio") }
        _ = await saveError { try await sut.useCase.save(intent) }
        sut.store.update { $0.createFailure = nil }

        let error = await saveError { try await sut.useCase.save(intent) }

        guard case .unconfirmedPreviousAttempt? = error else {
            return XCTFail("Error inesperado: \(String(describing: error))")
        }
        XCTAssertTrue(sut.store.snapshot.createdReminders.isEmpty, "Ante la duda, se pregunta antes de crear")
    }

    // MARK: - Garantías que no cambian

    func testRecoveryNeverTouchesOtherItems() async throws {
        let intent = try reminderIntent()
        let sut = makeSUT(registry: FlakyRegistry(failingSaves: 1))
        sut.store.update { _ = $0.existingIdentifiers.insert("reminder-del-usuario") }

        _ = await saveError { try await sut.useCase.save(intent) }
        _ = try await sut.useCase.save(intent)

        XCTAssertTrue(sut.store.snapshot.existingIdentifiers.contains("reminder-del-usuario"))
        XCTAssertEqual(sut.store.snapshot.createdReminders.count, 1)
    }
}
