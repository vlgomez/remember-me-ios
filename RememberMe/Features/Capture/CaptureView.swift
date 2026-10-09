import RememberMeCore
import SwiftUI

/// Añadir: por ahora, alta manual de recordatorios y eventos con revisión antes de guardar.
/// La escritura en lenguaje natural llegará en la Fase C y la voz en la Fase E.
struct CaptureView: View {
    @State private var model: ManualEntryViewModel
    @Environment(\.openURL) private var openURL

    init(environment: AppEnvironment) {
        _model = State(initialValue: ManualEntryViewModel(environment: environment))
    }

    var body: some View {
        NavigationStack {
            Form {
                entrySection
                dateSection
                if model.kind != .event, !model.reminderLists.isEmpty {
                    listSection
                }
                reviewSection
            }
            .navigationTitle("Añadir")
        }
        .task {
            await model.loadListsIfAllowed()
        }
        .alert(
            model.permissionExplanation?.title ?? "",
            isPresented: Binding(
                get: { model.permissionExplanation != nil },
                set: { if !$0 { model.permissionExplanation = nil } }
            ),
            presenting: model.permissionExplanation
        ) { _ in
            Button("Continuar") {
                Task { await model.save(explained: true) }
            }
            Button("Ahora no", role: .cancel) {}
        } message: { guidance in
            Text(guidance.message)
        }
        .confirmationDialog(
            "Ya no existe",
            isPresented: Binding(
                get: { model.missingRecord != nil },
                set: { if !$0 { model.missingRecord = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Crear de nuevo") {
                Task { await model.save(recreate: true) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Ya guardaste esta entrada, pero no se encuentra en \(model.kind.entity.appName): puede que la borraras. ¿Quieres crearla de nuevo?")
        }
        .confirmationDialog(
            "Intento sin confirmar",
            isPresented: Binding(
                get: { model.unconfirmedAttempt != nil },
                set: { if !$0 { model.unconfirmedAttempt = nil } }
            ),
            titleVisibility: .visible,
            presenting: model.unconfirmedAttempt
        ) { _ in
            // Crear puede dejar un duplicado: solo lo hace si el usuario lo pide tras revisarlo.
            Button("Crear igualmente") {
                Task { await model.save(createDespiteUnconfirmedAttempt: true) }
            }
            Button("No crear", role: .cancel) {}
        } message: { pending in
            Text(SaveError.unconfirmedPreviousAttempt(pending).userMessage)
        }
    }

    private var entrySection: some View {
        Section {
            Picker("Tipo", selection: $model.kind) {
                ForEach(ManualEntryViewModel.Kind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            TextField("Título", text: $model.title)
            TextField("Ubicación (opcional)", text: $model.location)
            TextField("Notas (opcional)", text: $model.notes, axis: .vertical)
        } footer: {
            Text(model.kind == .event
                 ? "Se guardará en Calendario."
                 : "Se guardará en Recordatorios. La ubicación se guarda como texto.")
        }
    }

    @ViewBuilder
    private var dateSection: some View {
        Section("Cuándo") {
            if model.kind == .event {
                DatePicker("Inicio", selection: $model.date, displayedComponents: [.date, .hourAndMinute])
                Picker("Duración", selection: $model.durationMinutes) {
                    Text("Elige…").tag(Int?.none)
                    ForEach(ManualEntryViewModel.durationChoices, id: \.self) { minutes in
                        Text("\(minutes) min").tag(Int?.some(minutes))
                    }
                }
            } else {
                Picker("Fecha", selection: $model.dateMode) {
                    ForEach(ManualEntryViewModel.DateMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                switch model.dateMode {
                case .none:
                    EmptyView()
                case .allDay:
                    DatePicker("Día", selection: $model.date, displayedComponents: .date)
                case .timed:
                    DatePicker("Día y hora", selection: $model.date, displayedComponents: [.date, .hourAndMinute])
                }
            }
        }
    }

    private var listSection: some View {
        Section("Lista") {
            Picker("Lista de Recordatorios", selection: $model.reminderListID) {
                Text("Predeterminada").tag(String?.none)
                ForEach(model.reminderLists) { list in
                    Text(list.title).tag(String?.some(list.id))
                }
            }
        }
    }

    @ViewBuilder
    private var reviewSection: some View {
        Section {
            Button("Revisar") {
                model.makeReview()
            }
            .disabled(!model.canReview)

            ForEach(model.problems, id: \.self) { problem in
                Label(problem, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            }

            if let review = model.review, model.isReviewCurrent {
                ForEach(review.summary, id: \.self) { line in
                    Text(line)
                }
                ForEach(review.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Button {
                    Task { await model.save() }
                } label: {
                    if model.isSaving {
                        ProgressView()
                    } else {
                        Text(model.kind == .event ? "Guardar en Calendario" : "Guardar en Recordatorios")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isSaving)
            } else if model.review != nil {
                Text("Has cambiado algún dato. Pulsa «Revisar» otra vez antes de guardar.")
                    .foregroundStyle(.secondary)
            }

            if let banner = model.banner {
                bannerView(banner)
            }
        } header: {
            Text("Revisión")
        } footer: {
            Text("No se guarda nada hasta que pulsas «Guardar». Si repites el guardado, no se crea un duplicado.")
        }
    }

    @ViewBuilder
    private func bannerView(_ banner: ManualEntryViewModel.Banner) -> some View {
        switch banner {
        case .success(let text):
            VStack(alignment: .leading, spacing: 8) {
                Label(text, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("Nueva entrada") {
                    model.reset()
                }
            }
        case .notice(let text):
            Label(text, systemImage: "info.circle")
                .foregroundStyle(.secondary)
        case .failure(let text):
            Label(text, systemImage: "xmark.octagon")
                .foregroundStyle(.red)
        case .access(let guidance):
            VStack(alignment: .leading, spacing: 8) {
                Label(guidance.title, systemImage: "lock")
                    .font(.headline)
                Text(guidance.message)
                    .font(.footnote)
                if guidance.action == .openSettings {
                    Button(guidance.actionTitle ?? "Abrir Ajustes") {
                        openAppSettings(using: openURL)
                    }
                }
            }
        }
    }
}
