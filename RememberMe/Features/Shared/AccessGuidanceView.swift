import RememberMeCore
import SwiftUI
import UIKit

/// Explica un estado de permiso y ofrece la única acción posible: pedir acceso (si el usuario
/// no ha decidido) o abrir Ajustes (si lo denegó o lo limitó). Con un permiso restringido no
/// muestra ningún botón, porque el usuario no puede cambiarlo.
struct AccessGuidanceView: View {
    let guidance: AccessGuidance
    let systemImage: String
    let onRequestAccess: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label(guidance.title, systemImage: systemImage)
        } description: {
            Text(guidance.message)
        } actions: {
            switch guidance.action {
            case .requestAccess:
                Button(guidance.actionTitle ?? "Permitir acceso", action: onRequestAccess)
                    .buttonStyle(.borderedProminent)
            case .openSettings:
                Button(guidance.actionTitle ?? "Abrir Ajustes") {
                    openAppSettings(using: openURL)
                }
                .buttonStyle(.bordered)
            case .noAction:
                EmptyView()
            }
        }
    }
}

/// Abre la página de Remember Me en Ajustes, donde están los permisos de Calendario y Recordatorios.
@MainActor
func openAppSettings(using openURL: OpenURLAction) {
    if let url = URL(string: UIApplication.openSettingsURLString) {
        openURL(url)
    }
}
