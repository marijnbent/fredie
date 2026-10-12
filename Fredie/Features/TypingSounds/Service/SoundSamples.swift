import AVFoundation
import Foundation

enum SoundSamples {
    struct SampleSet: @unchecked Sendable {
        let down: KeySamples
        let up: KeySamples

        func buffers(for kind: KeystrokeKind, phase: KeystrokePhase) -> [AVAudioPCMBuffer] {
            let samples = phase == .down ? down : up
            return samples.buffers(for: kind)
        }
    }

    struct KeySamples {
        let character: [AVAudioPCMBuffer]
        let space: [AVAudioPCMBuffer]
        let delete: [AVAudioPCMBuffer]
        let enter: [AVAudioPCMBuffer]

        func buffers(for kind: KeystrokeKind) -> [AVAudioPCMBuffer] {
            switch kind {
            case .character:
                character
            case .space:
                space
            case .delete:
                delete
            case .enter:
                enter
            }
        }
    }

    private static var format: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    }

    static func makeSampleSet(profile: SoundProfile) -> SampleSet {
        SampleSet(
            down: makeKeySamples(profile: profile, phase: .down),
            up: makeKeySamples(profile: profile, phase: .up)
        )
    }

    private static func makeKeySamples(profile: SoundProfile, phase: KeystrokePhase) -> KeySamples {
        KeySamples(
            character: makeVariants(profile: profile, kind: .character, phase: phase, count: phase == .down ? 28 : 18),
            space: makeVariants(profile: profile, kind: .space, phase: phase, count: 8),
            delete: makeVariants(profile: profile, kind: .delete, phase: phase, count: 8),
            enter: makeVariants(profile: profile, kind: .enter, phase: phase, count: 8)
        )
    }

    private static func makeVariants(
        profile: SoundProfile,
        kind: KeystrokeKind,
        phase: KeystrokePhase,
        count: Int
    ) -> [AVAudioPCMBuffer] {
        (0..<count).compactMap { index in
            makeBuffer(
                profile: profile,
                kind: kind,
                phase: phase,
                seed: UInt64(index + 1 + (phase == .down ? 0 : 97)) * 1_103_515_245
            )
        }
    }

    private static func makeBuffer(
        profile: SoundProfile,
        kind: KeystrokeKind,
        phase: KeystrokePhase,
        seed: UInt64
    ) -> AVAudioPCMBuffer? {
        let format = Self.format
        var voice = SwitchVoice(profile: profile, kind: kind, phase: phase)
        let frameCount = AVAudioFrameCount(Double(voice.duration) * format.sampleRate)
        guard
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
            let channel = buffer.floatChannelData?[0]
        else {
            return nil
        }

        buffer.frameLength = frameCount
        var rng = SeededRandomGenerator(seed: seed)
        let sampleRate = Float(format.sampleRate)
        voice.pitch *= Float.random(in: 0.94...1.08, using: &rng)
        voice.casePitch *= Float.random(in: 0.92...1.06, using: &rng)
        voice.releaseDelay *= Float.random(in: 0.88...1.16, using: &rng)
        voice.amplitude *= Float.random(in: 0.82...1.0, using: &rng)

        var lowNoise: Float = 0
        var highNoiseSource: Float = 0
        var previousOutput: Float = 0

        for frame in 0..<Int(frameCount) {
            let t = Float(frame) / sampleRate
            let noise = Float.random(in: -1...1, using: &rng)
            lowNoise += voice.noiseDamping * (noise - lowNoise)
            highNoiseSource += 0.22 * (noise - highNoiseSource)
            let crispNoise = noise - highNoiseSource

            let downEnvelope = percussionEnvelope(t: t, attack: 0.0014, decay: voice.downDecay) * voice.downPresence
            let bottomEnvelope = delayedEnvelope(t: t, delay: voice.bottomDelay, attack: 0.0008, decay: voice.bottomDecay) * voice.downPresence
            let releaseEnvelope = delayedEnvelope(t: t, delay: voice.releaseDelay, attack: 0.0009, decay: voice.releaseDecay) * voice.upPresence
            let caseEnvelope = delayedEnvelope(t: t, delay: 0.004, attack: 0.003, decay: voice.caseDecay)

            let pitchBend = 1 + (0.08 * exp(-t * 70))
            let downTone = resonator(t: t, frequency: voice.pitch * pitchBend, damping: voice.toneDamping)
            let caseTone = resonator(t: t, frequency: voice.casePitch, damping: voice.caseDamping)
            let tickTone = resonator(t: t, frequency: voice.tickPitch, damping: 90)

            let down = ((downTone * 0.58) + (lowNoise * voice.lowNoise)) * downEnvelope * voice.downGain
            let bottom = ((caseTone * 0.62) + (crispNoise * voice.crispNoise)) * bottomEnvelope * voice.bottomGain
            let release = ((tickTone * 0.36) + (crispNoise * 0.72)) * releaseEnvelope * voice.releaseGain
            let caseBody = (caseTone + lowNoise * 0.4) * caseEnvelope * voice.caseGain
            let keybed = delayedEnvelope(t: t, delay: voice.bottomDelay + 0.012, attack: 0.004, decay: voice.keybedDecay)
                * lowNoise
                * voice.keybedGain

            var value = (down + bottom + release + caseBody + keybed) * voice.amplitude
            value = highPass(value, previous: previousOutput, amount: voice.highPass)
            previousOutput = value
            channel[frame] = tanh(value * 1.35) * 0.72
        }

        return buffer
    }

    private static func percussionEnvelope(t: Float, attack: Float, decay: Float) -> Float {
        let attackGain = min(1, t / attack)
        return attackGain * exp(-t * decay)
    }

    private static func delayedEnvelope(t: Float, delay: Float, attack: Float, decay: Float) -> Float {
        guard t >= delay else {
            return 0
        }

        let localTime = t - delay
        let attackGain = min(1, localTime / attack)
        return attackGain * exp(-localTime * decay)
    }

    private static func resonator(t: Float, frequency: Float, damping: Float) -> Float {
        sin(2 * .pi * frequency * t) * exp(-t * damping)
    }

    private static func highPass(_ value: Float, previous: Float, amount: Float) -> Float {
        value - (previous * amount)
    }
}
private struct SwitchVoice {
    var duration: Float
    var amplitude: Float
    var pitch: Float
    var casePitch: Float
    var tickPitch: Float
    var downDecay: Float
    var bottomDecay: Float
    var releaseDecay: Float
    var caseDecay: Float
    var keybedDecay: Float
    var toneDamping: Float
    var caseDamping: Float
    var noiseDamping: Float
    var lowNoise: Float
    var crispNoise: Float
    var downGain: Float
    var bottomGain: Float
    var releaseGain: Float
    var caseGain: Float
    var keybedGain: Float
    var bottomDelay: Float
    var releaseDelay: Float
    var highPass: Float
    var downPresence: Float
    var upPresence: Float

    init(profile: SoundProfile, kind: KeystrokeKind, phase: KeystrokePhase) {
        switch profile {
        case .deepThock:
            duration = 0.118
            amplitude = 0.52
            pitch = 118
            casePitch = 242
            tickPitch = 2_700
            downDecay = 62
            bottomDecay = 118
            releaseDecay = 180
            caseDecay = 34
            keybedDecay = 22
            toneDamping = 34
            caseDamping = 24
            noiseDamping = 0.055
            lowNoise = 0.55
            crispNoise = 0.24
            downGain = 0.92
            bottomGain = 0.72
            releaseGain = 0.16
            caseGain = 0.36
            keybedGain = 0.16
            bottomDelay = 0.009
            releaseDelay = 0.048
            highPass = 0.18
        case .glassTactile:
            duration = 0.104
            amplitude = 0.46
            pitch = 185
            casePitch = 390
            tickPitch = 3_650
            downDecay = 72
            bottomDecay = 145
            releaseDecay = 210
            caseDecay = 44
            keybedDecay = 30
            toneDamping = 42
            caseDamping = 32
            noiseDamping = 0.075
            lowNoise = 0.32
            crispNoise = 0.46
            downGain = 0.78
            bottomGain = 0.72
            releaseGain = 0.26
            caseGain = 0.22
            keybedGain = 0.08
            bottomDelay = 0.007
            releaseDelay = 0.040
            highPass = 0.24
        case .mutedThock:
            duration = 0.126
            amplitude = 0.50
            pitch = 96
            casePitch = 178
            tickPitch = 2_050
            downDecay = 52
            bottomDecay = 92
            releaseDecay = 132
            caseDecay = 25
            keybedDecay = 18
            toneDamping = 28
            caseDamping = 18
            noiseDamping = 0.038
            lowNoise = 0.72
            crispNoise = 0.12
            downGain = 1.00
            bottomGain = 0.62
            releaseGain = 0.10
            caseGain = 0.42
            keybedGain = 0.22
            bottomDelay = 0.011
            releaseDelay = 0.052
            highPass = 0.11
        case .speedClick:
            duration = 0.088
            amplitude = 0.42
            pitch = 210
            casePitch = 420
            tickPitch = 4_200
            downDecay = 92
            bottomDecay = 178
            releaseDecay = 250
            caseDecay = 58
            keybedDecay = 38
            toneDamping = 54
            caseDamping = 40
            noiseDamping = 0.090
            lowNoise = 0.22
            crispNoise = 0.52
            downGain = 0.66
            bottomGain = 0.68
            releaseGain = 0.28
            caseGain = 0.16
            keybedGain = 0.05
            bottomDelay = 0.006
            releaseDelay = 0.034
            highPass = 0.30
        case .creamyLinear:
            duration = 0.116
            amplitude = 0.47
            pitch = 128
            casePitch = 255
            tickPitch = 2_600
            downDecay = 60
            bottomDecay = 110
            releaseDecay = 168
            caseDecay = 32
            keybedDecay = 22
            toneDamping = 34
            caseDamping = 24
            noiseDamping = 0.050
            lowNoise = 0.52
            crispNoise = 0.18
            downGain = 0.88
            bottomGain = 0.70
            releaseGain = 0.14
            caseGain = 0.34
            keybedGain = 0.14
            bottomDelay = 0.009
            releaseDelay = 0.046
            highPass = 0.16
        case .classicTypewriter:
            duration = 0.142
            amplitude = 0.54
            pitch = 290
            casePitch = 780
            tickPitch = 4_600
            downDecay = 82
            bottomDecay = 138
            releaseDecay = 205
            caseDecay = 28
            keybedDecay = 18
            toneDamping = 48
            caseDamping = 22
            noiseDamping = 0.068
            lowNoise = 0.36
            crispNoise = 0.62
            downGain = 0.68
            bottomGain = 0.96
            releaseGain = 0.26
            caseGain = 0.28
            keybedGain = 0.12
            bottomDelay = 0.007
            releaseDelay = 0.044
            highPass = 0.34
        case .retroTerminal:
            duration = 0.074
            amplitude = 0.38
            pitch = 520
            casePitch = 1_050
            tickPitch = 5_200
            downDecay = 120
            bottomDecay = 220
            releaseDecay = 270
            caseDecay = 72
            keybedDecay = 48
            toneDamping = 74
            caseDamping = 58
            noiseDamping = 0.12
            lowNoise = 0.16
            crispNoise = 0.44
            downGain = 0.46
            bottomGain = 0.44
            releaseGain = 0.32
            caseGain = 0.10
            keybedGain = 0.02
            bottomDelay = 0.004
            releaseDelay = 0.024
            highPass = 0.42
        }

        downPresence = phase == .down ? 1 : 0
        upPresence = phase == .up ? 1 : 0

        if phase == .up {
            duration *= 0.58
            amplitude *= 0.72
            pitch *= 1.65
            casePitch *= 1.32
            tickPitch *= 1.18
            downGain = 0
            bottomGain = 0
            caseGain *= 0.16
            keybedGain = 0
            releaseGain *= 2.2
            releaseDelay = 0.001
            releaseDecay *= 1.18
            highPass *= 1.2
        }

        switch kind {
        case .character:
            break
        case .space:
            duration *= 1.16
            amplitude *= 0.88
            pitch *= 0.74
            casePitch *= 0.82
            downGain *= 0.82
            keybedGain *= 1.35
            bottomDelay += 0.004
        case .delete:
            duration *= 0.88
            amplitude *= 0.80
            pitch *= 1.18
            tickPitch *= 1.16
            releaseGain *= 1.3
            caseGain *= 0.7
        case .enter:
            duration *= 1.55
            amplitude *= 1.02
            pitch *= 0.62
            casePitch *= 0.70
            downGain *= 0.92
            bottomGain *= 1.12
            caseGain *= 1.35
            keybedGain *= 1.8
            releaseDelay += 0.022
        }
    }
}

struct MouseSamples: @unchecked Sendable {
    let primaryDown: [AVAudioPCMBuffer]
    let primaryUp: [AVAudioPCMBuffer]
    let secondaryDown: [AVAudioPCMBuffer]
    let secondaryUp: [AVAudioPCMBuffer]
    let otherDown: [AVAudioPCMBuffer]
    let otherUp: [AVAudioPCMBuffer]

    static func make() -> MouseSamples {
        MouseSamples(
            primaryDown: makeVariants(kind: .primary, phase: .down, count: 12),
            primaryUp: makeVariants(kind: .primary, phase: .up, count: 8),
            secondaryDown: makeVariants(kind: .secondary, phase: .down, count: 10),
            secondaryUp: makeVariants(kind: .secondary, phase: .up, count: 8),
            otherDown: makeVariants(kind: .other, phase: .down, count: 8),
            otherUp: makeVariants(kind: .other, phase: .up, count: 6)
        )
    }

    func buffers(for kind: MouseClickKind, phase: KeystrokePhase) -> [AVAudioPCMBuffer] {
        switch (kind, phase) {
        case (.primary, .down):
            primaryDown
        case (.primary, .up):
            primaryUp
        case (.secondary, .down):
            secondaryDown
        case (.secondary, .up):
            secondaryUp
        case (.other, .down):
            otherDown
        case (.other, .up):
            otherUp
        }
    }

    private static func makeVariants(kind: MouseClickKind, phase: KeystrokePhase, count: Int) -> [AVAudioPCMBuffer] {
        (0..<count).compactMap { index in
            makeBuffer(
                kind: kind,
                phase: phase,
                seed: UInt64(index + 211 + (phase == .down ? 0 : 53)) * 747_796_405
            )
        }
    }

    private static func makeBuffer(kind: MouseClickKind, phase: KeystrokePhase, seed: UInt64) -> AVAudioPCMBuffer? {
        let sampleRate: Double = 44_100
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let duration: Float = phase == .down ? 0.046 : 0.030
        let frameCount = AVAudioFrameCount(Double(duration) * sampleRate)
        guard
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
            let channel = buffer.floatChannelData?[0]
        else {
            return nil
        }

        buffer.frameLength = frameCount
        var rng = SeededRandomGenerator(seed: seed)
        let basePitch: Float
        let clickPitch: Float
        let bodyGain: Float
        switch kind {
        case .primary:
            basePitch = 540
            clickPitch = 3_900
            bodyGain = 0.34
        case .secondary:
            basePitch = 455
            clickPitch = 3_250
            bodyGain = 0.40
        case .other:
            basePitch = 650
            clickPitch = 4_500
            bodyGain = 0.26
        }

        let pitch = basePitch * Float.random(in: 0.93...1.08, using: &rng) * (phase == .up ? 1.42 : 1)
        let tick = clickPitch * Float.random(in: 0.90...1.12, using: &rng)
        let amplitude = Float.random(in: 0.72...0.95, using: &rng) * (phase == .down ? 0.38 : 0.24)
        var smoothedNoise: Float = 0

        for frame in 0..<Int(frameCount) {
            let t = Float(frame) / Float(sampleRate)
            let noise = Float.random(in: -1...1, using: &rng)
            smoothedNoise += 0.11 * (noise - smoothedNoise)
            let transient = max(0, 1 - (t * (phase == .down ? 420 : 680)))
            let bodyEnvelope = exp(-t * (phase == .down ? 95 : 145))
            let click = sin(2 * .pi * tick * t) * exp(-t * 260)
            let body = sin(2 * .pi * pitch * t) * bodyEnvelope * bodyGain
            let snap = (noise - smoothedNoise) * transient * 0.46
            let value = (click * 0.42 + body + snap) * amplitude
            channel[frame] = tanh(value * 1.5)
        }

        return buffer
    }
}

private struct SeededRandomGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}

@MainActor
final class SoundSampleLibrary {
    private var cachedProfiles: [(SoundProfile, SoundSamples.SampleSet)] = []
    private var mouseSamples: MouseSamples?

    func samples(for profile: SoundProfile) async -> SoundSamples.SampleSet? {
        guard !Task.isCancelled else { return nil }
        if let index = cachedProfiles.firstIndex(where: { $0.0 == profile }) {
            let cached = cachedProfiles.remove(at: index)
            cachedProfiles.append(cached)
            return cached.1
        }
        let samples = await Task.detached(priority: .utility) {
            SoundSamples.makeSampleSet(profile: profile)
        }.value
        guard !Task.isCancelled else { return nil }
        cachedProfiles.append((profile, samples))
        if cachedProfiles.count > 2 {
            cachedProfiles.removeFirst()
        }
        return samples
    }

    func mouse() async -> MouseSamples? {
        guard !Task.isCancelled else { return nil }
        if let mouseSamples { return mouseSamples }
        let samples = await Task.detached(priority: .utility) { MouseSamples.make() }.value
        guard !Task.isCancelled else { return nil }
        mouseSamples = samples
        return samples
    }
}
