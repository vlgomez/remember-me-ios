import Foundation

/// Fuente del instante actual. Se inyecta para que los tests sean deterministas.
///
/// No se llama `Clock` para no chocar con el protocolo `Clock` de la biblioteca estándar.
public protocol DateProvider: Sendable {
    func now() -> Date
}

/// Reloj del sistema.
public struct SystemDateProvider: DateProvider {
    public init() {}

    public func now() -> Date {
        Date()
    }
}

/// Reloj detenido en un instante fijo (tests y vistas previas de SwiftUI).
public struct FixedDateProvider: DateProvider {
    public let date: Date

    public init(_ date: Date) {
        self.date = date
    }

    public func now() -> Date {
        date
    }
}
