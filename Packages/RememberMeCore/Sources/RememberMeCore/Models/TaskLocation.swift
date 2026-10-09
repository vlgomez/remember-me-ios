import Foundation

/// Ubicación tal y como la escribió el usuario ("Mercadona", "el taller").
///
/// Es solo texto. El dominio no la geocodifica ni la convierte en coordenadas o en una
/// dirección: "Mercadona" puede ser cualquiera de cientos de tiendas, y elegir una sería
/// inventar un dato. Si en el futuro se añade una ubicación geográfica, tendrá que ser un
/// campo distinto que elija el usuario.
public struct TaskLocation: Sendable, Hashable, Codable {
    public let text: String

    /// Devuelve `nil` si el texto está vacío o solo contiene espacios.
    public init?(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.text = trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case text
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .text)
        guard let value = TaskLocation(text: raw) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: container.codingPath, debugDescription: "Ubicación vacía.")
            )
        }
        self = value
    }
}
