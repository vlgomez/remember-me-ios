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

        XCTAssertEqual(try Data(contentsOf: paths.file), corrupt, "Un registro dañado no se sustituye en silencio")
    }
}
