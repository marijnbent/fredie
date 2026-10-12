import AppKit
import Observation

@MainActor
@Observable
final class TypingSoundsCoordinator: HealthCheckable {
    private let settings: AppSettings
    @ObservationIgnored private let monitor = KeystrokeMonitor()
    @ObservationIgnored private var engine: SoundEngine?
    @ObservationIgnored private let ticker: HealthTicker
    var canRun: () -> Bool = { true }
    private(set) var isRunning = false
    var isRecording = false {
        didSet { apply() }
    }
    var isCapturingShortcut = false {
        didSet { apply() }
    }

    var isQuiet: Bool { isRecording || isCapturingShortcut }

    init(settings: AppSettings, ticker: HealthTicker) {
        self.settings = settings
        self.ticker = ticker
        monitor.onInput = { [weak self] event in self?.play(event) }
        monitor.onRunningStateChanged = { [weak self] running in self?.isRunning = running }
    }

    func apply() {
        guard settings.typingSoundsEnabled, canRun() else {
            stop()
            return
        }
        ticker.subscribe(self)
        guard !isQuiet else {
            monitor.stop()
            engine?.stop()
            isRunning = false
            return
        }
        monitor.includeMouseClicks = settings.typingMouseEnabled
        if !monitor.isRunning || monitor.needsRestartForInputSelection {
            isRunning = monitor.start()
        }
        configureEngine()
    }

    func stop() {
        ticker.unsubscribe(self)
        monitor.stop()
        engine?.shutdown()
        engine = nil
        isRunning = false
    }

    func healthCheck() {
        guard settings.typingSoundsEnabled, !isQuiet else { return }
        if !monitor.isRunning { apply() }
    }

    func requestAccess() {
        KeystrokeMonitor.requestInputMonitoringAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    func preview() {
        guard !isRecording else { return }
        configureEngine()
        engine?.preview(
            profile: SoundProfile(rawValue: settings.typingSoundProfile) ?? .creamyLinear,
            volume: Double(settings.typingSoundVolume) / 100,
            downVolume: Double(settings.typingSoundDownVolume) / 100,
            upVolume: Double(settings.typingSoundUpVolume) / 100)
    }

    private func configureEngine() {
        let profile = SoundProfile(rawValue: settings.typingSoundProfile) ?? .creamyLinear
        if engine == nil { engine = SoundEngine(profile: profile) }
        engine?.profile = profile
        engine?.volume = Double(settings.typingSoundVolume) / 100
        engine?.downVolume = Double(settings.typingSoundDownVolume) / 100
        engine?.upVolume = Double(settings.typingSoundUpVolume) / 100
        engine?.mouseVolume = Double(settings.typingMouseVolume) / 100
    }

    private func play(_ event: InputSoundEvent) {
        guard settings.typingSoundsEnabled, !isQuiet, isRunning else { return }
        switch event {
        case .key(let kind, let phase): engine?.play(kind, phase: phase)
        case .mouse(let kind, let phase):
            if settings.typingMouseEnabled { engine?.playMouseClick(kind, phase: phase) }
        }
    }
}
