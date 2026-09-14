import AppKit
import Combine
import SwiftUI
import PetCore

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published private(set) var configuration: PetConfiguration
    @Published private(set) var pets: [LoadedPet] = []
    @Published private(set) var animation: PetAnimation = .idle
    @Published private(set) var animationStarted = ProcessInfo.processInfo.systemUptime
    @Published private(set) var event: PetEvent = .idle
    @Published private(set) var rate = NetworkRate.zero
    @Published private(set) var interfaces: [String] = []
    @Published private(set) var networkStatus = "Starting network monitor…"
    @Published var message: String?
    let store: ConfigurationStore
    let library: PetLibrary
    private var sources: [any PetEventSource] = []
    private var router = EventRouter()
    private var timer: Timer?
    private var saveTask: Task<Void, Never>?
    private var preview: (PetAnimation, Double)?
    private var sleeping = false
    private var settingsWindow: NSWindow?
    private var petWindow: PetWindowController?
    private var canSave = true
    private var workspaceObservers: [NSObjectProtocol] = []
    var currentPet: LoadedPet {
        pets.first { $0.id == configuration.selectedPet } ?? pets.first ?? LoadedPet(manifest: PetPack.builtins[0])
    }
    var reducedMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var isAnimating: Bool { configuration.visible && !configuration.paused && !sleeping && !reducedMotion }

    init(store: ConfigurationStore = ConfigurationStore()) {
        self.store = store
        library = PetLibrary(directory: store.packsDirectory)
        do { configuration = try store.load() }
        catch {
            configuration = PetConfiguration()
            do {
                try store.preserveUnreadableFile()
                message = "Settings could not be read. The original was backed up; defaults are active."
            } catch {
                canSave = false
                message = "Settings could not be read or backed up. Changes will not be saved: \(error.localizedDescription)"
            }
        }
    }
    func start() {
        reloadPets()
        interfaces = (try? SystemNetworkReader().read().keys.sorted()) ?? []
        petWindow = PetWindowController(model: self)
        petWindow?.apply(configuration)
        restartSources()
        let tick = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick.tolerance = 0.005
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
        for (name, asleep) in [(NSWorkspace.willSleepNotification, true), (NSWorkspace.didWakeNotification, false)] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.sleeping = asleep
                    self?.objectWillChange.send()
                    self?.restartSources()
                }
            })
        }
    }
    func binding<Value>(_ keyPath: WritableKeyPath<PetConfiguration, Value>) -> Binding<Value> {
        Binding(get: { self.configuration[keyPath: keyPath] }, set: { value in
            self.update { $0[keyPath: keyPath] = value }
        })
    }
    func update(_ change: (inout PetConfiguration) -> Void) {
        let previous = configuration
        var new = configuration; change(&new); new.normalize(); configuration = new
        petWindow?.apply(configuration)
        if previous.network != new.network || previous.networkEnabled != new.networkEnabled ||
            previous.paused != new.paused || previous.visible != new.visible ||
            previous.occasionalEnabled != new.occasionalEnabled || previous.occasionalMinimum != new.occasionalMinimum ||
            previous.occasionalMaximum != new.occasionalMaximum {
            restartSources()
        }
        scheduleSave()
        tick()
    }
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            self?.save()
        }
    }
    func save() {
        guard canSave else { return }
        do { try store.save(configuration) }
        catch { message = "Could not save settings: \(error.localizedDescription)" }
    }
    func setPosition(_ point: NSPoint) {
        // Do not reapply the window while a user is dragging it.
        configuration.positionX = point.x; configuration.positionY = point.y
        scheduleSave()
    }
    func recenter() { petWindow?.recenter() }
    private func restartSources() {
        sources.forEach { $0.stop() }; sources = []; router.reset(); preview = nil; rate = .zero
        guard !configuration.paused, configuration.visible, !sleeping else {
            networkStatus = sleeping ? "Sleeping" : configuration.paused ? "Paused" : "Pet hidden"
            return
        }
        if configuration.networkEnabled {
            networkStatus = "Measuring network activity…"
            sources.append(NetworkEventSource(settings: configuration.network))
        } else { networkStatus = "Network trigger off" }
        if configuration.occasionalEnabled {
            sources.append(OccasionalEventSource(interval: configuration.occasionalMinimum...configuration.occasionalMaximum))
        }
        sources.forEach { source in source.start { [weak self] update in self?.receive(update) } }
    }
    private func receive(_ update: SourceUpdate) {
        switch update {
        case let .network(rate, event, names):
            self.rate = rate; interfaces = names; networkStatus = configuration.network.interface ?? "Automatic · active en* interfaces"
            if event == .stopped || event == .slowdown {
                router.receive(event, at: now, duration: configuration.network.failureDuration, priority: 100)
                if event == .stopped { router.receive(.idle, at: now) }
            } else { router.receive(event, at: now) }
        case let .event(event):
            router.receive(event, at: now, duration: configuration.occasionalDuration, priority: 10)
        case let .unavailable(reason):
            networkStatus = reason; rate = .zero; router.reset()
        }
        tick()
    }
    private var now: Double { ProcessInfo.processInfo.systemUptime }
    private func tick() {
        let event = router.currentEvent(at: now)
        if self.event != event { self.event = event }
        var desired = configuration.animation(for: event)
        if let override = preview {
            if override.1 > now { desired = override.0 } else { preview = nil }
        }
        if configuration.paused || sleeping { desired = .idle }
        if animation != desired { animation = desired; animationStarted = now }
        petWindow?.advance(direction: animation.direction, moving: isAnimating && configuration.movementEnabled)
    }
    func previewAnimation(_ value: PetAnimation) {
        if configuration.paused || !configuration.visible { update { $0.paused = false; $0.visible = true } }
        animationStarted = now; preview = (value, now + 6); tick()
    }
    func reloadPets() {
        library.reload(); pets = library.pets
        if !library.warnings.isEmpty { message = library.warnings.joined(separator: "\n") }
    }
    func importPet() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Choose a pet pack folder"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let id = try library.install(folder: url); pets = library.pets
            update { $0.selectedPet = id }
        } catch { message = error.localizedDescription; showSettings() }
    }
    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 720),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "DesktopPet Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: self))
            window.center(); settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func shutdown() {
        sources.forEach { $0.stop() }; timer?.invalidate(); saveTask?.cancel()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        if let origin = petWindow?.panel.frame.origin { configuration.positionX = origin.x; configuration.positionY = origin.y }
        save()
    }
}
