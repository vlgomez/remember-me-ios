import Foundation

/// Registro en memoria. Útil para tests y vistas previas; se pierde al cerrar la app.
public actor InMemorySavedItemRegistry: SavedItemRegistry {
    private var records: [UUID: SavedItemRecord]
    private var pending: [UUID: PendingCreation] = [:]

    public init(records: [SavedItemRecord] = []) {
        self.records = Dictionary(records.map { ($0.intentID.uuid, $0) }, uniquingKeysWith: { _, last in last })
    }

    public func record(for intentID: TaskIntentID) -> SavedItemRecord? {
        records[intentID.uuid]
    }

    public func save(_ record: SavedItemRecord) {
        records[record.intentID.uuid] = record
        pending[record.intentID.uuid] = nil
    }

    public func pendingCreation(for intentID: TaskIntentID) -> PendingCreation? {
        pending[intentID.uuid]
    }

    public func markPending(_ pendingCreation: PendingCreation) {
        pending[pendingCreation.intentID.uuid] = pendingCreation
    }

    public func clearPending(for intentID: TaskIntentID) {
        pending[intentID.uuid] = nil
    }

    public func allRecords() -> [SavedItemRecord] {
        records.values.sorted { $0.savedAt < $1.savedAt }
    }

    public func pendingCreations() -> [PendingCreation] {
        pending.values.sorted { $0.startedAt < $1.startedAt }
    }
}

/// Registro guardado en un archivo JSON (en la app, dentro de Application Support).
///
/// Es pequeño y legible a propósito: solo guarda la relación entre intención y elemento creado,
/// y las marcas de intentos pendientes. Cada escritura sustituye el archivo completo de forma
/// atómica (`.atomic`): o queda la versión anterior o la nueva, nunca una mezcla.
///
/// Si el archivo está dañado, las operaciones fallan en vez de empezar de cero en silencio,
/// porque perder el registro permitiría crear duplicados.
///
/// Formatos: la versión 1 era una lista de `SavedItemRecord`; la versión 2 es un objeto con
/// `records` y `pending`. Se leen las dos y siempre se escribe la 2.
public actor JSONFileSavedItemRegistry: SavedItemRegistry {
    public enum RegistryError: Error, Sendable, Hashable {
        case unreadableFile(String)
    }

    private struct Contents {
        var records: [UUID: SavedItemRecord] = [:]
        var pending: [UUID: PendingCreation] = [:]
    }

    private struct FileV2: Codable {
        var version: Int
        var records: [SavedItemRecord]
        var pending: [PendingCreation]
    }

    private let fileURL: URL
    private var cache: Contents?

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func record(for intentID: TaskIntentID) throws -> SavedItemRecord? {
        try load().records[intentID.uuid]
    }

    public func save(_ record: SavedItemRecord) throws {
        var contents = try load()
        contents.records[record.intentID.uuid] = record
        contents.pending[record.intentID.uuid] = nil
        try write(contents)
    }

    public func pendingCreation(for intentID: TaskIntentID) throws -> PendingCreation? {
        try load().pending[intentID.uuid]
    }

    public func markPending(_ pendingCreation: PendingCreation) throws {
        var contents = try load()
        contents.pending[pendingCreation.intentID.uuid] = pendingCreation
        try write(contents)
    }

    public func pendingCreations() throws -> [PendingCreation] {
        try load().pending.values.sorted { $0.startedAt < $1.startedAt }
    }

    public func clearPending(for intentID: TaskIntentID) throws {
        var contents = try load()
        guard contents.pending[intentID.uuid] != nil else { return }
        contents.pending[intentID.uuid] = nil
        try write(contents)
    }

    // MARK: - Privado

    private func load() throws -> Contents {
        if let cache {
            return cache
        }
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            cache = Contents()
            return Contents()
        }
        let contents: Contents
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let file = try? decoder.decode(FileV2.self, from: data) {
                contents = Contents(
                    records: Self.byIntent(file.records, key: { $0.intentID }),
                    pending: Self.byIntent(file.pending, key: { $0.intentID })
                )
            } else {
                let list = try decoder.decode([SavedItemRecord].self, from: data)
                contents = Contents(records: Self.byIntent(list, key: { $0.intentID }))
            }
        } catch {
            throw RegistryError.unreadableFile(String(describing: error))
        }
        cache = contents
        return contents
    }

    /// Solo actualiza la caché si la escritura en disco termina bien.
    private func write(_ contents: Contents) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let file = FileV2(
            version: 2,
            records: contents.records.values.sorted { $0.savedAt < $1.savedAt },
            pending: contents.pending.values.sorted { $0.startedAt < $1.startedAt }
        )
        try encoder.encode(file).write(to: fileURL, options: .atomic)
        cache = contents
    }

    private static func byIntent<Item>(_ items: [Item], key: (Item) -> TaskIntentID) -> [UUID: Item] {
        Dictionary(items.map { (key($0).uuid, $0) }, uniquingKeysWith: { _, last in last })
    }
}
