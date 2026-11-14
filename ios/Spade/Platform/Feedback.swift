import AVFoundation
import UIKit

// What the player hears and feels. Each call pairs a short sound with a tap
// from the phone's haptic motor, the way built-in iPhone apps do.

@MainActor
enum Feedback {
    static var soundOn = true
    static var hapticsOn = true

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notice = UINotificationFeedbackGenerator()

    /// Gets the sounds and the haptic motor ready ahead of the first touch, so that touch doesn't lag.
    static func prepare() {
        if hapticsOn {
            light.prepare()
            selection.prepare()
        }
        if soundOn { Synth.shared.warmUp() }
    }

    /// An ordinary button press.
    static func tap() {
        if hapticsOn { light.impactOccurred() }
        if soundOn { Synth.shared.play(.tap) }
    }

    /// Picking one option from several: felt, but silent.
    static func select() {
        if hapticsOn { selection.selectionChanged() }
    }

    /// A counted quest moved one step.
    static func step() {
        if hapticsOn { medium.impactOccurred() }
        if soundOn { Synth.shared.play(.step) }
    }

    /// A quest was sealed.
    static func done() {
        if hapticsOn { notice.notificationOccurred(.success) }
        if soundOn { Synth.shared.play(.done) }
    }

    /// Every daily quest finished.
    static func clear() {
        if hapticsOn { notice.notificationOccurred(.success) }
        if soundOn { Synth.shared.play(.clear) }
    }

    /// The ground breaks.
    static func dig() {
        if hapticsOn { heavy.impactOccurred() }
        if soundOn { Synth.shared.play(.dig) }
    }

    /// The lockbox opens.
    static func reveal() {
        if hapticsOn { medium.impactOccurred() }
        if soundOn { Synth.shared.play(.reveal) }
    }

    static func level() {
        if hapticsOn { notice.notificationOccurred(.success) }
        if soundOn { Synth.shared.play(.level) }
    }

    static func feat() {
        if hapticsOn { light.impactOccurred() }
        if soundOn { Synth.shared.play(.feat) }
    }

    /// Something was refused (a save that wouldn't load, for instance).
    static func warn() {
        if hapticsOn { notice.notificationOccurred(.warning) }
    }
}

/// Sound effects, made from scratch. There are no sound files: each effect is a
/// few notes built from simple waves, shaped so they fade out like a plucked string.
///
/// Everything here runs on its own queue, off the main thread. Starting the
/// phone's audio system can take a moment, and the screen must never wait for it.
final class Synth: @unchecked Sendable {
    static let shared = Synth()
    private let queue = DispatchQueue(label: "spade.synth", qos: .userInitiated)

    enum Effect: CaseIterable {
        case tap, step, done, clear, dig, reveal, level, feat
    }

    private struct Note {
        enum Wave { case triangle, sine, square }
        var freq: Double
        /// Seconds after the effect starts.
        var at: Double
        /// How long the note rings.
        var length: Double
        var volume: Double = 0.5
        var wave: Wave = .triangle
        /// Slide to this pitch over the note's length.
        var slideTo: Double?
    }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [Effect: AVAudioPCMBuffer] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var nextPlayer = 0
    private var ready = false

    private init() {}

    private func score(_ effect: Effect) -> (notes: [Note], thumps: [(at: Double, length: Double, volume: Double)]) {
        switch effect {
        case .tap:
            return ([Note(freq: 520, at: 0, length: 0.05, volume: 0.25, wave: .square)], [])
        case .step:
            return ([Note(freq: 392, at: 0, length: 0.12, volume: 0.4)], [])
        case .done:
            return ([Note(freq: 440, at: 0, length: 0.16), Note(freq: 660, at: 0.07, length: 0.26)], [])
        case .clear:
            return ([Note(freq: 440, at: 0, length: 0.16), Note(freq: 587, at: 0.09, length: 0.16), Note(freq: 784, at: 0.18, length: 0.4)], [])
        case .dig:
            return ([Note(freq: 130, at: 0, length: 0.3, volume: 0.9, wave: .sine, slideTo: 46)], [(0, 0.28, 0.9), (0.34, 0.22, 0.5)])
        case .reveal:
            return ([
                Note(freq: 392, at: 0, length: 0.2),
                Note(freq: 494, at: 0.09, length: 0.2),
                Note(freq: 622, at: 0.18, length: 0.22),
                Note(freq: 831, at: 0.27, length: 0.7, volume: 0.6),
                Note(freq: 415, at: 0.27, length: 0.7, volume: 0.3, wave: .sine),
            ], [])
        case .level:
            return ([
                Note(freq: 294, at: 0, length: 0.18),
                Note(freq: 440, at: 0.1, length: 0.18),
                Note(freq: 554, at: 0.2, length: 0.18),
                Note(freq: 740, at: 0.3, length: 0.24),
                Note(freq: 880, at: 0.44, length: 0.9, volume: 0.6),
                Note(freq: 440, at: 0.44, length: 0.9, volume: 0.3, wave: .sine),
            ], [])
        case .feat:
            return ([Note(freq: 988, at: 0, length: 0.14, volume: 0.35), Note(freq: 1319, at: 0.08, length: 0.4, volume: 0.35)], [])
        }
    }

    /// Works out the sound wave for an effect, sample by sample.
    private func render(_ effect: Effect) -> AVAudioPCMBuffer? {
        let (notes, thumps) = score(effect)
        let rate = format.sampleRate
        let end = max(notes.map { $0.at + $0.length }.max() ?? 0, thumps.map { $0.at + $0.length }.max() ?? 0) + 0.05
        let frames = AVAudioFrameCount(end * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames), let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) { channel[i] = 0 }

        for note in notes {
            let first = Int(note.at * rate)
            let count = Int(note.length * rate)
            let peak = note.volume * 0.22
            var phase = 0.0
            for n in 0..<count where first + n < Int(frames) {
                let p = Double(n) / Double(count)
                // The pitch may slide; the phase adds up a little each sample.
                let freq = note.slideTo.map { note.freq * pow($0 / note.freq, p) } ?? note.freq
                phase += freq / rate
                let cycle = phase - phase.rounded(.down)
                let wave: Double
                switch note.wave {
                case .sine: wave = sin(cycle * 2 * .pi)
                case .square: wave = cycle < 0.5 ? 1 : -1
                case .triangle: wave = 4 * abs(cycle - 0.5) - 1
                }
                // A very quick rise, then a smooth fade to silence.
                let seconds = Double(n) / rate
                let attack = min(1, seconds / 0.008)
                let fade = pow(0.0001 / peak, p)
                channel[first + n] += Float(wave * peak * attack * fade)
            }
        }

        // Thumps: short bursts of muffled hiss, for earthy sounds.
        for thump in thumps {
            let first = Int(thump.at * rate)
            let count = Int(thump.length * rate)
            var smoothed = 0.0
            for n in 0..<count where first + n < Int(frames) {
                let fade = pow(1 - Double(n) / Double(count), 2)
                smoothed += (Double.random(in: -1...1) - smoothed) * 0.12
                channel[first + n] += Float(smoothed * fade * thump.volume * 0.5)
            }
        }
        return buffer
    }

    private func start() {
        guard !ready else { return }
        do {
            // "Ambient" respects the silent switch and doesn't interrupt music.
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            if players.isEmpty {
                for _ in 0..<4 {
                    let player = AVAudioPlayerNode()
                    engine.attach(player)
                    engine.connect(player, to: engine.mainMixerNode, format: format)
                    players.append(player)
                }
            }
            try engine.start()
            if buffers.isEmpty {
                for effect in Effect.allCases { buffers[effect] = render(effect) }
            }
            ready = true
        } catch {
            ready = false
        }
    }

    /// Builds the sounds now instead of on the first one played.
    func warmUp() {
        queue.async { self.start() }
    }

    func play(_ effect: Effect) {
        queue.async { self.playNow(effect) }
    }

    private func playNow(_ effect: Effect) {
        start()
        guard ready, let buffer = buffers[effect] else { return }
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()
    }
}
