import SwiftUI

struct RootTabView: View {
    let environment: AppEnvironment

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Hoy", systemImage: "sun.max") }
            CaptureView()
                .tabItem { Label("Añadir", systemImage: "plus.circle") }
            AgendaView()
                .tabItem { Label("Calendario", systemImage: "calendar") }
            RemindersOverviewView()
                .tabItem { Label("Recordatorios", systemImage: "bell") }
            SettingsView(environment: environment)
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
        }
    }
}
