/// De dónde procede el valor de un campo.
public enum FieldOrigin: String, Sendable, Hashable, Codable {
    /// El usuario lo dijo de forma literal ("mañana", "el 20 de noviembre de 2026").
    case userProvided
    /// Lo dedujo una regla determinista ("el viernes" → qué viernes; el año de "20 de noviembre").
    case deterministicRule
    /// Lo dedujo un modelo de IA.
    case aiInferred
}

/// Estado de confirmación de un campo.
public enum FieldConfirmation: String, Sendable, Hashable, Codable {
    /// El valor no necesita confirmación (lo dijo el usuario o es un valor por defecto que no añade información).
    case notRequired
    /// El valor es una deducción que todavía no se ha mostrado y aceptado en una vista previa.
    case pending
    /// El usuario aceptó la deducción en una vista previa.
    case confirmed
}

/// Nivel de confianza entre 0 y 1.
public struct Confidence: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let value: Double

    /// Devuelve `nil` si el valor no está en el intervalo cerrado [0, 1].
    public init?(_ value: Double) {
        guard value.isFinite, value >= 0, value <= 1 else { return nil }
        self.value = value
    }

    private init(uncheckedValue: Double) {
        self.value = uncheckedValue
    }

    public static let certain = Confidence(uncheckedValue: 1)
    public static let high = Confidence(uncheckedValue: 0.9)
    public static let medium = Confidence(uncheckedValue: 0.7)
    public static let low = Confidence(uncheckedValue: 0.4)

    public static func < (lhs: Confidence, rhs: Confidence) -> Bool {
        lhs.value < rhs.value
    }

    public var description: String { "\(value)" }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(Double.self)
        guard let valid = Confidence(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "La confianza debe estar entre 0 y 1; se recibió \(raw)."
            )
        }
        self = valid
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
