import AppKit
import QuartzCore
import SwiftUI

enum MetaBurnCursor {
    static let flame: NSCursor = makeFlame()

    private static func makeFlame() -> NSCursor {
        let size = NSSize(width: 16, height: 24)
        let image = NSImage(size: size, flipped: false) { rect in
            let tip = NSPoint(x: rect.midX, y: 1.5)
            let path = NSBezierPath()
            path.move(to: tip)
            path.curve(
                to: NSPoint(x: rect.midX, y: rect.maxY - 1.5),
                controlPoint1: NSPoint(x: rect.minX - 1, y: 9),
                controlPoint2: NSPoint(x: rect.minX + 2, y: 18)
            )
            path.curve(
                to: tip,
                controlPoint1: NSPoint(x: rect.maxX - 2, y: 18),
                controlPoint2: NSPoint(x: rect.maxX + 1, y: 9)
            )
            NSGradient(
                colors: [
                    NSColor(red: 1.0, green: 0.96, blue: 0.62, alpha: 1),
                    NSColor(red: 1.0, green: 0.42, blue: 0.06, alpha: 1),
                    NSColor(red: 0.82, green: 0.08, blue: 0.04, alpha: 0.96),
                ]
            )?.draw(in: path, relativeCenterPosition: NSPoint(x: 0, y: -0.35))
            NSColor(red: 1, green: 0.92, blue: 0.55, alpha: 0.55).setStroke()
            path.lineWidth = 0.6
            path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height - 2))
    }
}

struct CursorTrailView: NSViewRepresentable {
    var reduceMotion: Bool

    func makeNSView(context: Context) -> CursorTrailNSView {
        let view = CursorTrailNSView()
        view.setReduceMotion(reduceMotion)
        return view
    }

    func updateNSView(_ nsView: CursorTrailNSView, context: Context) {
        nsView.setReduceMotion(reduceMotion)
    }

    static func dismantleNSView(_ nsView: CursorTrailNSView, coordinator: ()) {
        nsView.teardown()
    }
}

final class CursorTrailNSView: NSView {
    private let smoke = CAEmitterCell()
    private let ember = CAEmitterCell()
    private let emitter = CAEmitterLayer()
    private var monitor: Any?
    private var reduceMotion = false
    private var cursorPushed = false
    private var lastPoint = CGPoint.zero
    private var hasLastPoint = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            teardown()
            return
        }
        window?.acceptsMouseMovedEvents = true
        installMonitor()
        layoutEmitter()
    }

    override func layout() {
        super.layout()
        layoutEmitter()
    }

    func setReduceMotion(_ reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        emitter.isHidden = reduceMotion
        if reduceMotion {
            smoke.birthRate = 0
            ember.birthRate = 0
        }
    }

    func teardown() {
        popCursor()
        removeMonitor()
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true
        configureCells()
        emitter.emitterShape = .point
        emitter.emitterMode = .outline
        emitter.renderMode = .additive
        emitter.emitterCells = [smoke, ember]
        layer?.addSublayer(emitter)
    }

    private func layoutEmitter() {
        emitter.frame = bounds
    }

    private func configureCells() {
        smoke.contents = FireParticles.glowImage(
            color: NSColor(white: 0.78, alpha: 0.45), size: 28)
        smoke.lifetime = 0.55
        smoke.lifetimeRange = 0.12
        smoke.velocity = 38
        smoke.velocityRange = 10
        smoke.yAcceleration = 8
        smoke.scale = 0.12
        smoke.scaleRange = 0.06
        smoke.scaleSpeed = 0.55
        smoke.alphaSpeed = -1.6
        smoke.birthRate = 0
        smoke.color = CGColor(gray: 0.62, alpha: 0.28)

        ember.contents = FireParticles.glowImage(
            color: NSColor(red: 1, green: 0.45, blue: 0.08, alpha: 0.85))
        ember.lifetime = 0.18
        ember.lifetimeRange = 0.04
        ember.velocity = 8
        ember.velocityRange = 4
        ember.yAcceleration = -12
        ember.scale = 0.07
        ember.scaleRange = 0.03
        ember.alphaSpeed = -3.2
        ember.birthRate = 0
        ember.color = CGColor(red: 1, green: 0.28, blue: 0.05, alpha: 0.7)
    }

    private func handleMouse(_ event: NSEvent) {
        guard let window, event.window == window else {
            popCursor()
            smoke.birthRate = 0
            ember.birthRate = 0
            return
        }
        let local = convert(event.locationInWindow, from: nil)
        guard bounds.contains(local) else {
            popCursor()
            smoke.birthRate = 0
            ember.birthRate = 0
            hasLastPoint = false
            return
        }

        pushCursor()
        emitter.emitterPosition = local

        if reduceMotion {
            smoke.birthRate = 0
            ember.birthRate = 0
            lastPoint = local
            hasLastPoint = true
            return
        }

        let dx = local.x - lastPoint.x
        let dy = local.y - lastPoint.y
        let speed = hasLastPoint ? hypot(dx, dy) : 0
        if hasLastPoint, speed > 0.4 {
            smoke.emissionLongitude = atan2(dy, dx) + .pi
        }
        smoke.birthRate = Float(min(48, 8 + speed * 1.6))
        ember.birthRate = speed > 0.6 ? 18 : 8
        lastPoint = local
        hasLastPoint = true
    }

    private func pushCursor() {
        MetaBurnCursor.flame.set()
        cursorPushed = true
    }

    private func popCursor() {
        guard cursorPushed else { return }
        NSCursor.arrow.set()
        cursorPushed = false
    }

    private func installMonitor() {
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) {
            [weak self] event in
            self?.handleMouse(event)
            return event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
