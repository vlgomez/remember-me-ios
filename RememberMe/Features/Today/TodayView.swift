import SwiftUI

/// Hoy: tareas pendientes, atrasadas y próximos avisos. Se conectará a Reminders en la Fase B.
struct TodayView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Nada pendiente",
                systemImage: "checkmark.circle",
                description: Text("Aquí verás las tareas de hoy, las atrasadas y los próximos avisos.")
            )
            .navigationTitle("Hoy")
        }
    }
}
