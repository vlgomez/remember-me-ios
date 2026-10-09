import Foundation

/// Eventos de un día de la agenda.
public struct AgendaDay: Sendable, Hashable, Identifiable {
    public let day: CalendarDay
    public let events: [CalendarEventSnapshot]

    public var id: CalendarDay { day }

    public init(day: CalendarDay, events: [CalendarEventSnapshot]) {
        self.day = day
        self.events = events
    }
}

/// Estado de la pantalla de agenda.
public enum AgendaState: Sendable, Hashable {
    /// Todavía no se ha consultado nada.
    case idle
    /// El usuario no ha decidido el permiso: se muestra la explicación y el botón.
    case needsPermission
    /// Sin acceso total (denegado, restringido o solo escritura).
    case unavailable(EventStorePermission)
    /// Hay acceso pero no hay eventos en el intervalo.
    case empty(DateInterval)
    case loaded([AgendaDay])
    case failed(EventStoreError)
}

/// Carga los eventos de los próximos días agrupados por día local.
///
/// Solo consulta el estado del permiso; nunca lo solicita.
public struct LoadAgendaUseCase: Sendable {
    private let access: any EventStoreAccessProviding
    private let calendar: any CalendarEventStoring
    private let dates: DateContext

    public init(access: any EventStoreAccessProviding, calendar: any CalendarEventStoring, dates: DateContext) {
        self.access = access
        self.calendar = calendar
        self.dates = dates
    }

    /// - Parameter days: Número de días, empezando hoy (incluido).
    public func load(days: Int = 7) async -> AgendaState {
        switch access.permission(for: .events) {
        case .notDetermined:
            return .needsPermission
        case .fullAccess:
            break
        case let other:
            return .unavailable(other)
        }

        let today = dates.today()
        let lastDay = today.adding(days: max(days, 1) - 1)
        let interval = DateInterval(
            start: dates.interval(for: today).start,
            end: dates.interval(for: lastDay).end
        )

        let events: [CalendarEventSnapshot]
        do {
            events = try await calendar.events(in: interval)
        } catch let error as EventStoreError {
            return .failed(error)
        } catch {
            return .failed(.operationFailed(String(describing: error)))
        }

        guard !events.isEmpty else { return .empty(interval) }
        return .loaded(group(events, from: today, to: lastDay))
    }

    /// Agrupa por el día local de inicio. Un evento que empezó antes del primer día se muestra en el primero.
    func group(_ events: [CalendarEventSnapshot], from firstDay: CalendarDay, to lastDay: CalendarDay) -> [AgendaDay] {
        var byDay: [CalendarDay: [CalendarEventSnapshot]] = [:]
        for event in events {
            let startDay = dates.day(containing: event.start)
            let day = min(max(startDay, firstDay), lastDay)
            byDay[day, default: []].append(event)
        }
        return byDay.keys.sorted().map { day in
            let sorted = (byDay[day] ?? []).sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return AgendaDay(day: day, events: sorted)
        }
    }
}

/// Estado de la sección de listas de Reminders.
public enum ReminderListsState: Sendable, Hashable {
    case idle
    case needsPermission
    case unavailable(EventStorePermission)
    case empty
    case loaded([ReminderListSnapshot])
    case failed(EventStoreError)
}

/// Carga las listas de Reminders (la por defecto primero). Solo consulta el permiso; nunca lo solicita.
public struct LoadReminderListsUseCase: Sendable {
    private let access: any EventStoreAccessProviding
    private let reminders: any ReminderStoring

    public init(access: any EventStoreAccessProviding, reminders: any ReminderStoring) {
        self.access = access
        self.reminders = reminders
    }

    public func load() async -> ReminderListsState {
        switch access.permission(for: .reminders) {
        case .notDetermined:
            return .needsPermission
        case .fullAccess:
            break
        case let other:
            return .unavailable(other)
        }

        do {
            let lists = try await reminders.reminderLists()
            guard !lists.isEmpty else { return .empty }
            return .loaded(lists.sorted { lhs, rhs in
                if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            })
        } catch let error as EventStoreError {
            return .failed(error)
        } catch {
            return .failed(.operationFailed(String(describing: error)))
        }
    }
}
