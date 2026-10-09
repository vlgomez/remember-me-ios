/// Valor de un campo de `TaskIntent` junto con su procedencia.
///
/// La procedencia es lo que permite cumplir la regla de no inventar datos: cualquier valor
/// que el usuario no haya dicho literalmente queda en estado `.pending` hasta que se muestra
/// en una vista previa y el usuario la acepta (ver `IntentPreview`).
///
/// Las instancias solo se crean con los métodos de fábrica, que fijan el estado de
/// confirmación coherente con el origen.
public struct TaskField<Value: Sendable>: Sendable {
    public let value: Value
    public let origin: FieldOrigin
    /// Confianza de la deducción. Es `nil` para valores del usuario y valores por defecto.
    public let confidence: Confidence?
    public let confirmation: FieldConfirmation

    private init(value: Value, origin: FieldOrigin, confidence: Confidence?, confirmation: FieldConfirmation) {
        self.value = value
        self.origin = origin
        self.confidence = confidence
        self.confirmation = confirmation
    }

    /// Valor que el usuario dijo o escribió. No requiere confirmación.
    public static func userProvided(_ value: Value) -> TaskField<Value> {
        TaskField(value: value, origin: .userProvided, confidence: nil, confirmation: .notRequired)
    }

    /// Valor deducido por una regla determinista. Requiere confirmación.
    public static func deterministicRule(_ value: Value, confidence: Confidence) -> TaskField<Value> {
        TaskField(value: value, origin: .deterministicRule, confidence: confidence, confirmation: .pending)
    }

    /// Valor por defecto de una regla que no añade información nueva (por ejemplo, "sin aviso"
    /// o la zona horaria del dispositivo). No requiere confirmación.
    public static func ruleDefault(_ value: Value) -> TaskField<Value> {
        TaskField(value: value, origin: .deterministicRule, confidence: nil, confirmation: .notRequired)
    }

    /// Valor deducido por un modelo de IA. Requiere confirmación.
    public static func aiInferred(_ value: Value, confidence: Confidence) -> TaskField<Value> {
        TaskField(value: value, origin: .aiInferred, confidence: confidence, confirmation: .pending)
    }

    public var needsConfirmation: Bool {
        confirmation == .pending
    }

    /// Solo se usa desde `TaskIntent.confirmingPendingFields(shownIn:)`: un campo no se puede
    /// marcar como confirmado sin pasar por una vista previa.
    func confirmed() -> TaskField<Value> {
        guard confirmation == .pending else { return self }
        return TaskField(value: value, origin: origin, confidence: confidence, confirmation: .confirmed)
    }
}

extension TaskField: Equatable where Value: Equatable {}
extension TaskField: Hashable where Value: Hashable {}
extension TaskField: Codable where Value: Codable {}
