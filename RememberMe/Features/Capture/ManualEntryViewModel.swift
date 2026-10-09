import Foundation
import Observation
import RememberMeCore

/// Alta manual de un recordatorio o un evento.
///
/// Es la forma de probar la integración con EventKit hasta que llegue la captura en lenguaje
/// natural (Fase C). Todos los datos los escribe o elige el usuario, así que la intención no
/// contiene nada deducido. El flujo es: rellenar, "Revisar" (valida y muestra lo que se va a
/// crear) y "Guardar" (crea el elemento si hay permiso y no se había guardado ya).
@MainActor
@Observable
final class ManualEntryViewModel {
    enum Kind: String, CaseIterable, Identifiable {
        case task
        case shopping
        case event

        var id: String { rawValue }

        var label: String {
            switch self {
            case .task:
                return "Tarea"
            case .shopping:
                return "Compra"
            case .event:
                return "Evento"
            }
        }

        var entity: EventStoreEntity {
            self == .event ? .events : .reminders
        }
    }

    enum DateMode: String, CaseIterable, Identifiable {
        case none
        case allDay
        case timed

        var id: String { rawValue }

        var label: String {
            switch self {
            case .none:
                return "Sin fecha"
            case .allDay:
                return "Día completo"
            case .timed:
                return "Con hora"
            }
        }
    }

    /// Lo que se mostró al pulsar "Revisar".
    struct Review: Equatable {
        let intent: TaskIntent
        let options: SaveOptions
        let summary: [String]
        let warnings: [String]
        let signature: String
    }

    enum Banner: Equatable {
        case success(String)
        case notice(String)
        case failure(String)
        case access(AccessGuidance)
    }

    static let durationChoices = [15, 30, 45, 60, 90, 120, 180]

    // Formulario.
    var kind: Kind = .task
    var title = ""
    var notes = ""
    var location = ""
    var dateMode: DateMode = .none
    var date = Date()
    /// Sin valor por defecto: la duración de un evento la elige el usuario.
    var durationMinutes: Int?
    /// `nil` = lista predeterminada de Recordatorios.
    var reminderListID: String?

    // Estado.
    private(set) var reminderLists: [ReminderListSnapshot] = []
    private(set) var review: Review?
    private(set) var problems: [String] = []
    private(set) var banner: Banner?
    private(set) var isSaving = false
    /// Explicación que se muestra antes de la petición del sistema.
    var permissionExplanation: AccessGuidance?
    /// Elemento guardado antes y borrado fuera de la app: se pregunta si crearlo de nuevo.
    var missingRecord: SavedItemRecord?

    private let environment: AppEnvironment
    /// Identificador de intención por contenido del formulario, para que repetir el mismo
    /// contenido sea la misma operación (y no un duplicado) durante la sesión.
    private var intentIDs: [String: UUID] = [:]

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var isReviewCurrent: Bool {
        review?.signature == signature
    }

    var canReview: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (kind != .event || durationMinutes != nil)
    }

    /// Carga las listas solo si ya hay acceso total: no pide permiso.
    func loadListsIfAllowed() async {
        guard environment.access.permission(for: .reminders) == .fullAccess else {
            reminderLists = []
            return
        }
        if case .loaded(let lists) = await environment.loadReminderLists.load() {
            reminderLists = lists.filter { $0.allowsModifications }
            if let selected = reminderListID, !reminderLists.contains(where: { $0.id == selected }) {
                reminderListID = nil
            }
        }
    }

    // MARK: - Revisar

    func makeReview() {
        banner = nil
        problems = []
        review = nil

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            problems = ["Escribe un título."]
            return
        }
        let duration: TimeInterval?
        if kind == .event {
            guard let minutes = durationMinutes else {
                problems = ["Elige la duración del evento."]
                return
            }
            duration = TimeInterval(minutes * 60)
        } else {
            duration = nil
        }

        let currentSignature = signature
        let id = intentIDs[currentSignature] ?? UUID()
        intentIDs[currentSignature] = id

        let dates = environment.dates
        let local = dates.localDateTime(containing: date)
        let scheduled: TaskDate?
        switch (kind, dateMode) {
        case (.event, _), (_, .timed):
            scheduled = .timed(local)
        case (_, .allDay):
            scheduled = .allDay(local.day)
        case (_, .none):
            scheduled = nil
        }
        let taskKind: TaskKind
        let action: TaskAction
        switch kind {
        case .task:
            taskKind = .task
            action = .createTask
        case .shopping:
            taskKind = .shopping
            action = .createTask
        case .event:
            taskKind = .appointment
            action = .createCalendarEvent
        }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let intent = TaskIntent(
            id: TaskIntentID(id),
            action: .userProvided(action),
            title: .userProvided(trimmedTitle),
            notes: trimmedNotes.isEmpty ? nil : TaskField.userProvided(trimmedNotes),
            kind: .userProvided(taskKind),
            scheduledAt: scheduled.map { TaskField.userProvided($0) },
            location: TaskLocation(text: location).map { TaskField.userProvided($0) },
            reminderPolicy: .ruleDefault(.noReminder)
        )

        // Rellena la zona horaria del dispositivo si hay hora y valida.
        let result = environment.interpret.revalidate(intent)
        guard let validated = result.intent, validated.validationState == .readyToSave else {
            let errors = result.messages.filter { $0.isError }.map { $0.text }
            problems = errors.isEmpty ? ["La entrada no es válida."] : errors
            return
        }

        let options = SaveOptions(
            eventDuration: duration,
            reminderListIdentifier: kind == .event ? nil : reminderListID
        )
        review = Review(
            intent: validated,
            options: options,
            summary: summary(for: validated, durationMinutes: durationMinutes),
            warnings: result.messages.filter { $0.severity == .warning }.map { $0.text },
            signature: currentSignature
        )
    }

    // MARK: - Guardar

    /// - Parameters:
    ///   - explained: el usuario ya vio la explicación previa a la petición del sistema.
    ///   - recreate: el usuario pidió crear de nuevo un elemento borrado fuera de la app.
    func save(explained: Bool = false, recreate: Bool = false) async {
        guard let review, isReviewCurrent, !isSaving else { return }
        banner = nil
        let entity = kind.entity

        switch environment.access.permission(for: entity) {
        case .fullAccess:
            break
        case .notDetermined:
            guard explained else {
                // Primero se explica por qué; la petición del sistema llega al pulsar "Continuar".
                permissionExplanation = AccessGuidance(entity: entity, permission: .notDetermined)
                return
            }
        case let other:
            banner = .access(AccessGuidance(entity: entity, permission: other))
            return
        }

        isSaving = true
        defer { isSaving = false }

        var options = review.options
        options.recreateIfMissing = recreate
        do {
            let outcome = try await environment.saveTask.save(review.intent, options: options)
            switch outcome {
            case .saved:
                banner = .success("Guardado en \(entity.appName).")
                await loadListsIfAllowed()
            case .alreadySaved:
                banner = .notice("Ya estaba guardado en \(entity.appName). No se ha creado otro.")
            case .previouslySavedButMissing(let record):
                missingRecord = record
            }
        } catch let error as SaveError {
            if case .permission(let failedEntity, let permission) = error {
                banner = .access(AccessGuidance(entity: failedEntity, permission: permission))
            } else {
                banner = .failure(error.userMessage)
            }
        } catch {
            banner = .failure(error.localizedDescription)
        }
    }

    /// Vacía el formulario para empezar otra entrada.
    func reset() {
        title = ""
        notes = ""
        location = ""
        dateMode = .none
        date = Date()
        durationMinutes = nil
        review = nil
        problems = []
        banner = nil
    }

    // MARK: - Auxiliares

    /// Resumen del contenido del formulario. Cambia si cambia cualquier dato.
    private var signature: String {
        let local = environment.dates.localDateTime(containing: date)
        let when: String
        switch (kind, dateMode) {
        case (.event, _), (_, .timed):
            when = local.description
        case (_, .allDay):
            when = local.day.description
        case (_, .none):
            when = "-"
        }
        return [
            kind.rawValue,
            title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes.trimmingCharacters(in: .whitespacesAndNewlines),
            location.trimmingCharacters(in: .whitespacesAndNewlines),
            when,
            durationMinutes.map { String($0) } ?? "-",
            kind == .event ? "-" : (reminderListID ?? "predeterminada")
        ].joined(separator: "|")
    }

    private func summary(for intent: TaskIntent, durationMinutes: Int?) -> [String] {
        var lines: [String] = []
        switch kind {
        case .event:
            lines.append("Se creará un evento en tu calendario predeterminado.")
        case .task, .shopping:
            let listName = reminderLists.first(where: { $0.id == reminderListID })?.title ?? "la lista predeterminada"
            lines.append("Se creará un recordatorio (\(kind.label.lowercased())) en \(listName).")
        }
        lines.append("Título: \(intent.title.value)")
        switch intent.scheduledAt?.value {
        case .allDay(let day)?:
            let start = environment.dates.interval(for: day).start
            lines.append("Fecha: \(start.formatted(date: .complete, time: .omitted)), sin hora")
        case .timed(let local)?:
            if let start = environment.dates.instant(for: local) {
                lines.append("Fecha y hora: \(start.formatted(date: .complete, time: .shortened))")
            }
        case nil:
            lines.append("Sin fecha")
        }
        if let minutes = durationMinutes, kind == .event {
            lines.append("Duración: \(minutes) min")
        }
        if let location = intent.location?.value.text {
            lines.append("Ubicación: \(location)")
        }
        if let notes = intent.notes?.value {
            lines.append("Notas: \(notes)")
        }
        lines.append("Sin aviso: los avisos llegarán en una fase posterior.")
        return lines
    }
}
