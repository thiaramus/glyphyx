import ScreenSaver
import MetalKit

class GlyphyxScreenSaver: ScreenSaverView {

    private var mtkView: MTKView!
    private var renderer: Renderer!
    private let config = GlyphyxConfig()
    private lazy var sheetController = ConfigureSheetController(config: config) { [weak self] in
        self?.applyConfig()
    }

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        mtkView = MTKView(frame: bounds, device: device)
        mtkView.autoresizingMask = [.width, .height]
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = config.backgroundClearColor
        mtkView.preferredFramesPerSecond = 60
        mtkView.isPaused = true

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
        mtkView?.isPaused = false
    }

    override func stopAnimation() {
        super.stopAnimation()
        mtkView?.isPaused = true
    }

    override func animateOneFrame() {
        // MTKView handles its own render loop via its delegate
    }

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? { sheetController.window }
}
