import ScreenSaver
import MetalKit

@objc(GlyphyxScreenSaver)
class GlyphyxScreenSaver: ScreenSaverView {

    private var mtkView: MTKView!
    private var renderer: Renderer!
    private let config = GlyphyxConfig()
    private lazy var sheetController = ConfigureSheetController(config: config) { [weak self] in
        self?.applyConfig()
    }

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        wantsLayer = true
        animationTimeInterval = 1.0 / 60.0
        setupMetal()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        animationTimeInterval = 1.0 / 60.0
        setupMetal()
    }

    // Secondary-screen fallback: the framework sometimes skips the normal
    // init path for non-primary displays, so we retry here if needed.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, mtkView == nil else { return }
        setupMetal()
    }

    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        mtkView = MTKView(frame: bounds, device: device)
        mtkView.autoresizingMask = [.width, .height]
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = config.backgroundClearColor
        mtkView.preferredFramesPerSecond = 60
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = false

        renderer = Renderer(config: config)
        renderer.setup(mtkView: mtkView)
        mtkView.delegate = renderer

        addSubview(mtkView)
    }

    private func applyConfig() {
        mtkView?.clearColor = config.backgroundClearColor
        renderer?.reconfigure(config: config)
    }

    // MARK: - ScreenSaverView

    override func startAnimation() {
        super.startAnimation()
        // Fallback: set up Metal here if viewDidMoveToWindow wasn't called
        // by the framework for this screen instance (common on secondary screens).
        if mtkView == nil { setupMetal() }
    }

    override func stopAnimation() {
        super.stopAnimation()
    }

    override func animateOneFrame() {
        mtkView?.draw()
    }

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? { sheetController.window }
}
