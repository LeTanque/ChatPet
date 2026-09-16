import SwiftUI
import PetCore

struct PetView: View {
    @ObservedObject var model: AppModel
    var drag: ((CGSize, Bool) -> Void)?
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !model.isAnimating)) { _ in
            let elapsed = model.isAnimating ? max(0, ProcessInfo.processInfo.systemUptime - model.animationStarted) : 0
            let pet = model.currentPet
            if let clip = pet.manifest.clips[model.animation.rawValue],
               let frames = pet.images[model.animation.rawValue], !frames.isEmpty {
                Image(nsImage: frames[min(frames.count - 1, clip.frameIndex(elapsed: elapsed))])
                    .resizable().interpolation(.none).scaledToFit()
            } else {
                ProceduralPet(pack: pet.manifest, animation: model.animation, elapsed: elapsed)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 1).onChanged { drag?($0.translation, false) }.onEnded { drag?($0.translation, true) })
        .accessibilityLabel("\(model.currentPet.manifest.name), \(model.animation.title)")
        .help("Drag to move. Configure from the paw in the menu bar.")
    }
}

/// A lightweight vector fallback also makes palette-only pet packs useful.
private struct ProceduralPet: View {
    var pack: PetPack
    var animation: PetAnimation
    var elapsed: Double
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 192, y: size.height / 208)
            let running = animation.direction != 0
            let stride = running ? sin(elapsed * 16) * 9 : 0
            let bob = running ? abs(sin(elapsed * 16)) * 4 : sin(elapsed * 2) * 2
            let failed = animation == .failed
            let ink = Color(red: 0.16, green: 0.20, blue: 0.25)
            let body = Color(hex: pack.bodyColor)
            let accent = Color(hex: pack.accentColor)
            func shape(_ rect: CGRect, color: Color, radius: CGFloat = 12) {
                let p = Path(roundedRect: rect, cornerRadius: radius)
                context.fill(p, with: .color(color))
                context.stroke(p, with: .color(ink), lineWidth: 3)
            }
            func line(_ points: [CGPoint], color: Color = .primary, width: CGFloat = 3) {
                var path = Path(); path.addLines(points)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
            context.fill(Path(ellipseIn: CGRect(x: 40, y: 191, width: 112, height: 9)), with: .color(.black.opacity(0.12)))
            context.translateBy(x: 0, y: failed ? 10 : -bob)
            if animation == .runLeft { context.translateBy(x: 192, y: 0); context.scaleBy(x: -1, y: 1) }
            if pack.species != .robot {
                line([CGPoint(x: 56, y: 160), CGPoint(x: 30, y: 150), CGPoint(x: 28, y: 124 + stride / 2)], color: body, width: 17)
            }
            shape(CGRect(x: 57 + stride, y: 169, width: 30, height: 23), color: body)
            shape(CGRect(x: 104 - stride, y: 169, width: 30, height: 23), color: body)
            shape(CGRect(x: 54, y: 105, width: 85, height: 75), color: body, radius: 30)
            shape(CGRect(x: 69, y: 123, width: 55, height: 44), color: accent, radius: 20)
            if pack.species != .robot {
                for x: CGFloat in [46, 113] {
                    var ear = Path()
                    ear.addLines([CGPoint(x: x, y: 75), CGPoint(x: x + 7, y: pack.species == .fox ? 24 : 35), CGPoint(x: x + 37, y: 67)])
                    ear.closeSubpath(); context.fill(ear, with: .color(body)); context.stroke(ear, with: .color(ink), lineWidth: 3)
                }
            } else {
                line([CGPoint(x: 96, y: 52), CGPoint(x: 96, y: 32)], color: ink)
                shape(CGRect(x: 89, y: 23, width: 14, height: 14), color: accent)
            }
            shape(CGRect(x: 39, y: 53, width: 113, height: 81), color: body, radius: pack.species == .robot ? 20 : 33)
            if pack.species == .robot { shape(CGRect(x: 51, y: 73, width: 89, height: 42), color: ink, radius: 14) }
            let eyeColor = pack.species == .robot ? accent : ink
            let blink = elapsed.truncatingRemainder(dividingBy: 5) > 4.8
            for x: CGFloat in [73, 118] {
                if failed {
                    line([CGPoint(x: x - 5, y: 89), CGPoint(x: x + 5, y: 99)], color: eyeColor)
                    line([CGPoint(x: x + 5, y: 89), CGPoint(x: x - 5, y: 99)], color: eyeColor)
                } else {
                    context.fill(Path(roundedRect: CGRect(x: x - 4, y: 87, width: 8, height: blink ? 3 : 15), cornerRadius: 4), with: .color(eyeColor))
                }
            }
            if pack.species != .robot {
                line([CGPoint(x: 91, y: 108), CGPoint(x: 96, y: 112), CGPoint(x: 101, y: 108)], color: ink, width: 2)
            }
            if animation == .laptop {
                shape(CGRect(x: 91, y: 135, width: 74, height: 46), color: ink, radius: 5)
                line([CGPoint(x: 76, y: 183), CGPoint(x: 167, y: 183)], color: accent, width: 7)
                line([CGPoint(x: 122, y: 149), CGPoint(x: 130, y: 155), CGPoint(x: 122, y: 161)], color: accent)
            }
        }
    }
}

private extension Color {
    init(hex: String) {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0x80BFB0
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}
