import Foundation

/// Interpreta una frase, la valida y gestiona la confirmación de la vista previa.
///
/// Es el único punto de entrada que debería usar la interfaz: valida siempre lo que devuelve
/// el parser, sea determinista o de IA, así que ninguna implementación puede saltarse las reglas.
/// No guarda nada: para guardar en Reminders o Calendar se usa `SaveConfirmedTaskUseCase`.
public struct InterpretTaskUseCase: Sendable {
    private let parser: any TaskIntentParser
    private let context: ParsingContext
    private let validator: TaskIntentValidator

    public init(parser: any TaskIntentParser, context: ParsingContext) {
        self.parser = parser
        self.context = context
        self.validator = TaskIntentValidator(dates: context.dates)
    }

    public func interpret(_ text: String) async throws -> TaskParseResult {
        let draft = try await parser.parse(text, context: context)
        guard let intent = draft.intent else {
            return draft
        }
        let validated = validator.validate(
            intent.fillingMissingTimeZone(context.dates.timeZone),
            clarifications: draft.clarifications
        )
        return TaskParseResult(
            intent: validated.intent,
            clarifications: validated.clarifications,
            messages: draft.messages + validated.messages
        )
    }

    /// Vuelve a validar después de que el usuario corrija algo en la vista previa.
    public func revalidate(
        _ intent: TaskIntent,
        remainingClarifications: [ClarificationRequest] = []
    ) -> TaskParseResult {
        validator.validate(
            intent.fillingMissingTimeZone(context.dates.timeZone),
            clarifications: remainingClarifications
        )
    }

    /// Confirma los datos deducidos que se mostraron en `preview` y vuelve a validar.
    ///
    /// - Throws: `ConfirmationError` si la vista previa no corresponde a la intención actual o
    ///   la intención no está pendiente de confirmación.
    public func confirm(_ intent: TaskIntent, shownIn preview: IntentPreview) throws -> TaskParseResult {
        let confirmed = try intent.confirmingPendingFields(shownIn: preview)
        return validator.validate(confirmed)
    }
}
