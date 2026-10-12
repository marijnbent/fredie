import SwiftUI

struct DictationSettingsView: View {
    private enum Pane: String, CaseIterable {
        case general = "Recording", shortcuts = "Shortcuts", enhancements = "Prompts", history = "History", logs = "Logs"
    }
    @Environment(DictationCoordinator.self) private var dictation
    @State private var pane = Pane.general

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if dictation.session.isRecording {
                    Button("Stop") { dictation.toggleRecording() }
                }
                if let conflict = dictation.conflict { Text("Shortcut already used by \(conflict)").foregroundStyle(.orange) }
                if let error = dictation.settings.credentialError { Text(error).foregroundStyle(.red) }
                if let error = dictation.session.historyPersistenceError { Text(error).foregroundStyle(.red) }
                Picker("Dictation settings", selection: $pane) {
                    ForEach(Pane.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
            }.padding(16)
            Divider()
            Group {
                switch pane {
                case .general: DictationGeneralSettingsView(viewModel: dictation.generalControls)
                case .shortcuts: ShortcutsSettingsView(viewModel: dictation.shortcutControls)
                case .enhancements: EnhancementsSettingsView(viewModel: dictation.enhancementControls)
                case .history: HistoryView(viewModel: dictation.historyControls)
                case .logs: LogsView(viewModel: dictation.logControls)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { dictation.prepareSettings() }
    }
}
