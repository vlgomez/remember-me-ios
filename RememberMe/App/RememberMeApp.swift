import SwiftUI

@main
struct RememberMeApp: App {
    private let environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootTabView(environment: environment)
                .tint(.green)
        }
    }
}
