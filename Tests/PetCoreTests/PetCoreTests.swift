import Foundation
import Testing
@testable import PetCore

@Test func defaultsMatchRequestedBehavior() {
    let config = PetConfiguration()
    #expect(config.selectedPet == "builtin.blue-turtle")
    #expect(config.animation(for: .downstream) == .runLeft)
    #expect(config.animation(for: .upstream) == .runRight)
    #expect(config.animation(for: .stopped) == .failed)
    #expect(config.animation(for: .slowdown) == .failed)
    #expect(config.animation(for: .occasional) == .laptop)
}

@Test func ratesUseActualElapsedTimeAnd64BitValues() {
    var estimator = RateEstimator()
    #expect(estimator.sample(["en0": .init(received: 9_000_000_000, sent: 5)], at: 1) == nil)
    let rate = estimator.sample(["en0": .init(received: 9_000_006_000, sent: 1005)], at: 3)
    #expect(rate == NetworkRate(downstream: 3000, upstream: 500))
}

@Test func newRemovedAndResetInterfacesDoNotSpike() {
    var estimator = RateEstimator()
    _ = estimator.sample(["en0": .init(received: 100, sent: 100)], at: 1)
    #expect(estimator.sample(["en0": .init(received: 10, sent: 2), "en1": .init(received: 999_999, sent: 999)], at: 2) == .zero)
    #expect(estimator.sample(["en1": .init(received: 1_000_999, sent: 1099)], at: 3) == NetworkRate(downstream: 1000, upstream: 100))
    #expect(estimator.sample([:], at: 4) == .zero)
}

@Test func wakeGapRebaselinesCounters() {
    var estimator = RateEstimator()
    _ = estimator.sample(["en0": .init(received: 100, sent: 100)], at: 1)
    #expect(estimator.sample(["en0": .init(received: 900_000, sent: 900_000)], at: 200) == nil)
    #expect(estimator.sample(["en0": .init(received: 901_000, sent: 900_000)], at: 201)?.downstream == 1000)
}

@Test func startupIdleThenStopFiresOnceAfterGrace() {
    var detector = NetworkEventDetector()
    let settings = NetworkSettings()
    #expect(detector.consume(.zero, at: 0, settings: settings) == .idle)
    #expect(detector.consume(.init(downstream: 20_000, upstream: 100), at: 1, settings: settings) == .downstream)
    #expect(detector.consume(.zero, at: 2, settings: settings) == .downstream)
    #expect(detector.consume(.zero, at: 4, settings: settings) == .downstream)
    #expect(detector.consume(.zero, at: 5, settings: settings) == .stopped)
    #expect(detector.consume(.zero, at: 6, settings: settings) == .idle)
}

@Test func significantSlowdownDoesNotRepeatUntilRecovery() {
    var detector = NetworkEventDetector()
    let settings = NetworkSettings()
    _ = detector.consume(.init(downstream: 100_000, upstream: 0), at: 1, settings: settings)
    #expect(detector.consume(.init(downstream: 10_000, upstream: 0), at: 2, settings: settings) == .slowdown)
    #expect(detector.consume(.init(downstream: 10_000, upstream: 0), at: 3, settings: settings) == .downstream)
    _ = detector.consume(.init(downstream: 90_000, upstream: 0), at: 4, settings: settings)
    #expect(detector.consume(.init(downstream: 10_000, upstream: 0), at: 5, settings: settings) == .slowdown)
}

@Test func shortTrafficGapDoesNotProduceFailure() {
    var detector = NetworkEventDetector()
    let settings = NetworkSettings()
    _ = detector.consume(.init(downstream: 0, upstream: 20_000), at: 1, settings: settings)
    _ = detector.consume(.zero, at: 2, settings: settings)
    #expect(detector.consume(.init(downstream: 0, upstream: 20_000), at: 3, settings: settings) == .upstream)
    #expect(detector.consume(.zero, at: 4, settings: settings) == .upstream)
}

@Test func bidirectionalTrafficUsesHysteresis() {
    var detector = NetworkEventDetector()
    let settings = NetworkSettings()
    #expect(detector.consume(.init(downstream: 20_000, upstream: 18_000), at: 1, settings: settings) == .downstream)
    #expect(detector.consume(.init(downstream: 20_000, upstream: 22_000), at: 2, settings: settings) == .downstream)
    #expect(detector.consume(.init(downstream: 20_000, upstream: 30_000), at: 3, settings: settings) == .upstream)
}

@Test func failurePreemptsLaptopThenReturnsToLatestActivity() {
    var router = EventRouter()
    router.receive(.downstream, at: 0)
    router.receive(.occasional, at: 1, duration: 4, priority: 10)
    #expect(router.currentEvent(at: 2) == .occasional)
    router.receive(.stopped, at: 2, duration: 2.5, priority: 100)
    router.receive(.occasional, at: 3, duration: 4, priority: 10)
    router.receive(.upstream, at: 3)
    #expect(router.currentEvent(at: 4) == .stopped)
    #expect(router.currentEvent(at: 4.5) == .upstream)
    router.reset()
    #expect(router.currentEvent(at: 5) == .idle)
}

@Test func configurationRoundTripsAndClampsUnsafeValues() throws {
    var config = PetConfiguration()
    config.mappings[PetEvent.upstream.rawValue] = .laptop
    config.positionX = -1920; config.network.interface = "utun3"
    config.scale = 100; config.network.stopDelay = -1
    let decoded = try ConfigurationCodec.decode(ConfigurationCodec.encode(config))
    #expect(decoded.scale == 2)
    #expect(decoded.network.stopDelay == 1)
    #expect(decoded.positionX == -1920)
    #expect(decoded.network.interface == "utun3")
    #expect(decoded.animation(for: .upstream) == .laptop)
}

@Test func unsupportedAndCorruptConfigurationRejected() throws {
    var config = PetConfiguration(); config.schemaVersion = 99
    #expect(throws: ConfigurationError.self) { try ConfigurationCodec.decode(ConfigurationCodec.encode(config)) }
    #expect(throws: (any Error).self) { try ConfigurationCodec.decode(Data("bad json".utf8)) }
}

@Test func packPathsCannotEscapeTheirFolder() {
    for path in ["../secret.png", "/tmp/file.png", "images/../../file.png", "a//b.png", "https://a.png", "a\\b.png", "a.jpg"] {
        #expect(!PetPack.safeFramePath(path))
    }
    #expect(PetPack.safeFramePath("frames/idle/00.png"))
}

@Test func invalidFrameTimingsRejected() {
    var pet = PetPack.builtins[0]
    pet.clips["idle"] = SpriteClip(frames: ["frame.png"], framesPerSecond: 0)
    #expect(throws: PackError.self) { try pet.validate() }
    pet.clips["idle"] = SpriteClip(frames: ["frame.png"], framesPerSecond: 10, frameDurations: [0.1, 0.2])
    #expect(throws: PackError.self) { try pet.validate() }
}

@Test func originalVariableFrameTimingIsPreserved() {
    let clip = SpriteClip(frames: ["a.png", "b.png", "c.png"], framesPerSecond: 8, frameDurations: [1.68, 0.66, 0.84])
    #expect(clip.frameIndex(elapsed: 0) == 0)
    #expect(clip.frameIndex(elapsed: 1.67) == 0)
    #expect(clip.frameIndex(elapsed: 1.7) == 1)
    #expect(clip.frameIndex(elapsed: 2.5) == 2)
    #expect(clip.frameIndex(elapsed: 3.2) == 0)
}

@Test func systemCounterReaderWorksWithoutPacketCapture() throws {
    let counters = try SystemNetworkReader().read()
    #expect(!counters.keys.contains("lo0"))
    #expect(counters.keys.allSatisfy { !$0.isEmpty })
}
