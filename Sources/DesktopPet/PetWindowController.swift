import AppKit
import SwiftUI
import PetCore

private final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PetWindowController {
    let panel: NSPanel
    private weak var model: AppModel?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var dragOrigin: NSPoint?
    private var screenObserver: NSObjectProtocol?
    init(model: AppModel) {
        self.model = model
        panel = PetPanel(contentRect: NSRect(x: 0, y: 0, width: 144, height: 156),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "DesktopPet Companion"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: PetView(model: model, drag: { [weak self] translation, ended in
            self?.drag(translation: translation, ended: ended)
        }))
        if let x = model.configuration.positionX, let y = model.configuration.positionY {
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else { recenter() }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.clampToScreen() }
        }
    }
    func apply(_ configuration: PetConfiguration) {
        panel.setContentSize(NSSize(width: 144 * configuration.scale, height: 156 * configuration.scale))
        panel.ignoresMouseEvents = configuration.clickThrough
        clampToScreen()
        if configuration.visible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }
    private var visibleScreen: NSRect {
        (NSScreen.screens.first { $0.visibleFrame.intersects(panel.frame) } ?? NSScreen.main)?.visibleFrame
        ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    }
    func clampToScreen() {
        let bounds = visibleScreen
        let origin = NSPoint(x: min(max(panel.frame.minX, bounds.minX), bounds.maxX - panel.frame.width),
                             y: min(max(panel.frame.minY, bounds.minY), bounds.maxY - panel.frame.height))
        panel.setFrameOrigin(origin)
    }
    func recenter() {
        let bounds = NSScreen.main?.visibleFrame ?? visibleScreen
        panel.setFrameOrigin(NSPoint(x: bounds.midX - panel.frame.width / 2, y: bounds.minY + 12))
        model?.setPosition(panel.frame.origin)
    }
    func advance(direction: Double, moving: Bool) {
        let time = ProcessInfo.processInfo.systemUptime
        let delta = min(0.1, max(0, time - lastTick)); lastTick = time
        guard moving, direction != 0, dragOrigin == nil else { return }
        let bounds = visibleScreen
        var x = panel.frame.minX + direction * 55 * delta
        // Stop at the edge instead of reversing the semantic upload/download direction.
        x = min(max(x, bounds.minX), bounds.maxX - panel.frame.width)
        if x != panel.frame.minX { panel.setFrameOrigin(NSPoint(x: x, y: panel.frame.minY)) }
    }
    private func drag(translation: CGSize, ended: Bool) {
        if dragOrigin == nil { dragOrigin = panel.frame.origin }
        guard let origin = dragOrigin else { return }
        panel.setFrameOrigin(NSPoint(x: origin.x + translation.width, y: origin.y - translation.height))
        if ended { dragOrigin = nil; clampToScreen(); model?.setPosition(panel.frame.origin) }
    }
}
