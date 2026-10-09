import Foundation
import XCTest
@testable import RememberMeCore

final class SavedItemRegistryTests: XCTestCase {
    private func makeRecord(
        id: UUID = Fixtures.fixedID,
        identifier: String = "reminder-1",
        pendingAlertDay: CalendarDay? = Fixtures.day(2026, 11, 17)
    ) -> SavedItemRecord {
        SavedItemRecord(
            intentID: TaskIntentID(id),
            reference: StoredItemReference(destination: .appleReminders, identifier: identifier, externalIdentifier: nil),
            alertChannel: .noAlert,
            pendingAlertDay: pendingAlertDay,
            // Segundos enteros: ISO 8601 no conserva fracciones de segundo.
            savedAt: Fixtures.instant(Fixtures.wednesdayMorning)
        )
    }

    private func makeTemporaryFileURL() -> (directory: URL, file: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RememberMeCoreTests-\(UUID().uuidString)", isDirectory: true)
        return (directory, directory.appendingPathComponent("saved-items.json", isDirectory: false))
    }

    // MARK: - En memoria

    func testInMemoryRegistryReplacesTheRecordOfTheSameIntent() async {
        let registry = InMemorySavedItemRegistry()
        await registry.save(makeRecord(identifier: "reminder-1"))
        await registry.save(makeRecord(identifier: "reminder-2"))

        let record = await registry.record(for: TaskIntentID(Fixtures.fixedID))
        let all = await registry.allRecords()

        XCTAssertEqual(record?.reference.identifier, "reminder-2")
        XCTAssertEqual(all.count, 1)
    }

    // MARK: - Archivo JSON

    func testFileRegistrySurvivesANewInstance() async throws {
        let paths = makeTemporaryFileURL()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        let record = makeRecord()
        let other = makeRecord(id: StoreFixtures.otherID, identifier: "reminder-2", pendingAlertDay: nil)

        let writer = JSONFileSavedItemRegistry(fileURL: paths.file)
        try await writer.save(record)
        try await writer.save(other)

        let reader = JSONFileSavedItemRegistry(fileURL: paths.file)
        let loaded = try await reader.record(for: record.intentID)
        let loadedOther = try await reader.record(for: other.intentID)

        XCTAssertEqual(loaded, record)
        XCTAssertEqual(loadedOther, other)
    }

    func testMissingFileMeansNothingSavedYet() async throws {
        let paths = makeTemporaryFileURL()
        defer { try? FileManager.default.removeItem(at: paths.directory) }

        let registry = JSONFileSavedItemRegistry(fileURL: paths.file)
        let record = try await registry.record(for: TaskIntentID(Fixtures.fixedID))

        XCTAssertNil(record)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.file.path), "Leer no crea el archivo")
    }

    // MARK: - Marcas de intentos pendientes

    private func makePending(id: UUID = Fixtures.fixedID) -> PendingCreation {
        PendingCreation(
            intentID: TaskIntentID(id),
            destination: .appleReminders,
            title: "Comprar pilas",
            startedAt: Fixtures.instant(Fixtures.wednesdayMorning)
        )
    }

    func testInMemoryPendingMarkIsClearedBySavingTheRecord() async {
        let registry = InMemorySavedItemRegistry()
        await registry.markPending(makePending())
        let marked = await registry.pendingCreation(for: TaskIntentID(Fixtures.fixedID))
        XCTAssertEqual(marked, makePending())

        await registry.save(makeRecord())

        let afterSave = await registry.pendingCreation(for: TaskIntentID(Fixtures.fixedID))
        XCTAssertNil(afterSave, "Guardar el registro borra la marca en la misma operación")
    }

    func testPendingMarkMatchesTheSameDestinationAndTitle() {
        let pending = makePending()

        XCTAssertTrue(pending.matches(destination: .appleReminders, title: "Comprar pilas"))
        XCTAssertTrue(pending.matches(destination: .appleReminders, title: "  comprar PILAS\n"))
        XCTAssertFalse(pending.matches(destination: .appleReminders, title: "Comprar pila"))
        XCTAssertFalse(pending.matches(destination: .appleCalendar, title: "Comprar pilas"))
    }

    func testFilePendingMarkSurvivesANewInstanceAndIsClearedBySaving() async throws {
        let paths = makeTemporaryFileURL()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        let pending = makePending()
        let other = makePending(id: StoreFixtures.otherID)

        let writer = JSONFileSavedItemRegistry(fileURL: paths.file)
        try await writer.markPending(pending)
        try await writer.markPending(other)

        let afterRelaunch = JSONFileSavedItemRegistry(fileURL: paths.file)
        let loaded = try await afterRelaunch.pendingCreation(for: pending.intentID)
        let all = try await afterRelaunch.pendingCreations()
        XCTAssertEqual(loaded, pending, "La marca sobrevive a un cierre de la app")
        XCTAssertEqual(Set(all), [pending, other])

        try await afterRelaunch.save(makeRecord())
        try await afterRelaunch.clearPending(for: other.intentID)

        let reader = JSONFileSavedItemRegistry(fileURL: paths.file)
        let pendingAfterSave = try await reader.pendingCreation(for: pending.intentID)
        let otherAfterClear = try await reader.pendingCreation(for: other.intentID)
        let record = try await reader.record(for: pending.intentID)
        XCTAssertNil(pendingAfterSave)
        XCTAssertNil(otherAfterClear)
        XCTAssertEqual(record, makeRecord())
    }

    func testFileRegistryReadsTheVersion1Format() async throws {
        let paths = makeTemporaryFileURL()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        try FileManager.default.createDirectory(at: paths.directory, withIntermediateDirectories: true)
        // La versión 1 guardaba una lista de registros.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([makeRecord()]).write(to: paths.file)

        let registry = JSONFileSavedItemRegistry(fileURL: paths.file)
        let record = try await registry.record(for: TaskIntentID(Fixtures.fixedID))
        let pending = try await registry.pendingCreation(for: TaskIntentID(Fixtures.fixedID))
        XCTAssertEqual(record, makeRecord())
        XCTAssertNil(pending)

        // Al escribir se pasa a la versión 2 sin perder nada.
        try await registry.markPending(makePending(id: StoreFixtures.otherID))
        let reader = JSONFileSavedItemRegistry(fileURL: paths.file)
        let migratedRecord = try await reader.record(for: TaskIntentID(Fixtures.fixedID))
        let migratedPending = try await reader.pendingCreation(for: TaskIntentID(StoreFixtures.otherID))
        XCTAssertEqual(migratedRecord, makeRecord())
        XCTAssertEqual(migratedPending, makePending(id: StoreFixtures.otherID))
    }

    func testCorruptFileIsNeverOverwritten() async throws {
        let paths = makeTemporaryFileURL()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        try FileManager.default.createDirectory(at: paths.directory, withIntermediateDirectories: true)
        let corrupt = Data("esto no es JSON".utf8)
        try corrupt.write(to: paths.file)
        let registry = JSONFileSavedItemRegistry(fileURL: paths.file)

        do {
            _ = try await registry.record(for: TaskIntentID(Fixtures.fixedID))
            XCTFail("Se esperaba un error al leer un archivo dañado")
        } catch {
            XCTAssertTrue(error is JSONFileSavedItemRegistry.RegistryError, "\(error)")
        }

        do {
            try await registry.save(makeRecord())
            XCTFail("Se esperaba un error al guardar sobre un archivo dañado")
        } catch {
            XCTAssertTrue(error is JSONFileSavedItemRegistry.RegistryError, "\(error)")
        }

        do {
            try await registry.markPending(makePending())
            XCTFail("Se esperaba un error al anotar un intento sobre un archivo dañado")
        } catch {
            XCTAssertTrue(error is JSONFileSavedItemRegistry.RegistryError, "\(error)")
        }

        XCTAssertEqual(try Data(contentsOf: paths.file), corrupt, "Un registro dañado no se sustituye en silencio")
    }
}
