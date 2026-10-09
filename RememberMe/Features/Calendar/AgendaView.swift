import SwiftUI

/// Calendario: agenda de eventos existentes. Necesita acceso a Calendar (Fase B).
struct AgendaView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Sin eventos",
                systemImage: "calendar",
                description: Text("Cuando des acceso al calendario, aquí aparecerá tu agenda.")
            )
            .navigationTitle("Calendario")
        }
    }
}
