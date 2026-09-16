import AppKit
import Metal
import MetalKit

final class StaticFireView: NSView {
    var isLight = false {
        didSet { updateGradient() }
    }

    private let gradient = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = gradient
        updateGradient()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer = gradient
        updateGradient()
    }

    override func layout() {
        super.layout()
        gradient.frame = bounds
    }

    private func updateGradient() {
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        if isLight {
            gradient.colors = [
                NSColor(red: 0.82, green: 0.38, blue: 0.16, alpha: 1).cgColor,
                NSColor(red: 0.94, green: 0.90, blue: 0.85, alpha: 1).cgColor,
            ]
        } else {
            gradient.colors = [
                NSColor(red: 0.42, green: 0.05, blue: 0.02, alpha: 1).cgColor,
                NSColor(red: 0.026, green: 0.010, blue: 0.012, alpha: 1).cgColor,
            ]
        }
    }
}

final class FireRenderer: MTKView, MTKViewDelegate {
    private(set) var isReady = false

    var targetPointer = CGPoint.zero
    var pointerInside = false
    var targetIntensity: Float = 0.58
    var isLight = false
    var reduceMotion = false

    private var commandQueue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var startTime: CFTimeInterval = CACurrentMediaTime()
    private var burstOrigin = CGPoint.zero
    private var burstStart: CFTimeInterval = -100
    private var pointer = SIMD2<Float>.zero
    private var pointerVel = SIMD2<Float>.zero
    private var strength: Float = 0
    private var intensity: Float = 0.58
    private var occlusionObservers: [NSObjectProtocol] = []

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device ?? MTLCreateSystemDefaultDevice())
        configure()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        device = MTLCreateSystemDefaultDevice()
        configure()
    }

    deinit {
        for observer in occlusionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func triggerBurst(at point: CGPoint) {
        burstOrigin = point
        burstStart = CACurrentMediaTime()
    }

    func updatePausedState() {
        guard let window else {
            isPaused = true
            return
        }
        isPaused = reduceMotion || !isReady || isHidden
            || window.isMiniaturized
            || !window.occlusionState.contains(.visible)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installOcclusionObservers()
        updatePausedState()
        updateDrawableSize()
    }

    override func layout() {
        super.layout()
        updateDrawableSize()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard isReady, !reduceMotion,
            let pipeline,
            let queue = commandQueue,
            let descriptor = view.currentRenderPassDescriptor,
            let drawable = currentDrawable,
            let buffer = queue.makeCommandBuffer(),
            let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        let dt: Float = 1.0 / 60.0
        let target = SIMD2<Float>(Float(targetPointer.x), Float(targetPointer.y))
        let stiffness: Float = 42
        let damping: Float = 11
        let accel = (target - pointer) * stiffness - pointerVel * damping
        pointerVel += accel * dt
        pointer += pointerVel * dt

        let strengthTarget: Float = pointerInside ? 1 : 0
        strength += (strengthTarget - strength) * min(1, 6 * dt)
        intensity += (targetIntensity - intensity) * min(1, 3.2 * dt)

        var uniforms = FireUniforms()
        let size = drawableSize
        uniforms.resolution = SIMD2<Float>(Float(size.width), Float(size.height))
        let scaleX = bounds.width > 0 ? Float(size.width / bounds.width) : 1
        let scaleY = bounds.height > 0 ? Float(size.height / bounds.height) : 1
        uniforms.pointer = SIMD2<Float>(pointer.x * scaleX, pointer.y * scaleY)
        uniforms.burst = SIMD2<Float>(
            Float(burstOrigin.x) * scaleX, Float(burstOrigin.y) * scaleY)
        uniforms.time = Float(CACurrentMediaTime() - startTime)
        uniforms.pointerStrength = strength
        uniforms.intensity = intensity
        uniforms.isLight = isLight ? 1 : 0
        uniforms.burstAge = Float(CACurrentMediaTime() - burstStart)

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FireUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    private func configure() {
        framebufferOnly = true
        preferredFramesPerSecond = 60
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0.026, green: 0.010, blue: 0.012, alpha: 1)
        isPaused = false
        enableSetNeedsDisplay = false
        autoResizeDrawable = false
        delegate = self
        compilePipeline()
    }

    private func compilePipeline() {
        guard let device else { return }
        commandQueue = device.makeCommandQueue()
        do {
            let library = try device.makeLibrary(source: FireShader.source, options: nil)
            guard let vertex = library.makeFunction(name: "fire_vertex"),
                let fragment = library.makeFunction(name: "fire_fragment")
            else { return }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            isReady = true
        } catch {
            isReady = false
        }
    }

    private func updateDrawableSize() {
        let scale = (window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2) * 0.5
        let width = max(1, bounds.width * scale)
        let height = max(1, bounds.height * scale)
        drawableSize = CGSize(width: width, height: height)
    }

    private func installOcclusionObservers() {
        for observer in occlusionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        occlusionObservers.removeAll()
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
        ]
        for name in names {
            let observer = center.addObserver(forName: name, object: window, queue: .main) {
                [weak self] _ in
                self?.updatePausedState()
            }
            occlusionObservers.append(observer)
        }
    }
}
