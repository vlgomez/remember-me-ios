/// Contexto con el que se interpreta una frase.
public struct ParsingContext: Sendable {
    public let dates: DateContext
    public let identifiers: any IdentifierProvider

    public init(dates: DateContext, identifiers: any IdentifierProvider = RandomIdentifierProvider()) {
        self.dates = dates
        self.identifiers = identifiers
    }
}

/// Interpreta una frase en lenguaje natural y devuelve una intención estructurada.
///
/// Un parser nunca ejecuta operaciones (EventKit, notificaciones): solo devuelve datos.
/// El resultado lo valida siempre `InterpretTaskUseCase`, sea cual sea la implementación,
/// para que un parser de IA no pueda saltarse las reglas.
///
/// La función es asíncrona y puede lanzar errores para admitir implementaciones remotas
/// o basadas en modelos; el parser determinista no lanza nunca.
public protocol TaskIntentParser: Sendable {
    func parse(_ text: String, context: ParsingContext) async throws -> TaskParseResult
}
