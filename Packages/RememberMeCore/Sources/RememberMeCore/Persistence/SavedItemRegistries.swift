import Foundation

/// Registro en memoria. Útil para tests y vistas previas; se pierde al cerrar la app.
public actor InMemorySavedItemRegistry: SavedItemRegistry {
    private var records: [UUID: SavedItemRecord]

    public init(records: [SavedItemRecord] = []) {
        self.records = Dictionary(records.map { ($0.intentID.uuid, $0) }, uniquingKeysWith: { _, last in last })
    }

    public func record(for intentID: TaskIntentID) -> SavedItemRecord? {
        records[intentID.uuid]
    }

    public func save(_ record: SavedItemRecord) {
        records[record.intentID.uuid] = record
    }

    public func allRecords() -> [SavedItemRecord] {
        records.values.sorted { $0.savedAt < $1.savedAt }
    }
}

/// Registro guardado en un archivo JSON (en la app, dentro de Application Support).
///
/// Es pequeño y legible a propósito: solo guarda la relación entre intención y elemento creado.
/// Si el archivo está dañado, las operaciones fallan en vez de empezar de cero en silencio,
/// porque perder el registro permitiría crear duplicados.
public actor JSONFileSavedItemRegistry: SavedItemRegistry {
    public enum RegistryError: Error, Sendable, Hashable {
        case unreadableFile(String)
    }

    private let fileURL: URL
    private var cache: [UUID: SavedItemRecord]?

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func record(for intentID: TaskIntentID) throws -> SavedItemRecord? {
        try loadRecords()[intentID.uuid]
    }

    public func save(_ record: SavedItemRecord) throws {
        var records = try loadRecords()
        records[record.intentID.uuid] = record
        try write(records)
        cache = records
    }

    private func loadRecords() throws -> [UUID: SavedItemRecord] {
        if let cache {
            return cache
        }
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            cache = [:]
            return [:]
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let list = try decoder.decode([SavedItemRecord].self, from: data)
            let records = Dictionary(list.map { ($0.intentID.uuid, $0) }, uniquingKeysWith: { _, last in last })
            cache = records
            return records
        } catch {
            throw RegistryError.unreadableFile(String(describing: error))
        }
    }

    private func write(_ records: [UUID: SavedItemRecord]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let ordered = records.values.sorted { $0.savedAt < $1.savedAt }
        try encoder.encode(ordered).write(to: fileURL, options: .atomic)
    }
}
