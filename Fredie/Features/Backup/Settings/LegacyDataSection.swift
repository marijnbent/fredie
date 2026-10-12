import SwiftUI

struct LegacyDataSection: View {
    @Environment(LegacyDataCoordinator.self) private var adoption

    var body: some View {
        Section("Import Existing Apps") {
            ForEach(LegacyApp.allCases.filter { $0 != .notifications }, id: \.self) { app in
                LabeledContent {
                    if adoption.active == app { ProgressView().controlSize(.small) }
                    else { Button("Import…") { adoption.importData(app) }.disabled(adoption.active != nil || adoption.unavailable(app) != nil) }
                } label: {
                    Text(app.name)
                    if let message = adoption.status[app] ?? adoption.unavailable(app) { Text(message).foregroundStyle(.secondary) }
                }
            }
        }
    }
}
