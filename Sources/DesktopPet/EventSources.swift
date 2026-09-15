import Foundation
import PetCore

enum SourceUpdate {
    case network(NetworkRate, PetEvent, [String])
    case event(PetEvent)
    case unavailable(String)
    case codex(CodexActivitySummary)
    case codexUnavailable(String)
}

@MainActor
protocol PetEventSource: AnyObject {
    func start(deliver: @escaping @MainActor (SourceUpdate) -> Void)
    func stop()
}

private actor CounterWorker {
    func read() throws -> [String: InterfaceCounters] { try SystemNetworkReader().read() }
}

@MainActor
final class NetworkEventSource: PetEventSource {
    private let settings: NetworkSettings
    private var task: Task<Void, Never>?
    private let worker = CounterWorker()
    init(settings: NetworkSettings) { self.settings = settings }
    func start(deliver: @escaping @MainActor (SourceUpdate) -> Void) {
        stop()
        task = Task { [settings, worker] in
            var estimator = RateEstimator()
            var detector = NetworkEventDetector()
            while !Task.isCancelled {
                do {
                    let all = try await worker.read()
                    guard !Task.isCancelled else { return }
                    let selected = all.filter { name, _ in
                        settings.interface.map { $0 == name } ?? name.hasPrefix("en")
                    }
                    if selected.isEmpty {
                        estimator.reset(); detector.reset()
                        deliver(.unavailable("No active monitored interface. Select one in Settings."))
                    } else {
                        let time = ProcessInfo.processInfo.systemUptime
                        let rate = estimator.sample(selected, at: time) ?? .zero
                        let event = detector.consume(rate, at: time, settings: settings)
                        deliver(.network(rate, event, all.keys.sorted()))
                    }
                } catch {
                    estimator.reset(); detector.reset()
                    deliver(.unavailable("Network monitor: \(error.localizedDescription)"))
                }
                do { try await Task.sleep(for: .seconds(settings.sampleInterval)) } catch { return }
            }
        }
    }
    func stop() { task?.cancel(); task = nil }
}

@MainActor
final class OccasionalEventSource: PetEventSource {
    private let interval: ClosedRange<Double>
    private var task: Task<Void, Never>?
    init(interval: ClosedRange<Double>) { self.interval = interval }
    func start(deliver: @escaping @MainActor (SourceUpdate) -> Void) {
        stop()
        task = Task { [interval] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(Double.random(in: interval))) } catch { return }
                guard !Task.isCancelled else { return }
                deliver(.event(.occasional))
            }
        }
    }
    func stop() { task?.cancel(); task = nil }
}

@MainActor
final class CodexEventSource: PetEventSource {
    private let settings: CodexSettings
    private var task: Task<Void, Never>?
    init(settings: CodexSettings) { self.settings = settings }
    func start(deliver: @escaping @MainActor (SourceUpdate) -> Void) {
        stop()
        let root = URL(fileURLWithPath: (settings.sessionsDirectory as NSString).expandingTildeInPath, isDirectory: true)
        let reader = CodexSessionReader(root: root)
        task = Task { [settings] in
            while !Task.isCancelled {
                do {
                    let summary = try await reader.poll(staleAfter: settings.staleAfter, reactionDuration: settings.reactionDuration)
                    guard !Task.isCancelled else { return }
                    deliver(.codex(summary))
                } catch {
                    guard !Task.isCancelled else { return }
                    deliver(.codexUnavailable(error.localizedDescription))
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
    func stop() { task?.cancel(); task = nil }
}
