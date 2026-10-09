import Combine
import RememberMeCore
import SwiftUI

/// Calendario: agenda de los próximos 7 días leída de Apple Calendar.
///
/// Muestra la explicación y el botón de permiso si el usuario no ha decidido, y un mensaje con
/// acceso a Ajustes si lo denegó o lo limitó a "solo añadir eventos". Se actualiza al volver
/// a la app y cuando Calendar cambia fuera de ella.
struct AgendaView: View {
    @State private var model: AgendaViewModel
    @Environment(\.scenePhase) private var scenePhase

    init(environment: AppEnvironment) {
        _model = State(initialValue: AgendaViewModel(environment: environment))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Calendario")
                .toolbar {
                    if model.isLoading {
                        ProgressView()
                    }
                }
        }
        .task {
            await model.reload()
        }
        .onChange(of: scenePhase) { _, phase in
            // Al volver de Ajustes el permiso puede haber cambiado.
            if phase == .active {
                Task { await model.reload() }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .eventStoreDidChange).receive(on: RunLoop.main)
        ) { _ in
            Task { await model.reload() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            ProgressView("Cargando agenda…")
        case .needsPermission:
            VStack(spacing: 12) {
                AccessGuidanceView(
                    guidance: AccessGuidance(entity: .events, permission: .notDetermined),
                    systemImage: "calendar.badge.exclamationmark"
                ) {
                    Task { await model.requestAccess() }
                }
                if let error = model.requestError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
            }
        case .unavailable(let permission):
            AccessGuidanceView(
                guidance: AccessGuidance(entity: .events, permission: permission),
                systemImage: "calendar.badge.exclamationmark"
            ) {
                Task { await model.requestAccess() }
            }
        case .empty:
            ContentUnavailableView(
                "Sin eventos",
                systemImage: "calendar",
                description: Text("No tienes eventos en los próximos 7 días.")
            )
            .refreshable { await model.reload() }
        case .loaded(let days):
            List {
                ForEach(days) { day in
                    Section(model.title(for: day.day)) {
                        ForEach(day.events) { event in
                            EventRow(event: event)
                        }
                    }
                }
            }
            .refreshable { await model.reload() }
        case .failed(let error):
            ContentUnavailableView {
                Label("No se pudo cargar la agenda", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.userMessage)
            } actions: {
                Button("Reintentar") {
                    Task { await model.reload() }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct EventRow: View {
    let event: CalendarEventSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title.isEmpty ? "Sin título" : event.title)
                .font(.body)
            HStack(spacing: 6) {
                if event.isAllDay {
                    Text("Todo el día")
                } else {
                    Text(event.start, format: .dateTime.hour().minute())
                    Text("–")
                    Text(event.end, format: .dateTime.hour().minute())
                }
                if let calendar = event.calendarTitle {
                    Text("· \(calendar)")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if let location = event.location, !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
