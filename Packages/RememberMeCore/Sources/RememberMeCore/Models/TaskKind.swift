/// Tipo de tarea que distingue el dominio.
public enum TaskKind: String, Sendable, Hashable, Codable, CaseIterable {
    /// Tarea general: llamar, enviar, revisar...
    case task
    /// Compra: un artículo para la lista de la compra o algo que adquirir.
    case shopping
    /// Compromiso con hora (cita, reunión). Se guarda como evento de calendario.
    case appointment
}
