/// Procedencia de un valor resuelto (origen y confianza).
struct Provenance: Sendable, Hashable {
    let origin: FieldOrigin
    let confidence: Confidence?

    static let user = Provenance(origin: .userProvided, confidence: nil)

    static func rule(_ confidence: Confidence) -> Provenance {
        Provenance(origin: .deterministicRule, confidence: confidence)
    }

    /// Un valor compuesto (día + hora) es tan fiable como su parte menos fiable.
    static func weakest(_ items: [Provenance]) -> Provenance {
        let inferred = items.filter { $0.origin != .userProvided }
        guard !inferred.isEmpty else { return .user }
        let confidence = inferred.compactMap(\.confidence).min() ?? .medium
        let hasAIValue = inferred.contains(where: { $0.origin == .aiInferred })
        let origin: FieldOrigin = hasAIValue ? .aiInferred : .deterministicRule
        return Provenance(origin: origin, confidence: confidence)
    }

    func field<Value: Sendable>(_ value: Value) -> TaskField<Value> {
        switch origin {
        case .userProvided:
            return .userProvided(value)
        case .deterministicRule:
            return .deterministicRule(value, confidence: confidence ?? .medium)
        case .aiInferred:
            return .aiInferred(value, confidence: confidence ?? .low)
        }
    }
}

enum DayResolution: Sendable, Hashable {
    case resolved(CalendarDay, Provenance)
    case ambiguous([CalendarDay])
    case invalid
}

enum TimeResolution: Sendable, Hashable {
    case resolved(TimeOfDay, Provenance)
    /// Varias horas posibles. Puede estar vacía si la ambigüedad no se reduce a una lista corta.
    case ambiguous([TimeOfDay])
    case invalid
}

/// Convierte expresiones reconocidas en días y horas concretos.
///
/// Reglas (todas documentadas en el README):
/// - "hoy", "mañana", "pasado mañana", "dentro de N días": exactas (`userProvided`).
/// - "el viernes" / "este viernes": el próximo viernes; si hoy es viernes, es ambiguo.
/// - "el próximo viernes": si el siguiente viernes cae en esta misma semana, es ambiguo
///   (hay quien se refiere al de la semana siguiente); si no, ese viernes.
/// - "20 de noviembre" sin año: la próxima vez que llegue esa fecha, contando hoy (año deducido).
/// - Horas de 1 a 7 sin "de la mañana/tarde": ambiguas. De 8 a 11: se proponen por la mañana
///   (deducido). 0 y de 13 a 23: exactas.
struct SpanishExpressionResolver: Sendable {
    let today: CalendarDay

    func resolve(_ expression: DayExpression) -> DayResolution {
        switch expression {
        case .relative(let days):
            return .resolved(today.adding(days: days), .user)

        case .weekday(let weekday, let qualifier):
            var delta = (weekday.rawValue - today.weekday.rawValue + 7) % 7
            switch qualifier {
            case .plain, .this:
                if delta == 0 {
                    return .ambiguous([today, today.adding(days: 7)])
                }
                return .resolved(today.adding(days: delta), .rule(.high))
            case .next:
                if delta == 0 {
                    delta = 7
                }
                let candidate = today.adding(days: delta)
                if candidate.startOfISOWeek == today.startOfISOWeek {
                    return .ambiguous([candidate, candidate.adding(days: 7)])
                }
                return .resolved(candidate, .rule(.high))
            }

        case .explicit(let day, let month, let year):
            if let year {
                guard let value = CalendarDay(year: year, month: month, day: day) else { return .invalid }
                return .resolved(value, .user)
            }
            // Sin año: la próxima vez que exista esa fecha (el 29 de febrero puede tardar años).
            for offset in 0...8 {
                if let candidate = CalendarDay(year: today.year + offset, month: month, day: day), candidate >= today {
                    return .resolved(candidate, .rule(offset == 0 ? .high : .medium))
                }
            }
            return .invalid
        }
    }

    func resolve(_ expression: TimeExpression) -> TimeResolution {
        let minute = expression.minute
        guard (0...59).contains(minute) else { return .invalid }

        func exact(_ hour: Int, _ provenance: Provenance) -> TimeResolution {
            guard let time = TimeOfDay(hour: hour, minute: minute) else { return .invalid }
            return .resolved(time, provenance)
        }

        func either(_ first: Int, _ second: Int) -> TimeResolution {
            let options = [first, second].compactMap { TimeOfDay(hour: $0, minute: minute) }
            return options.count == 2 ? .ambiguous(options) : .invalid
        }

        let hour = expression.hour
        switch expression.period {
        case nil:
            switch hour {
            case 0, 13...23:
                return exact(hour, .user)
            case 12:
                return exact(12, .rule(.high))
            case 8...11:
                return exact(hour, .rule(.medium))
            case 1...7:
                return either(hour, hour + 12)
            default:
                return .invalid
            }
        case .noon?:
            return exact(12, .user)
        case .morning?, .dawn?:
            switch hour {
            case 0...11:
                return exact(hour, .user)
            case 12:
                return either(0, 12)
            default:
                return .invalid
            }
        case .afternoon?:
            switch hour {
            case 1...11:
                return exact(hour + 12, .user)
            case 12...23:
                return exact(hour, .user)
            default:
                return .invalid
            }
        case .night?:
            switch hour {
            case 6...11:
                return exact(hour + 12, .user)
            case 18...23:
                return exact(hour, .user)
            case 0...5, 12:
                // "a las 2 de la noche" suele referirse a la madrugada del día siguiente: se pregunta.
                return .ambiguous([])
            default:
                return .invalid
            }
        }
    }
}
