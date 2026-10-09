import Foundation

/// Momento en que debe sonar un aviso, una vez aplicada la política.
public enum ReminderTrigger: Sendable, Hashable {
    case noReminder
    /// Se conoce el día del aviso pero no la hora. La hora la elige el usuario; no se inventa.
    case dayWithoutTime(CalendarDay)
    case at(LocalDateTime)
}

public enum ReminderPolicyError: Error, Sendable, Hashable {
    case missingDeadline
    case nonPositiveLeadTime
    case leadTimeRequiresTimedDeadline
    case unresolvableLocalTime
}

/// Reglas por defecto para elegir la política de aviso.
public enum ReminderPolicyRules {
    /// - Si la ejecución tiene hora, se propone avisar a esa hora (deducido: requiere confirmación).
    /// - En cualquier otro caso, sin aviso. No se asigna hora a fechas que no la tienen.
    public static func defaultPolicy(scheduledAt: TaskDate?) -> TaskField<ReminderPolicy> {
        if case .timed(let local)? = scheduledAt {
            return .deterministicRule(.at(local), confidence: .high)
        }
        return .ruleDefault(.noReminder)
    }
}

/// Calcula el momento de un aviso a partir de su política y la fecha límite.
public struct ReminderScheduleCalculator: Sendable {
    public let dates: DateContext

    public init(dates: DateContext) {
        self.dates = dates
    }

    public func trigger(for policy: ReminderPolicy, deadline: Deadline?) -> Result<ReminderTrigger, ReminderPolicyError> {
        switch policy {
        case .noReminder:
            return .success(.noReminder)
        case .at(let local):
            return .success(.at(local))
        case .beforeDeadline(let lead):
            guard let deadline else {
                return .failure(.missingDeadline)
            }
            guard lead.amount > 0 else {
                return .failure(.nonPositiveLeadTime)
            }
            switch (lead, deadline.date) {
            case (.days(let count), .allDay(let day)):
                return .success(.dayWithoutTime(day.adding(days: -count)))
            case (.days(let count), .timed(let local)):
                // Días de calendario: misma hora de reloj aunque haya cambio de horario por medio.
                return .success(.at(dates.adding(days: -count, to: local)))
            case (.hours, .allDay), (.minutes, .allDay):
                return .failure(.leadTimeRequiresTimedDeadline)
            case (.hours(let count), .timed(let local)):
                return shifted(local, bySeconds: TimeInterval(count) * 3_600)
            case (.minutes(let count), .timed(let local)):
                return shifted(local, bySeconds: TimeInterval(count) * 60)
            }
        }
    }

    /// Horas y minutos son duraciones reales: se restan sobre el instante, no sobre el reloj.
    private func shifted(_ local: LocalDateTime, bySeconds seconds: TimeInterval) -> Result<ReminderTrigger, ReminderPolicyError> {
        guard let instant = dates.instant(for: local) else {
            return .failure(.unresolvableLocalTime)
        }
        return .success(.at(dates.localDateTime(containing: instant.addingTimeInterval(-seconds))))
    }
}
