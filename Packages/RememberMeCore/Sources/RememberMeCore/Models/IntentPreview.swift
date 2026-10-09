/// Instantánea de lo que se ha mostrado al usuario en la vista previa.
///
/// La interfaz crea una `IntentPreview` en el momento de mostrar la intención. Para confirmar
/// los datos deducidos hay que presentar esa misma instantánea: si la intención ha cambiado
/// desde entonces, la confirmación se rechaza. Así no se puede dar por aceptada una fecha
/// que el usuario no ha visto.
public struct IntentPreview: Sendable, Hashable {
    public let shownIntent: TaskIntent
    public let fieldsNeedingConfirmation: Set<TaskFieldKey>

    public init(showing intent: TaskIntent) {
        self.shownIntent = intent
        self.fieldsNeedingConfirmation = intent.fieldsPendingConfirmation
    }
}

public enum ConfirmationError: Error, Sendable, Hashable {
    /// La intención no es la que se mostró en la vista previa (ha cambiado después).
    case previewDoesNotMatchIntent
    /// La intención no está a la espera de confirmación (falta información o tiene errores).
    case intentNotAwaitingConfirmation(ValidationState)
}

extension TaskIntent {
    /// Marca como confirmados los campos deducidos que aparecían en la vista previa.
    ///
    /// - Throws: `ConfirmationError` si la vista previa no corresponde a esta intención o si la
    ///   intención no está en estado `.needsConfirmation`.
    /// - Returns: Una copia con estado `.notValidated`, que hay que volver a validar.
    public func confirmingPendingFields(shownIn preview: IntentPreview) throws -> TaskIntent {
        guard preview.shownIntent == self else {
            throw ConfirmationError.previewDoesNotMatchIntent
        }
        guard validationState == .needsConfirmation else {
            throw ConfirmationError.intentNotAwaitingConfirmation(validationState)
        }
        return confirmingFields(preview.fieldsNeedingConfirmation)
    }
}
