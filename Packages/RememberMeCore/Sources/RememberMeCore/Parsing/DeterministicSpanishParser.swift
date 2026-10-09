import Foundation

/// Parser determinista para un subconjunto pequeño y documentado del español.
///
/// Frases y expresiones admitidas (ver también el README):
///
/// - Día de ejecución: "hoy", "mañana", "pasado mañana", "dentro de N días|semanas",
///   "en N días|semanas", "[el|este] <día de la semana>", "el próximo <día>",
///   "el <día> que viene", "el 20 de noviembre [de 2026]", "el 20/11[/2026]".
/// - Fecha límite: "antes del|de <día>" (excluye ese día), "para [el] <día>",
///   "hasta [el] <día>" (incluyen ese día).
/// - Antelación: "<N> días|semanas|horas antes del|de <día>" → fecha límite + aviso previo.
/// - Hora: "a las 10", "a la una", "a las 10:30", "a las 10 y media|y cuarto|menos cuarto|y 20",
///   "a las 5 de la mañana|tarde|noche|madrugada", "a las 10h", "18:00", "al mediodía".
/// - Franjas sin hora: "esta mañana|tarde|noche", "por la mañana|tarde|noche", "de madrugada".
/// - Lista de la compra: "Añadir|Añade|Apunta|Pon... <artículo> a la lista de la compra".
/// - Prefijo "Recuérdame [que]": se descarta.
/// - Ubicación: "en <Palabras En Mayúscula>" ("en Mercadona"). Se guarda como texto, deducida.
/// - Tipo: "Comprar ..." → compra (deducido); "cita", "reunión", "consulta" → compromiso (deducido).
///
/// Cuando no puede interpretar algo con seguridad devuelve una aclaración en vez de rellenar
/// el hueco. Las frases con "avísame" (avisos sobre eventos existentes) no se admiten aún.
public struct DeterministicSpanishParser: TaskIntentParser {
    static let unsupportedWords: Set<String> = ["avisame", "avisadme"]
    static let reminderPrefixes: Set<String> = ["recuerdame", "recordarme"]
    static let appointmentWords: Set<String> = ["cita", "reunion", "consulta"]

    public init() {}

    public func parse(_ text: String, context: ParsingContext) async -> TaskParseResult {
        parseImmediately(text, context: context)
    }

    /// Variante síncrona. El parser determinista no necesita esperar a nada.
    public func parseImmediately(_ text: String, context: ParsingContext) -> TaskParseResult {
        let allTokens = SpanishText.tokenize(text)
        guard !allTokens.isEmpty else {
            return TaskParseResult(
                intent: nil,
                clarifications: [ClarificationRequest(field: .title, reason: .emptyInput)]
            )
        }
        if allTokens.contains(where: { Self.unsupportedWords.contains($0.normalized) }) {
            return TaskParseResult(
                intent: nil,
                clarifications: [ClarificationRequest(field: .action, reason: .unsupportedExpression, fragment: text)]
            )
        }

        // 1. Lista de la compra o frase general.
        var titleTokens: [Token] = []
        var explicitKind: TaskField<TaskKind>?
        let workingTokens: [Token]
        if let shopping = SpanishGrammar.matchShoppingList(allTokens) {
            explicitKind = .userProvided(.shopping)
            titleTokens = shopping.item
            workingTokens = shopping.rest
        } else {
            workingTokens = Self.droppingReminderPrefix(allTokens)
        }

        // 2. Reconocimiento de expresiones.
        let scan = SpanishGrammar(tokens: workingTokens).scan()
        titleTokens += scan.leftovers

        let dates = context.dates
        let today = dates.today()
        let now = dates.now()
        let resolver = SpanishExpressionResolver(today: today)
        var clarifications: [ClarificationRequest] = []

        // 3. Tipo y acción.
        let kindField = explicitKind ?? Self.inferKind(from: titleTokens)
        let actionField: TaskField<TaskAction> = .ruleDefault(
            kindField.value == .appointment ? .createCalendarEvent : .createTask
        )

        // 4. Hora.
        var time: (value: TimeOfDay, provenance: Provenance)?
        var ambiguousTimes: [TimeOfDay] = []
        var ambiguousTimeText: String?
        var timeFailed = false
        var vagueUsedAsPeriod = false
        if scan.times.count > 1 {
            timeFailed = true
            clarifications.append(
                ClarificationRequest(field: .scheduledAt, reason: .ambiguousTime, fragment: Self.join(scan.times.map(\.text)))
            )
        } else if let mention = scan.times.first {
            var expression = mention.expression
            if expression.period == nil, scan.vagues.count == 1 {
                // "mañana por la tarde a las 5" → la franja aclara la hora.
                expression = expression.withPeriod(scan.vagues[0].period)
                vagueUsedAsPeriod = true
            }
            switch resolver.resolve(expression) {
            case .resolved(let value, let provenance):
                time = (value: value, provenance: provenance)
            case .ambiguous(let options):
                timeFailed = true
                ambiguousTimes = options
                ambiguousTimeText = mention.text
            case .invalid:
                timeFailed = true
                clarifications.append(
                    ClarificationRequest(field: .scheduledAt, reason: .invalidTime, fragment: mention.text)
                )
            }
        }
        let hasUnresolvedVaguePeriod = !scan.vagues.isEmpty && !vagueUsedAsPeriod && scan.times.isEmpty

        // 5. Fecha límite.
        var deadlineDay: (value: CalendarDay, provenance: Provenance, mention: DeadlineMention)?
        if scan.deadlines.count > 1 {
            clarifications.append(
                ClarificationRequest(field: .deadline, reason: .ambiguousDate, fragment: Self.join(scan.deadlines.map(\.text)))
            )
        } else if let mention = scan.deadlines.first {
            switch resolver.resolve(mention.expression) {
            case .resolved(let day, let provenance):
                deadlineDay = (value: day, provenance: provenance, mention: mention)
            case .ambiguous(let days):
                clarifications.append(
                    ClarificationRequest(
                        field: .deadline,
                        reason: .ambiguousDate,
                        options: days.map { TaskDate.allDay($0) },
                        fragment: mention.text
                    )
                )
            case .invalid:
                clarifications.append(
                    ClarificationRequest(field: .deadline, reason: .invalidDate, fragment: mention.text)
                )
            }
        }

        // 6. Día de ejecución ("esta tarde" también aporta el día: hoy).
        let dayMentions = scan.days + scan.vagues.compactMap { vague -> DayMention? in
            guard let day = vague.day else { return nil }
            return DayMention(expression: day, text: vague.text)
        }
        var scheduledDay: (value: CalendarDay, provenance: Provenance)?
        var dayFailed = false
        if !dayMentions.isEmpty {
            var resolvedDays: [(day: CalendarDay, provenance: Provenance)] = []
            for mention in dayMentions {
                switch resolver.resolve(mention.expression) {
                case .resolved(let day, let provenance):
                    resolvedDays.append((day: day, provenance: provenance))
                case .ambiguous(let days):
                    dayFailed = true
                    clarifications.append(
                        ClarificationRequest(
                            field: .scheduledAt,
                            reason: .ambiguousDate,
                            options: Self.options(days: days, time: time?.value),
                            fragment: mention.text
                        )
                    )
                case .invalid:
                    dayFailed = true
                    clarifications.append(
                        ClarificationRequest(field: .scheduledAt, reason: .invalidDate, fragment: mention.text)
                    )
                }
            }
            if !dayFailed {
                let distinctDays = Set(resolvedDays.map { $0.day })
                if distinctDays.count == 1, let first = resolvedDays.first {
                    scheduledDay = (value: first.day, provenance: Provenance.weakest(resolvedDays.map { $0.provenance }))
                } else {
                    dayFailed = true
                    clarifications.append(
                        ClarificationRequest(
                            field: .scheduledAt,
                            reason: .ambiguousDate,
                            options: Self.options(days: distinctDays.sorted(), time: time?.value),
                            fragment: Self.join(dayMentions.map(\.text))
                        )
                    )
                }
            }
        }

        // 7. A qué fecha pertenece la hora: a la de ejecución si se mencionó un día; si solo hay
        //    fecha límite, a la fecha límite; si no hay ninguna, a hoy (si todavía no ha pasado).
        let timeBelongsToDeadline = dayMentions.isEmpty && deadlineDay != nil
        var scheduledField: TaskField<TaskDate>?
        var deadlineField: TaskField<Deadline>?

        if let scheduledDay {
            if let time {
                let local = LocalDateTime(day: scheduledDay.value, time: time.value)
                scheduledField = Provenance.weakest([scheduledDay.provenance, time.provenance]).field(TaskDate.timed(local))
            } else if !timeFailed && !hasUnresolvedVaguePeriod {
                scheduledField = scheduledDay.provenance.field(TaskDate.allDay(scheduledDay.value))
            }
        }

        if let deadlineDay {
            var provenances = [deadlineDay.provenance]
            let date: TaskDate
            if timeBelongsToDeadline, let time {
                date = .timed(LocalDateTime(day: deadlineDay.value, time: time.value))
                provenances.append(time.provenance)
            } else {
                date = .allDay(deadlineDay.value)
            }
            deadlineField = Provenance.weakest(provenances).field(
                Deadline(date: date, boundary: deadlineDay.mention.boundary)
            )
        }

        if dayMentions.isEmpty, scan.deadlines.isEmpty, let time {
            let todayAt = LocalDateTime(day: today, time: time.value)
            if let instant = dates.instant(for: todayAt), instant > now {
                // El día es deducido: no se dijo, pero hoy todavía se está a tiempo.
                scheduledField = Provenance.weakest([time.provenance, .rule(.medium)]).field(TaskDate.timed(todayAt))
            } else {
                let tomorrowAt = LocalDateTime(day: today.adding(days: 1), time: time.value)
                clarifications.append(
                    ClarificationRequest(
                        field: .scheduledAt,
                        reason: .missingDate,
                        options: [.timed(tomorrowAt)],
                        fragment: scan.times.first?.text
                    )
                )
            }
        }

        // 8. Aclaraciones de hora pendientes.
        if let ambiguousTimeText {
            let targetDay: CalendarDay? = scheduledDay?.value ?? (timeBelongsToDeadline ? deadlineDay?.value : nil)
            let field: TaskFieldKey = (scheduledDay == nil && timeBelongsToDeadline) ? .deadline : .scheduledAt
            var options: [TaskDate] = []
            if let targetDay {
                options = ambiguousTimes.map { TaskDate.timed(LocalDateTime(day: targetDay, time: $0)) }
            }
            clarifications.append(
                ClarificationRequest(
                    field: field,
                    reason: .ambiguousTime,
                    options: options,
                    knownDay: targetDay,
                    fragment: ambiguousTimeText
                )
            )
        }

        if hasUnresolvedVaguePeriod {
            clarifications.append(
                ClarificationRequest(
                    field: .scheduledAt,
                    reason: .vagueTimeOfDay,
                    knownDay: scheduledDay?.value,
                    fragment: Self.join(scan.vagues.map(\.text))
                )
            )
        }

        if kindField.value == .appointment, scan.times.isEmpty, !hasUnresolvedVaguePeriod, !dayFailed {
            clarifications.append(
                ClarificationRequest(field: .scheduledAt, reason: .missingTime, knownDay: scheduledDay?.value)
            )
        }

        // 9. Ubicación (solo texto).
        var locationField: TaskField<TaskLocation>?
        if scan.locations.count == 1, let location = TaskLocation(text: scan.locations[0]) {
            locationField = .deterministicRule(location, confidence: .medium)
        } else if scan.locations.count > 1 {
            clarifications.append(
                ClarificationRequest(field: .location, reason: .unsupportedExpression, fragment: Self.join(scan.locations))
            )
        }

        // 10. Título.
        let titleText = SpanishText.capitalizingFirstLetter(titleTokens.map(\.original).joined(separator: " "))
        if titleText.isEmpty {
            clarifications.append(ClarificationRequest(field: .title, reason: .missingTitle))
        }

        // 11. Zona horaria y aviso.
        let hasTimedDate = scheduledField?.value.isAllDay == false || deadlineField?.value.date.isAllDay == false
        let timeZoneField: TaskField<TimeZone>? = hasTimedDate ? .ruleDefault(dates.timeZone) : nil

        let reminderField: TaskField<ReminderPolicy>
        if let lead = deadlineDay?.mention.lead, deadlineField != nil {
            reminderField = .userProvided(.beforeDeadline(lead))
        } else {
            reminderField = ReminderPolicyRules.defaultPolicy(scheduledAt: scheduledField?.value)
        }

        let intent = TaskIntent(
            id: TaskIntentID(context.identifiers.makeIdentifier()),
            action: actionField,
            title: .userProvided(titleText),
            kind: kindField,
            deadline: deadlineField,
            scheduledAt: scheduledField,
            timeZone: timeZoneField,
            location: locationField,
            reminderPolicy: reminderField
        )
        return TaskParseResult(intent: intent, clarifications: clarifications)
    }

    // MARK: - Auxiliares

    static func droppingReminderPrefix(_ tokens: [Token]) -> [Token] {
        guard let first = tokens.first, reminderPrefixes.contains(first.normalized) else { return tokens }
        var rest = Array(tokens.dropFirst())
        if rest.first?.normalized == "que" {
            rest.removeFirst()
        }
        return rest
    }

    static func inferKind(from titleTokens: [Token]) -> TaskField<TaskKind> {
        let words = titleTokens.map(\.normalized)
        if words.first == "comprar" {
            return .deterministicRule(.shopping, confidence: .high)
        }
        if words.contains(where: { appointmentWords.contains($0) }) {
            return .deterministicRule(.appointment, confidence: .medium)
        }
        return .ruleDefault(.task)
    }

    static func options(days: [CalendarDay], time: TimeOfDay?) -> [TaskDate] {
        days.map { day -> TaskDate in
            if let time {
                return .timed(LocalDateTime(day: day, time: time))
            }
            return .allDay(day)
        }
    }

    static func join(_ parts: [String]) -> String {
        parts.joined(separator: ", ")
    }
}
