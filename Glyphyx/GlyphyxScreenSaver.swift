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
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        animationTimeInterval = 1.0 / 60.0
    }

    // Defer Metal setup until the view is placed in its screen's window.
    // This ensures the MTKView's CAMetalLayer gets the correct display
    // connection on every monitor, including secondary screens.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, mtkView == nil else { return }
        setupMetal()
    }

    private func setupMetal() {
        // preferredDevice picks the GPU driving this specific screen,
        // which matters on multi-GPU Macs.
        let tempView = MTKView(frame: bounds)
        guard let device = tempView.preferredDevice ?? MTLCreateSystemDefaultDevice() else { return }

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
