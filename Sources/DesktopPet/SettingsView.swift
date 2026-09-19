import SwiftUI
import PetCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                PetView(model: model).frame(width: 66, height: 72)
                VStack(alignment: .leading, spacing: 5) {
                    Text("DesktopPet").font(.title2.bold())
                    Text("A little companion for your Mac.").foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.animation.title).font(.caption).padding(8).background(.quaternary, in: Capsule())
            }.padding(20)
            if let message = model.message {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(message).font(.caption).textSelection(.enabled)
                    Spacer()
                    Button("Dismiss") { model.message = nil }
                }.padding(12).background(Color.orange.opacity(0.12))
            }
            TabView {
                petSettings.tabItem { Label("Pet", systemImage: "pawprint") }
                eventSettings.tabItem { Label("Events", systemImage: "bolt") }
                networkSettings.tabItem { Label("Network", systemImage: "network") }
            }.padding([.horizontal, .bottom], 16)
            HStack {
                Text(model.networkStatus).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button("Done") { NSApp.keyWindow?.close() }.keyboardShortcut(.defaultAction)
            }.padding(16)
        }.frame(width: 580, height: 720)
    }
    private var petSettings: some View {
        Form {
            Section("Your companion") {
                Picker("Pet", selection: model.binding(\.selectedPet)) {
                    ForEach(model.pets) { pet in Text(pet.manifest.name).tag(pet.id) }
                }
                HStack {
                    Text("Size")
                    Slider(value: model.binding(\.scale), in: 0.6...2, step: 0.1)
                    Text(model.configuration.scale, format: .percent.precision(.fractionLength(0))).monospacedDigit().frame(width: 48)
                }
                Toggle("Show desktop pet", isOn: model.binding(\.visible))
                Toggle("Pause activity", isOn: model.binding(\.paused))
                Toggle("Move across the desktop when running", isOn: model.binding(\.movementEnabled))
                Toggle("Let clicks pass through the pet", isOn: model.binding(\.clickThrough))
                Text("Drag the pet to place it. At screen edges, it runs in place. Reduce Motion in macOS stops frame animation and travel.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Recenter pet") { model.recenter() }
            }
            Section("Pet packs") {
                HStack {
                    Button("Import pet folder…") { model.importPet() }
                    Button("Reload packs") { model.reloadPets() }
                }
                Button("Open pet packs folder") { NSWorkspace.shared.open(model.store.packsDirectory) }
                Text("Import a folder containing pet.json and PNG frames (see the repo pets/ folder for Michelangelo). Blue Turtle and Michelangelo ship with the app; Mochi, Ember, and Pip are additional built-in pets.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var eventSettings: some View {
        Form {
            Section("When an event happens") {
                ForEach(PetEvent.allCases) { event in
                    HStack {
                        Picker(event.title, selection: Binding(get: {
                            model.configuration.animation(for: event, clipKeys: model.currentPet.clipKeys)
                        }, set: { value in
                            model.update { $0.mappings[event.rawValue] = value }
                        })) {
                            ForEach(model.currentPet.availableAnimations) { animation in
                                Text(animation.title).tag(animation)
                            }
                        }
                        Button {
                            model.previewAnimation(
                                model.configuration.animation(for: event, clipKeys: model.currentPet.clipKeys)
                            )
                        } label: {
                            Image(systemName: "play.fill")
                        }.help("Preview for six seconds").accessibilityLabel("Preview \(event.title)")
                    }
                }
                Button("Restore default mappings") { model.update { $0.mappings = [:] } }
            }
            Section("Occasional breaks") {
                Toggle("Occasionally play a short animation", isOn: model.binding(\.occasionalEnabled))
                numberField("Minimum interval (seconds)", \.occasionalMinimum)
                numberField("Maximum interval (seconds)", \.occasionalMaximum)
                numberField("Duration (seconds)", \.occasionalDuration)
                Text("Defaults: a 4-second laptop break every 45–100 seconds. Slowdown and stopped events take priority; the current activity resumes afterward.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var networkSettings: some View {
        Form {
            Section("Network activity") {
                Toggle("React to network traffic", isOn: model.binding(\.networkEnabled))
                Picker("Interface", selection: Binding(get: { model.configuration.network.interface ?? "" }, set: { value in
                    model.update { $0.network.interface = value.isEmpty ? nil : value }
                })) {
                    Text("Automatic (Wi-Fi / Ethernet)").tag("")
                    ForEach(Array(Set(model.interfaces + [model.configuration.network.interface].compactMap { $0 })).sorted(), id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    Label("↓ \(formatted(model.rate.downstream))/s", systemImage: "arrow.down.circle")
                    Spacer()
                    Label("↑ \(formatted(model.rate.upstream))/s", systemImage: "arrow.up.circle")
                }.monospacedDigit()
                Text("Automatic sums active en* interfaces and excludes loopback and VPN tunnels to reduce double counting. Select a single interface for VPN or other adapters. Counts include all apps, not just internet traffic.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Sensitivity") {
                numberField("Sample interval (seconds)", \.network.sampleInterval)
                numberField("Activity threshold (bytes/second)", \.network.activityThreshold)
                numberField("Slowdown ratio of burst peak", \.network.slowdownRatio)
                numberField("Stop grace period (seconds)", \.network.stopDelay)
                numberField("Failure animation (seconds)", \.network.failureDuration)
                Text("A drop below 25% of the current burst peak triggers slowdown. Traffic below 2 KB/s for 3 seconds triggers stopped. Startup silence stays idle. When both directions are active, the larger rate wins with a 20% switching margin.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Reset network defaults") { model.update { $0.network = NetworkSettings() } }
            }
            Text("Local interface counters only. No packet inspection, traffic logs, analytics, or network requests.")
                .font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }
    private func numberField(_ title: String, _ keyPath: WritableKeyPath<PetConfiguration, Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: model.binding(keyPath), format: .number.precision(.fractionLength(0...2)))
                .labelsHidden().multilineTextAlignment(.trailing).frame(width: 90)
        }
    }
    private func formatted(_ bytes: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(min(Double(Int64.max / 2), max(0, bytes))), countStyle: .binary)
    }
}
