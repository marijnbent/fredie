import SwiftUI

struct LegacyAppNotice: View {
    @Environment(AppCore.self) private var core
    let app: LegacyApp

    var body: some View {
        if core.legacyApps.isRunning(app) {
            LabeledContent("Waiting for \(app.name) to quit") {
                Button("Quit \(app.name)") { core.legacyApps.requestQuit(app) }
            }
        }
    }
}
