import SwiftUI

/// Ajustes: permisos, listas de destino, preferencias y privacidad.
/// En la Fase A solo muestra la configuración de fechas que usa la app.
struct SettingsView: View {
    let environment: AppEnvironment

    var body: some View {
        NavigationStack {
            List {
                Section("Fechas") {
                    LabeledContent("Zona horaria", value: environment.dates.timeZone.identifier)
                    LabeledContent("La semana empieza", value: "Lunes")
                }
                Section("Permisos") {
                    Text("El acceso a Calendario y Recordatorios se pedirá cuando actives esas funciones.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ajustes")
        }
    }
}
