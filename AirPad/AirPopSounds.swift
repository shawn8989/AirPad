//
//  AirPopSounds.swift
//  AirPad
//
//  Tiny synthesized sound-effects engine for AirPop. Every effect is rendered
//  to a PCM buffer at launch from pure math (sine sweeps + noise + decay
//  envelopes) — no audio assets, nothing to license, a few KB of RAM.
//  Plays through a small pool of player nodes so rapid pops overlap instead
//  of queueing. Ambient category: never interrupts the user's music.
//

import AVFoundation

final class AirPopSounds {
    static let shared = AirPopSounds()

    enum Effect: CaseIterable {
        case pop, golden, bomb, tick, gameOver, newBest
    }

    var muted: Bool {
        get { UserDefaults.standard.bool(forKey: "airpop.muted") }
        set { UserDefaults.standard.set(newValue, forKey: "airpop.muted") }
    }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [Effect: AVAudioPCMBuffer] = [:]
    private let sampleRate = 44_100.0
    private var started = false

    private init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        for _ in 0..<4 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            players.append(node)
        }
        buffers[.pop]      = render(duration: 0.10) { t, p in
            // Bright blip sweeping up, like a soap bubble giving way.
            let f = 620.0 + 500.0 * p
            return sinf(Float(2 * .pi * f * t)) * expf(Float(-18 * p)) * 0.8
        }
        buffers[.golden]   = render(duration: 0.32) { t, p in
            // Two-note chime (A5 → E6) with a shimmer.
            let f = p < 0.4 ? 880.0 : 1318.5
            let v = sinf(Float(2 * .pi * f * t)) + 0.3 * sinf(Float(4 * .pi * f * t))
            return v * expf(Float(-6 * p)) * 0.55
        }
        buffers[.bomb]     = render(duration: 0.35) { t, p in
            // Low thud plus a burst of noise.
            let boom = sinf(Float(2 * .pi * (110.0 - 40.0 * p) * t))
            let noise = Float.random(in: -1...1) * expf(Float(-24 * p)) * 0.5
            return (boom * expf(Float(-7 * p)) + noise) * 0.85
        }
        buffers[.tick]     = render(duration: 0.05) { t, p in
            sinf(Float(2 * .pi * 1050 * t)) * expf(Float(-30 * p)) * 0.5
        }
        buffers[.gameOver] = render(duration: 0.5) { t, p in
            // Descending slide.
            let f = 660.0 - 380.0 * p
            return sinf(Float(2 * .pi * f * t)) * expf(Float(-4 * p)) * 0.6
        }
        buffers[.newBest]  = render(duration: 0.55) { t, p in
            // Rising three-note fanfare (C6 E6 G6).
            let f: Double = p < 0.33 ? 1046.5 : (p < 0.66 ? 1318.5 : 1568.0)
            let v = sinf(Float(2 * .pi * f * t)) + 0.25 * sinf(Float(4 * .pi * f * t))
            return v * expf(Float(-3 * p)) * 0.55
        }
    }

    /// Renders `duration` seconds; the closure gets (time, progress 0...1).
    private func render(duration: Double, _ sample: (Double, Double) -> Float) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frames = AVAudioFrameCount(duration * sampleRate)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = frames
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            data[i] = sample(t, t / duration)
        }
        return buf
    }

    /// Call when the game screen appears; safe to call repeatedly.
    func prepare() {
        guard !started else { return }
        // Ambient + mixWithOthers: game blips never pause Music/podcasts.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        do {
            try engine.start()
            started = true
        } catch {
            // No audio is a degraded game, not a broken one.
        }
    }

    func stop() {
        guard started else { return }
        engine.stop()
        started = false
        // Hand the audio session back: leaving it active starves the mic and
        // silently breaks Dictation after a round of AirPop.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func play(_ effect: Effect) {
        guard !muted, started, let buffer = buffers[effect] else { return }
        let node = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        node.stop()
        node.scheduleBuffer(buffer, at: nil)
        node.play()
    }
}
