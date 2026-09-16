import AppKit
import QuartzCore
import SwiftUI

enum FireMood {
    case idle
    case dragging
    case burning

    var intensity: Float {
        switch self {
        case .idle: 0.7
        case .dragging: 0.85
        case .burning: 1.05
        }
    }

    var emberBirthRate: Float {
        switch self {
        case .idle: 5
        case .dragging: 9
        case .burning: 14
        }
    }
}

@MainActor
final class FireStageController {
    private weak var stage: FireStageNSView?

    func bind(_ stage: FireStageNSView) {
        self.stage = stage
    }

    func unbind(_ stage: FireStageNSView) {
        if self.stage === stage {
            self.stage = nil
        }
    }

    func setMood(_ mood: FireMood) {
        stage?.setMood(mood)
    }

    func burst(at point: CGPoint, count: Int) {
        stage?.burstFromSwiftUI(point, count: count)
    }

    func celebrate() {
        stage?.celebrate()
    }

    func setLight(_ isLight: Bool) {
        stage?.setLight(isLight)
    }

    func setReduceMotion(_ reduceMotion: Bool) {
        stage?.setReduceMotion(reduceMotion)
    }
}

struct FireStageView: NSViewRepresentable {
    let controller: FireStageController
    var isLight: Bool
    var reduceMotion: Bool

    func makeNSView(context: Context) -> FireStageNSView {
        let view = FireStageNSView()
        controller.bind(view)
        view.setLight(isLight)
        view.setReduceMotion(reduceMotion)
        return view
    }

    func updateNSView(_ nsView: FireStageNSView, context: Context) {
        controller.bind(nsView)
        nsView.setLight(isLight)
        nsView.setReduceMotion(reduceMotion)
    }

    static func dismantleNSView(_ nsView: FireStageNSView, coordinator: ()) {
        nsView.teardown()
    }
}

final class FireStageNSView: NSView {
    private var renderer: FireRenderer?
    private let fallback = StaticFireView()
    private let particleHost = NSView()
    private let ambientLayer = CAEmitterLayer()
    private let burstLayer = CAEmitterLayer()
    private let ambientEmber = CAEmitterCell()
    private let smokeCell = CAEmitterCell()
    private let burstEmber = CAEmitterCell()
    private var mood: FireMood = .idle
    private var isLight = false
    private var reduceMotion = false

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
        renderer?.updatePausedState()
        layoutEmitters()
    }

    override func layout() {
        super.layout()
        renderer?.frame = bounds
        fallback.frame = bounds
        particleHost.frame = bounds
        layoutEmitters()
    }

    func setMood(_ mood: FireMood) {
        self.mood = mood
        renderer?.targetIntensity = mood.intensity
        updateEmitterRates()
    }

    func setLight(_ isLight: Bool) {
        self.isLight = isLight
        renderer?.isLight = isLight
        fallback.isLight = isLight
    }

    func setReduceMotion(_ reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        renderer?.reduceMotion = reduceMotion
        applyPresentationMode()
        renderer?.updatePausedState()
        updateEmitterRates()
    }

    func burstFromSwiftUI(_ point: CGPoint, count: Int) {
        let local = CGPoint(x: point.x, y: bounds.height - point.y)
        burst(at: local, count: max(1, count))
    }

    func celebrate() {
        burst(at: CGPoint(x: bounds.midX, y: 56), count: 8)
    }

    func teardown() {
        renderer?.delegate = nil
        renderer?.isPaused = true
    }

    private func burst(at point: CGPoint, count: Int) {
        guard !reduceMotion else { return }
        renderer?.triggerBurst(at: point)
        burstLayer.emitterPosition = point
        smokeCell.birthRate = Float(6 + min(count, 12))
        burstEmber.birthRate = Float(8 + min(count, 12))
        burstLayer.birthRate = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.burstLayer.birthRate = 0
            self.smokeCell.birthRate = 0
            self.burstEmber.birthRate = 0
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        let renderer = FireRenderer(frame: bounds, device: nil)
        self.renderer = renderer
        addSubview(renderer)

        fallback.frame = bounds
        fallback.autoresizingMask = [.width, .height]
        addSubview(fallback)

        particleHost.wantsLayer = true
        particleHost.layer?.masksToBounds = true
        addSubview(particleHost)
        particleHost.layer?.addSublayer(ambientLayer)
        particleHost.layer?.addSublayer(burstLayer)
        configureEmitters()
        applyPresentationMode()
    }

    private func applyPresentationMode() {
        let useLive = !reduceMotion && (renderer?.isReady == true)
        renderer?.isHidden = !useLive
        fallback.isHidden = useLive
        particleHost.isHidden = !useLive
        if !useLive {
            ambientLayer.birthRate = 0
            burstLayer.birthRate = 0
        }
    }

    private func configureEmitters() {
        ambientLayer.emitterShape = .rectangle
        ambientLayer.emitterMode = .surface
        ambientLayer.renderMode = .additive
        configure(ambientEmber, birthRate: FireMood.idle.emberBirthRate)
        ambientLayer.emitterCells = [ambientEmber]

        burstLayer.emitterShape = .point
        burstLayer.emitterMode = .outline
        burstLayer.renderMode = .unordered
        burstLayer.birthRate = 0
        configureSmoke(smokeCell)
        configureBurstEmber(burstEmber)
        burstLayer.emitterCells = [smokeCell, burstEmber]
    }

    private func layoutEmitters() {
        ambientLayer.frame = particleHost.bounds
        burstLayer.frame = particleHost.bounds
        ambientLayer.emitterPosition = CGPoint(x: bounds.midX, y: bounds.height * 0.38)
        ambientLayer.emitterSize = CGSize(
            width: max(40, bounds.width * 0.94), height: max(40, bounds.height * 0.7))
    }

    private func updateEmitterRates() {
        guard !reduceMotion else {
            ambientLayer.birthRate = 0
            return
        }
        ambientLayer.birthRate = 1
        ambientEmber.birthRate = mood.emberBirthRate
    }

    private func configure(_ cell: CAEmitterCell, birthRate: Float) {
        cell.contents = FireParticles.glowImage(
            color: NSColor(red: 1.0, green: 0.55, blue: 0.12, alpha: 0.9))
        cell.birthRate = birthRate
        cell.lifetime = 4.2
        cell.lifetimeRange = 1.2
        cell.velocity = 10
        cell.velocityRange = 6
        cell.yAcceleration = -14
        cell.emissionLongitude = .pi / 2
        cell.emissionRange = 0.4
        cell.scale = 0.05
        cell.scaleRange = 0.03
        cell.alphaSpeed = -0.16
        cell.color = CGColor(red: 1, green: 0.40, blue: 0.08, alpha: 0.35)
    }

    private func configureBurstEmber(_ cell: CAEmitterCell) {
        configure(cell, birthRate: 0)
        cell.lifetime = 1.6
        cell.velocity = 70
        cell.velocityRange = 40
        cell.yAcceleration = -40
        cell.emissionRange = .pi
        cell.scale = 0.12
        cell.alphaSpeed = -0.5
    }

    private func configureSmoke(_ cell: CAEmitterCell) {
        cell.contents = FireParticles.glowImage(
            color: NSColor(white: 0.72, alpha: 0.55), size: 48)
        cell.birthRate = 0
        cell.lifetime = 2.1
        cell.lifetimeRange = 0.5
        cell.velocity = 28
        cell.velocityRange = 16
        cell.yAcceleration = -36
        cell.emissionLongitude = .pi / 2
        cell.emissionRange = 0.7
        cell.scale = 0.28
        cell.scaleRange = 0.18
        cell.scaleSpeed = 0.42
        cell.alphaSpeed = -0.48
        cell.color = CGColor(red: 0.55, green: 0.52, blue: 0.50, alpha: 0.35)
    }
}

enum FireParticles {
    static func glowImage(color: NSColor, size: CGFloat = 32) -> CGImage? {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let gradient = NSGradient(colors: [color, color.withAlphaComponent(0)]) else {
                return false
            }
            gradient.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
            return true
        }
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
