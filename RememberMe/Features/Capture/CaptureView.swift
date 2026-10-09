import SwiftUI

/// Añadir: campo de texto, micrófono y vista previa. La captura se implementa en la Fase C
/// y la voz en la Fase E.
struct CaptureView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Captura en preparación",
                systemImage: "text.cursor",
                description: Text("Aquí podrás escribir o dictar una tarea y revisar cómo se ha entendido antes de guardarla.")
            )
            .navigationTitle("Añadir")
        }
    }
}
