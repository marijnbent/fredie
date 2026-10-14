import SwiftUI

struct MediaImportSettingsView: View {
    @Environment(MediaImportCoordinator.self) private var mediaImport

    var body: some View {
        MediaImportSettingsContent(settings: mediaImport.state.settingsStore,
            ffmpeg: mediaImport.state.ffmpeg,
            onLocationsChanged: { mediaImport.state.refreshDestinations() },
            onError: { mediaImport.reportError($0) })
            .settingsScrollTarget(.mediaImport)
    }
}
