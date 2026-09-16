import AppKit
import SwiftUI
import PetCore

@main
struct DesktopPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared
    var body: some Scene {
        MenuBarExtra("DesktopPet", systemImage: "pawprint.fill") {
            Text("\(model.currentPet.manifest.name) · \(model.animation.title)")
            Divider()
            Toggle("Show pet", isOn: model.binding(\.visible))
            Toggle("Pause", isOn: model.binding(\.paused))
            Picker("Choose pet", selection: model.binding(\.selectedPet)) {
                ForEach(model.pets) { pet in Text(pet.manifest.name).tag(pet.id) }
            }
            Menu("Preview animation") {
                ForEach(PetAnimation.allCases) { animation in
                    Button(animation.title) { model.previewAnimation(animation) }
                }
            }
            Button("Recenter pet") { model.recenter() }
            Divider()
            Button("Settings…") { model.showSettings() }.keyboardShortcut(",")
            Button("Import pet…") { model.importPet() }
            if model.message != nil { Button("View notice…") { model.showSettings() } }
            Divider()
            Button("Quit DesktopPet") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.showSettings() }.keyboardShortcut(",")
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let iconURL = Bundle.main.url(forResource: "ChatPetIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        AppModel.shared.start()
    }
    func applicationWillTerminate(_ notification: Notification) { AppModel.shared.shutdown() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppModel.shared.showSettings(); return false
    }
}
