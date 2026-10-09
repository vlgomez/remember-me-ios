import SwiftUI

struct RootTabView: View {
    let environment: AppEnvironment

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Hoy", systemImage: "sun.max") }
            CaptureView(environment: environment)
                .tabItem { Label("Añadir", systemImage: "plus.circle") }
            AgendaView(environment: environment)
                .tabItem { Label("Calendario", systemImage: "calendar") }
            RemindersOverviewView()
                .tabItem { Label("Recordatorios", systemImage: "bell") }
            SettingsView(environment: environment)
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
        }
    }
}
