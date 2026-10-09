import SwiftUI

/// Recordatorios: avisos programados y reglas de anticipación (Fase D).
struct RemindersOverviewView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Sin avisos programados",
                systemImage: "bell.slash",
                description: Text("Aquí verás los avisos programados y podrás ajustar con cuánta antelación quieres recibirlos.")
            )
            .navigationTitle("Recordatorios")
        }
    }
}
