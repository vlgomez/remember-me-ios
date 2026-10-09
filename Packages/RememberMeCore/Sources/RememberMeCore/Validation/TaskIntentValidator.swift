import Foundation

/// Comprueba la coherencia de una intención y le asigna un estado de validación.
///
/// Orden de precedencia del estado:
/// 1. Hay aclaraciones pendientes → `.needsClarification` (los errores pueden deberse a que falta información).
/// 2. Hay errores → `.invalid`.
/// 3. Hay datos deducidos sin confirmar → `.needsConfirmation`.
/// 4. En otro caso → `.readyToSave`.
///
/// Los avisos (`warning`) e informaciones (`info`) no bloquean el guardado.
public struct TaskIntentValidator: Sendable {
    public let dates: DateContext

    public init(dates: DateContext) {
        self.dates = dates
    }

    public func validate(_ intent: TaskIntent, clarifications: [ClarificationRequest] = []) -> TaskParseResult {
        let context = intent.timeZone.map { dates.withTimeZone($0.value) } ?? dates
        let now = context.now()
        let today = context.day(containing: now)
        var messages: [ValidationMessage] = []

        if intent.title.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(.error(.emptyTitle, field: .title))
        }

        if !Self.isConsistent(kind: intent.kind.value, action: intent.action.value) {
            messages.append(.error(.actionKindMismatch, field: .action))
        }

        if case .createCalendarEvent = intent.action.value, intent.scheduledAt?.value.isAllDay != false {
            messages.append(.error(.calendarEventRequiresTime, field: .scheduledAt))
        }

        if intent.requiresTimeZone, intent.timeZone == nil {
            messages.append(.error(.missingTimeZone, field: .timeZone))
        }

        if let scheduled = intent.scheduledAt?.value {
            messages += checkDate(scheduled, field: .scheduledAt, today: today, now: now, context: context)
        }

        if let deadline = intent.deadline?.value {
            if deadline.lastValidDay < today {
                messages.append(.warning(.deadlineInPast, field: .deadline))
            }
            if case .timed(let local) = deadline.date, case .nonexistent = context.resolve(local) {
                messages.append(.error(.nonexistentLocalTime, field: .deadline))
            }
            if let scheduled = intent.scheduledAt?.value, scheduled.day > deadline.lastValidDay {
                messages.append(.error(.scheduledAfterDeadline, field: .scheduledAt))
            }
        }

        messages += checkReminder(intent, context: context, now: now)

        let pending = intent.fieldsPendingConfirmation
        for key in TaskFieldKey.allCases where pending.contains(key) {
            messages.append(.info(.pendingConfirmation, field: key))
        }

        let state = Self.state(messages: messages, clarifications: clarifications, pending: pending)
        return TaskParseResult(
            intent: intent.settingValidationState(state),
            clarifications: clarifications,
            messages: messages
        )
    }

    static func state(
        messages: [ValidationMessage],
        clarifications: [ClarificationRequest],
        pending: Set<TaskFieldKey>
    ) -> ValidationState {
        if !clarifications.isEmpty {
            return .needsClarification
        }
        if messages.contains(where: { $0.severity == .error }) {
            return .invalid
        }
        if !pending.isEmpty {
            return .needsConfirmation
        }
        return .readyToSave
    }

    static func isConsistent(kind: TaskKind, action: TaskAction) -> Bool {
        switch (kind, action) {
        case (.appointment, .createCalendarEvent),
             (_, .addReminderToExistingEvent),
             (.task, .createTask),
             (.shopping, .createTask):
            return true
        default:
            return false
        }
    }

    private func checkDate(
        _ date: TaskDate,
        field: TaskFieldKey,
        today: CalendarDay,
        now: Date,
        context: DateContext
    ) -> [ValidationMessage] {
        switch date {
        case .allDay(let day):
            return day < today ? [.warning(.dateInPast, field: field)] : []
        case .timed(let local):
            switch context.resolve(local) {
            case .nonexistent:
                return [.error(.nonexistentLocalTime, field: field)]
            case .repeated(let earlier, _):
                var result: [ValidationMessage] = [.warning(.repeatedLocalTime, field: field)]
                if earlier < now {
                    result.append(.warning(.dateInPast, field: field))
                }
                return result
            case .exact(let instant):
                return instant < now ? [.warning(.dateInPast, field: field)] : []
            }
        }
    }

    private func checkReminder(_ intent: TaskIntent, context: DateContext, now: Date) -> [ValidationMessage] {
        let calculator = ReminderScheduleCalculator(dates: context)
        switch calculator.trigger(for: intent.reminderPolicy.value, deadline: intent.deadline?.value) {
        case .success(.noReminder):
            return []
        case .success(.dayWithoutTime(let day)):
            var result: [ValidationMessage] = [.info(.reminderNeedsTime, field: .reminderPolicy)]
            if day < context.day(containing: now) {
                result.append(.warning(.reminderInPast, field: .reminderPolicy))
            }
            return result
        case .success(.at(let local)):
            guard let instant = context.instant(for: local) else {
                return [.error(.nonexistentLocalTime, field: .reminderPolicy)]
            }
            return instant < now ? [.warning(.reminderInPast, field: .reminderPolicy)] : []
        case .failure(.missingDeadline):
            return [.error(.reminderRequiresDeadline, field: .reminderPolicy)]
        case .failure(.nonPositiveLeadTime):
            return [.error(.leadTimeMustBePositive, field: .reminderPolicy)]
        case .failure(.leadTimeRequiresTimedDeadline):
            return [.error(.leadTimeNeedsTimedDeadline, field: .reminderPolicy)]
        case .failure(.unresolvableLocalTime):
            return [.error(.nonexistentLocalTime, field: .reminderPolicy)]
        }
    }
}
