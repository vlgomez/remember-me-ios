import Foundation

/// Generador de identificadores. Se inyecta para que los tests sean deterministas.
public protocol IdentifierProvider: Sendable {
    func makeIdentifier() -> UUID
}

public struct RandomIdentifierProvider: IdentifierProvider {
    public init() {}

    public func makeIdentifier() -> UUID {
        UUID()
    }
}

/// Devuelve siempre el mismo identificador.
public struct FixedIdentifierProvider: IdentifierProvider {
    public let identifier: UUID

    public init(_ identifier: UUID) {
        self.identifier = identifier
    }

    public func makeIdentifier() -> UUID {
        identifier
    }
}
