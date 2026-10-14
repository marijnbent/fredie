import AVFoundation
import CoreAudio
import Foundation

@MainActor
final class SoundEngine {
    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private let sampleLibrary = SoundSampleLibrary()
    private let playback: ((AVAudioPCMBuffer, Float) -> Void)?
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayerIndex = 0
    private var samples: SoundSamples.SampleSet?
    private var mouseSamples: MouseSamples?
    private var sampleTask: Task<Void, Never>?
    private var mouseTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var pendingKeys: [(KeystrokeKind, KeystrokePhase)] = []
    private var pendingClicks: [(MouseClickKind, KeystrokePhase)] = []
    private var idleTimer: DispatchSourceTimer?
    private var cachedSystemOutputVolume: Double?
    private var lastSystemVolumeReadTime: TimeInterval?

    var profile: SoundProfile {
        didSet {
            if profile != oldValue {
                prepareSamples()
            }
        }
    }
    var downVolume: Double = 1.0
    var upVolume: Double = 0.32
    var mouseVolume: Double = 0.45
    var volume: Double = 0.65

    init(profile: SoundProfile = .creamyLinear, playback: ((AVAudioPCMBuffer, Float) -> Void)? = nil) {
        self.profile = profile
        self.playback = playback
        if playback == nil {
            engine.attach(mixer)
            engine.connect(mixer, to: engine.mainMixerNode, format: nil)
            for _ in 0..<16 {
                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: mixer, format: Self.format)
                players.append(player)
            }
            mixer.outputVolume = 1
        }
        prepareSamples()
    }

    func shutdown() {
        sampleTask?.cancel()
        sampleTask = nil
        mouseTask?.cancel()
        mouseTask = nil
        stop()
    }

    func stop() {
        idleTimer?.cancel()
        idleTimer = nil
        previewTask?.cancel()
        previewTask = nil
        pendingKeys.removeAll(keepingCapacity: true)
        pendingClicks.removeAll(keepingCapacity: true)
        players.forEach { $0.stop() }
        engine.stop()
        nextPlayerIndex = 0
    }

    private func prepareSamples() {
        sampleTask?.cancel()
        samples = nil
        pendingKeys.removeAll(keepingCapacity: true)
        let requestedProfile = profile
        sampleTask = Task { [weak self, sampleLibrary] in
            guard let samples = await sampleLibrary.samples(for: requestedProfile),
                  !Task.isCancelled,
                  let self,
                  self.profile == requestedProfile
            else { return }
            self.samples = samples
            self.sampleTask = nil
            let pending = self.pendingKeys
            self.pendingKeys.removeAll(keepingCapacity: true)
            for (kind, phase) in pending {
                self.play(kind, phase: phase)
            }
        }
    }

    func play(_ kind: KeystrokeKind, phase: KeystrokePhase) {
        let eventVolume = phase == .down ? downVolume : upVolume
        guard volume > 0, eventVolume > 0 else { return }
        guard let samples else {
            if pendingKeys.count < 16 { pendingKeys.append((kind, phase)) }
            return
        }
        guard let buffer = samples.buffers(for: kind, phase: phase).randomElement() else { return }
        play(buffer: buffer, volume: eventVolume, masterVolume: volume)
    }

    func playMouseClick(_ kind: MouseClickKind, phase: KeystrokePhase) {
        guard volume > 0, mouseVolume > 0 else { return }
        guard let mouseSamples else {
            if pendingClicks.count < 16 { pendingClicks.append((kind, phase)) }
            if mouseTask == nil {
                mouseTask = Task { [weak self, sampleLibrary] in
                    guard let samples = await sampleLibrary.mouse(), !Task.isCancelled, let self else { return }
                    self.mouseSamples = samples
                    self.mouseTask = nil
                    let pending = self.pendingClicks
                    self.pendingClicks.removeAll(keepingCapacity: true)
                    for (kind, phase) in pending {
                        self.playMouseClick(kind, phase: phase)
                    }
                }
            }
            return
        }
        guard let buffer = mouseSamples.buffers(for: kind, phase: phase).randomElement() else { return }
        play(buffer: buffer, volume: mouseVolume, masterVolume: volume)
    }

    func preview(profile: SoundProfile, volume: Double, downVolume: Double, upVolume: Double) {
        previewTask?.cancel()
        previewTask = Task { [weak self, sampleLibrary] in
            guard let samples = await sampleLibrary.samples(for: profile), !Task.isCancelled, let self else { return }
            if let buffer = samples.buffers(for: .character, phase: .down).randomElement() {
                self.play(buffer: buffer, volume: downVolume, masterVolume: volume)
            }
            do { try await Task.sleep(for: .milliseconds(75)) } catch { return }
            guard !Task.isCancelled else { return }
            if let buffer = samples.buffers(for: .character, phase: .up).randomElement() {
                self.play(buffer: buffer, volume: upVolume, masterVolume: volume)
            }
        }
    }

    func previewMouseClick(volume: Double) {
        previewTask?.cancel()
        let masterVolume = self.volume
        previewTask = Task { [weak self, sampleLibrary] in
            guard let samples = await sampleLibrary.mouse(), !Task.isCancelled, let self else { return }
            if let buffer = samples.buffers(for: .primary, phase: .down).randomElement() {
                self.play(buffer: buffer, volume: volume, masterVolume: masterVolume)
            }
            do { try await Task.sleep(for: .milliseconds(70)) } catch { return }
            guard !Task.isCancelled else { return }
            if let buffer = samples.buffers(for: .primary, phase: .up).randomElement() {
                self.play(buffer: buffer, volume: volume, masterVolume: masterVolume)
            }
        }
    }

    private func play(buffer: AVAudioPCMBuffer, volume: Double, masterVolume: Double) {
        guard volume > 0, masterVolume > 0 else { return }
        if let playback {
            playback(buffer, Float(min(volume, 1) * min(masterVolume, 1)))
            return
        }
        refreshSystemOutputVolumeIfNeeded()
        if !engine.isRunning {
            do {
                engine.prepare()
                try engine.start()
            } catch {
                NSLog("Ollie failed to start audio engine: \(error)")
                return
            }
        }
        let player = players[nextPlayerIndex]
        nextPlayerIndex = (nextPlayerIndex + 1) % players.count
        if player.isPlaying { player.stop() }
        player.volume = Float(min(volume, 1) * compensatedVolume(for: min(masterVolume, 1)))
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
        scheduleStop()
    }

    private func scheduleStop() {
        if idleTimer == nil {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.setEventHandler { [weak self] in
                Task { @MainActor [weak self] in self?.stop() }
            }
            idleTimer = timer
            timer.schedule(deadline: .now() + 2)
            timer.resume()
        } else {
            idleTimer?.schedule(deadline: .now() + 2)
        }
    }

    private func refreshSystemOutputVolumeIfNeeded() {
        let now = ProcessInfo.processInfo.systemUptime
        if let lastSystemVolumeReadTime,
           now - lastSystemVolumeReadTime < Self.systemVolumeCacheDuration {
            return
        }

        cachedSystemOutputVolume = Self.systemOutputVolume()
        lastSystemVolumeReadTime = now
    }

    private func compensatedVolume(for volume: Double) -> Double {
        guard
            volume > 0,
            let systemVolume = cachedSystemOutputVolume,
            systemVolume > 0
        else {
            return volume
        }

        return min(volume / systemVolume, 1)
    }

    private static func systemOutputVolume() -> Double? {
        var defaultDevice = AudioObjectID(0)
        var propertySize = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &defaultDevice
        ) == noErr else {
            return nil
        }

        var volume = Float32(0)
        propertySize = UInt32(MemoryLayout<Float32>.size)
        address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyData(
            defaultDevice,
            &address,
            0,
            nil,
            &propertySize,
            &volume
        ) == noErr else {
            return nil
        }

        return Double(volume)
    }

    private static let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private static let systemVolumeCacheDuration: TimeInterval = 2
}
