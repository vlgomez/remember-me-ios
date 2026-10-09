import Combine
import RememberMeCore
import SwiftUI

/// Ajustes: permisos de Calendario y Recordatorios, listas de Recordatorios, fechas y privacidad.
struct SettingsView: View {
    @State private var model: SettingsViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    init(environment: AppEnvironment) {
        _model = State(initialValue: SettingsViewModel(environment: environment))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PermissionRow(entity: .events, permission: model.calendarPermission) {
                        Task { await model.requestAccess(for: .events) }
                    } openSettings: {
                        openAppSettings(using: openURL)
                    }
                    PermissionRow(entity: .reminders, permission: model.remindersPermission) {
                        Task { await model.requestAccess(for: .reminders) }
                    } openSettings: {
                        openAppSettings(using: openURL)
                    }
                } header: {
                    Text("Permisos")
                } footer: {
                    if let error = model.requestError {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text("Remember Me solo pide acceso cuando pulsas «Permitir acceso». Si lo denegaste, puedes cambiarlo en Ajustes.")
                    }
                }

                Section("Listas de Recordatorios") {
                    reminderLists
                }

                Section("Fechas") {
                    LabeledContent("Zona horaria", value: model.environment.dates.timeZone.identifier)
                    LabeledContent("La semana empieza", value: "Lunes")
                }

                Section("Privacidad") {
                    Text("Tus eventos y recordatorios se guardan en Calendario y Recordatorios. Remember Me solo guarda en el iPhone una lista de los elementos que ha creado, para no duplicarlos; no guarda su contenido ni lo envía a ningún servidor.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ajustes")
        }
        .task {
            await model.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refresh() }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .eventStoreDidChange).receive(on: RunLoop.main)
        ) { _ in
            Task { await model.refresh() }
        }
    }

    @ViewBuilder
    private var reminderLists: some View {
        switch model.lists {
        case .idle:
            ProgressView()
        case .needsPermission, .unavailable:
            Text("Concede acceso total a Recordatorios para ver tus listas.")
                .foregroundStyle(.secondary)
        case .empty:
            Text("No tienes listas en Recordatorios.")
                .foregroundStyle(.secondary)
        case .loaded(let lists):
            ForEach(lists) { list in
                HStack {
                    Text(list.title)
                    Spacer()
                    if list.isDefault {
                        Text("Predeterminada")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !list.allowsModifications {
                        Text("Solo lectura")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        case .failed(let error):
            Text(error.userMessage)
                .foregroundStyle(.red)
        }
    }
}

private struct PermissionRow: View {
    let entity: EventStoreEntity
    let permission: EventStorePermission
    let requestAccess: () -> Void
    let openSettings: () -> Void

    var body: some View {
        let guidance = AccessGuidance(entity: entity, permission: permission)
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(entity.appName, value: permission.label)
            if permission != .fullAccess {
                Text(guidance.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            switch guidance.action {
            case .requestAccess:
                Button(guidance.actionTitle ?? "Permitir acceso", action: requestAccess)
                    .buttonStyle(.borderedProminent)
            case .openSettings:
                Button(guidance.actionTitle ?? "Abrir Ajustes", action: openSettings)
                    .buttonStyle(.bordered)
            case .noAction:
                EmptyView()
            }
        }
        .padding(.vertical, 2)
    }
}
