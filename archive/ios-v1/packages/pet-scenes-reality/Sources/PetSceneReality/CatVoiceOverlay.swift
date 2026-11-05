import AVFoundation
import Foundation
import Observation
import Pet
import SwiftUI

/// What the cat says, for the view to show: a small bubble over its head with what it wants, for
/// a few seconds after each meow or yowl.
@MainActor @Observable
final class CatSay {
  struct Bubble: Equatable {
    let serial: Int
    /// SF Symbols, drawn in a row.
    let symbols: [String]
    let born: Date
    let loud: Bool
  }

  private(set) var bubble: Bubble?
  @ObservationIgnored private var serial = 0

  static let shown: TimeInterval = 2.6

  /// Shows what a cat that feels `feeling` says with `voice`.
  func say(_ voice: CatVoice, feeling: CatFeeling) {
    serial += 1
    bubble = Bubble(
      serial: serial, symbols: Self.symbols(voice, feeling: feeling), born: .now,
      loud: voice == .yowl)
  }

  func clear() { bubble = nil }

  /// What the bubble shows: a fish for food, two for a tantrum, a heart, a ball of yarn.
  static func symbols(_ voice: CatVoice, feeling: CatFeeling) -> [String] {
    let need: [String] =
      switch feeling.need {
      case .full: ["fish.fill"]
      case .loved: ["heart.fill"]
      case .playful: ["tennisball.fill"]
      case .rested: ["moon.zzz.fill"]
      case nil: ["heart.fill"]
      }
    switch voice {
    case .yowl: return need + ["exclamationmark"]
    case .meow, .chirp: return need
    }
  }
}

/// The bubble over the cat's head while it asks for something.
struct CatSayOverlay: View {
  let say: CatSay
  /// Where the cat is on screen now.
  let point: () -> CGPoint?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(.animation(paused: say.bubble == nil)) { context in
      if let bubble = say.bubble, let at = point() {
        let age = context.date.timeIntervalSince(bubble.born)
        let fade = min(1, age / 0.18) * min(1, max(0, (CatSay.shown - age) / 0.4))
        let shake = bubble.loud && !reduceMotion ? sin(age * 40) * 2 * max(0, 1 - age) : 0
        HStack(spacing: 2) {
          ForEach(Array(bubble.symbols.enumerated()), id: \.offset) { _, symbol in
            Image(systemName: symbol)
          }
        }
        .font(.system(size: bubble.loud ? 20 : 17, weight: .bold, design: .rounded))
        .foregroundStyle(Color(red: 0.95, green: 0.55, blue: 0.3))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(red: 1, green: 0.98, blue: 0.94), in: Capsule())
        .overlay(alignment: .bottomLeading) {
          Circle().fill(Color(red: 1, green: 0.98, blue: 0.94)).frame(width: 9, height: 9)
            .offset(x: 8, y: 9)
        }
        .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
        .scaleEffect(reduceMotion ? 1 : 0.7 + 0.3 * min(1, age / 0.18))
        .opacity(fade)
        .position(x: at.x + 44 + shake, y: at.y - 58)
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .task(id: say.bubble?.serial) {
      guard let serial = say.bubble?.serial else { return }
      try? await Task.sleep(for: .seconds(CatSay.shown))
      if say.bubble?.serial == serial { say.clear() }
    }
  }
}

/// The cat's voice, made in code: a meow is a few harmonics gliding up and down with the vowel
/// opening from "mi" to "ow", a yowl a longer, rougher one, a chirp a quick rising trill. Quiet,
/// and silent with the ringer off.
@MainActor
final class CatSounds {
  private var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  private var buffers: [CatVoice: AVAudioPCMBuffer] = [:]
  private var lastPlayed = -Double.infinity

  static let rate = 44_100.0

  /// Plays `voice`, unless one played less than a second ago.
  func play(_ voice: CatVoice, at clock: Double) {
    guard clock - lastPlayed > 1 else { return }
    lastPlayed = clock
    guard let player = start(), let buffer = buffer(voice) else { return }
    player.scheduleBuffer(buffer, at: nil, options: .interrupts)
    if !player.isPlaying { player.play() }
  }

  func stop() {
    player?.stop()
    engine?.stop()
  }

  private func start() -> AVAudioPlayerNode? {
    if let engine, let player, engine.isRunning { return player }
    #if os(iOS)
      // Ambient: under other audio, and silent with the ringer switch off.
      try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
      try? AVAudioSession.sharedInstance().setActive(true)
    #endif
    let engine = self.engine ?? AVAudioEngine()
    let player = self.player ?? AVAudioPlayerNode()
    if self.engine == nil {
      engine.attach(player)
      engine.connect(player, to: engine.mainMixerNode, format: Self.format)
      engine.mainMixerNode.outputVolume = 0.5
    }
    self.engine = engine
    self.player = player
    do {
      try engine.start()
    } catch {
      return nil
    }
    return player
  }

  private static let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)

  private func buffer(_ voice: CatVoice) -> AVAudioPCMBuffer? {
    if let buffer = buffers[voice] { return buffer }
    guard let format = Self.format else { return nil }
    let samples = Self.samples(voice)
    guard
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
      let channel = buffer.floatChannelData?[0]
    else { return nil }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    for (index, sample) in samples.enumerated() { channel[index] = sample }
    buffers[voice] = buffer
    return buffer
  }

  /// The shape of each sound: how long, the pitch at its start, peak and end, and how rough.
  struct Shape {
    var length: Double
    var start: Double
    var peak: Double
    var end: Double
    /// Where the pitch peaks, as a share of the length.
    var peakAt: Double
    var rough: Double
  }

  static func shape(_ voice: CatVoice) -> Shape {
    switch voice {
    case .meow: Shape(length: 0.62, start: 560, peak: 780, end: 470, peakAt: 0.3, rough: 0.05)
    case .yowl: Shape(length: 1.35, start: 430, peak: 640, end: 340, peakAt: 0.45, rough: 0.35)
    case .chirp: Shape(length: 0.2, start: 900, peak: 1350, end: 1250, peakAt: 0.7, rough: 0)
    }
  }

  /// The sound as samples from -1 to 1.
  static func samples(_ voice: CatVoice) -> [Float] {
    let shape = shape(voice)
    let count = Int(shape.length * rate)
    var out = [Float](repeating: 0, count: count)
    var phase = 0.0
    for index in 0..<count {
      let t = Double(index) / rate
      let x = t / shape.length
      // The pitch glides up to its peak and down again, with a little vibrato.
      let glide =
        x < shape.peakAt
        ? shape.start + (shape.peak - shape.start) * sin(.pi / 2 * x / shape.peakAt)
        : shape.peak + (shape.end - shape.peak)
          * sin(.pi / 2 * (x - shape.peakAt) / (1 - shape.peakAt))
      let f0 = glide * (1 + 0.012 * sin(2 * .pi * 6 * t))
      phase += 2 * .pi * f0 / rate
      // The vowel opens: bright harmonics early, the low ones late.
      let open = min(1, x * 1.6)
      var value = 0.0
      for harmonic in 1...7 {
        let h = Double(harmonic)
        let bright = 1 / h
        let round = exp(-(h - 1.5) * (h - 1.5) / 2)
        value += sin(phase * h) * (bright * (1 - open) + round * open)
      }
      // A yowl's roughness: the loudness wobbles fast.
      value *= 1 - shape.rough * (0.5 + 0.5 * sin(2 * .pi * 31 * t))
      let attack = min(1, t / 0.04)
      let release = min(1, (shape.length - t) / 0.16)
      out[index] = Float(value * 0.22 * attack * max(release, 0))
    }
    return out
  }
}
