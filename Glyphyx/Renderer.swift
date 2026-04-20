import Metal
import MetalKit
import simd
import CoreGraphics
import CoreText

// NOTE: Colors use float4 in uniforms to avoid Metal/Swift alignment issues.
// The .w component carries alpha (foreground) or is unused (glow).

struct FrameUniforms {
    var headColor:           SIMD4<Float>
    var trailColor:          SIMD4<Float>
    var glowColor:           SIMD4<Float>
    var time:                Float
    var totalChars:          Int32
    var atlasGridSize:       SIMD2<Float>
    var fallSpeedMultiplier: Float
    var characterBlur:       Float
    var flowDirection:       Int32
    var bidirectionalLayout: Int32
}

struct PaneUniforms {
    var mvp:        float4x4
    var gridSize:   SIMD2<Float>
    var layerSeed:  Int32
    var brightness: Float
}

struct PaneConfig {
    var position:  SIMD3<Float>
    var yRotation: Float
    var width:     Float
    var height:    Float
    var gridCols:  Int
    var gridRows:  Int
}

class Renderer: NSObject, MTKViewDelegate {

    private var device:       MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipeline:     MTLRenderPipelineState!
    private var depthState:   MTLDepthStencilState!
    private var atlasTexture: MTLTexture!
    private var quadBuffer:   MTLBuffer!
    private var startTime:    CFAbsoluteTime = 0

    private var glyphW    = 14
    private var glyphH    = 24
    private let atlasCols = 16
    private let atlasRows = 6

    private var characters: [Character] = []
    private var panes:      [PaneConfig] = []
    private var config:     GlyphyxConfig

    init(config: GlyphyxConfig) {
        self.config = config
    }

    // MARK: - Setup

    func setup(mtkView: MTKView) {
        device       = mtkView.device!
        commandQueue = device.makeCommandQueue()!
        startTime    = CFAbsoluteTimeGetCurrent()
        buildPipeline(mtkView: mtkView)
        buildQuadMesh()
        loadCharacters()
        computeGlyphDimensions()
        buildGlyphAtlas()
        generatePanes()
    }

    func reconfigure(config: GlyphyxConfig) {
        self.config = config
        loadCharacters()
        computeGlyphDimensions()
        buildGlyphAtlas()
        generatePanes()
    }

    // MARK: - Private Setup

    private func loadCharacters() {
        let raw = config.characterSet.isEmpty ? GlyphyxConfig.defaultCharacterSet : config.characterSet
        characters = Array(Array(raw).prefix(atlasCols * atlasRows))
    }

    private func computeGlyphDimensions() {
        let ctFont = CTFontCreateWithName(config.fontName as CFString, CGFloat(config.fontSize), nil)

        let ascent  = CTFontGetAscent(ctFont)
        let descent = CTFontGetDescent(ctFont)
        let leading = max(CTFontGetLeading(ctFont), 0)
        glyphH = max(Int(ceil(ascent + descent + leading)) + 2, 10)

        // Measure width using a wide reference character
        let attrStr = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0)!
        CFAttributedStringReplaceString(attrStr, CFRangeMake(0, 0), "M" as CFString)
        CFAttributedStringSetAttribute(attrStr, CFRangeMake(0, 1), kCTFontAttributeName, ctFont)
        let line   = CTLineCreateWithAttributedString(attrStr)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        glyphW = max(Int(ceil(bounds.width)) + 2, 6)
    }

    private func buildPipeline(mtkView: MTKView) {
        let bundle = Bundle(for: Renderer.self)
        guard let library = try? device.makeDefaultLibrary(bundle: bundle) else {
            fatalError("No Metal library in bundle: \(bundle.bundlePath)")
        }

        let vd = MTLVertexDescriptor()
        vd.attributes[0].format     = .float2
        vd.attributes[0].offset     = 0
        vd.attributes[0].bufferIndex = 0
        vd.attributes[1].format     = .float2
        vd.attributes[1].offset     = 8
        vd.attributes[1].bufferIndex = 0
        vd.layouts[0].stride        = 16

        let pd = MTLRenderPipelineDescriptor()
        pd.vertexFunction   = library.makeFunction(name: "vertex_main")
        pd.fragmentFunction = library.makeFunction(name: "fragment_main")
        pd.vertexDescriptor = vd
        pd.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        pd.depthAttachmentPixelFormat      = mtkView.depthStencilPixelFormat

        // Additive blending so glow layers accumulate naturally
        pd.colorAttachments[0].isBlendingEnabled             = true
        pd.colorAttachments[0].sourceRGBBlendFactor          = .sourceAlpha
        pd.colorAttachments[0].destinationRGBBlendFactor     = .one
        pd.colorAttachments[0].sourceAlphaBlendFactor        = .sourceAlpha
        pd.colorAttachments[0].destinationAlphaBlendFactor   = .one

        pipeline = try! device.makeRenderPipelineState(descriptor: pd)

        let dd = MTLDepthStencilDescriptor()
        dd.depthCompareFunction = .less
        dd.isDepthWriteEnabled  = true
        depthState = device.makeDepthStencilState(descriptor: dd)!
    }

    private func buildQuadMesh() {
        let verts: [Float] = [
            -0.5, -0.5,  0, 1,
             0.5, -0.5,  1, 1,
             0.5,  0.5,  1, 0,
            -0.5, -0.5,  0, 1,
             0.5,  0.5,  1, 0,
            -0.5,  0.5,  0, 0,
        ]
        quadBuffer = device.makeBuffer(bytes: verts,
                                       length: verts.count * MemoryLayout<Float>.stride,
                                       options: .storageModeShared)
    }

    private func generatePanes() {
        let density: Float = 3.5
        let rings: [(radius: Float, count: Int, height: Float, width: Float)] = [
            (4.0,  5, 18, 7),
            (7.5,  7, 22, 9),
            (11.0, 9, 26, 11),
        ]

        panes = []
        for ring in rings {
            for i in 0..<ring.count {
                let angle = Float(i) / Float(ring.count) * .pi * 2
                let x = cos(angle) * ring.radius
                let z = sin(angle) * ring.radius
                panes.append(PaneConfig(
                    position:  SIMD3(x, 0, z),
                    yRotation: angle + .pi,
                    width:     ring.width,
                    height:    ring.height,
                    gridCols:  Int(ring.width  * density),
                    gridRows:  Int(ring.height * density)
                ))
            }
        }
    }

    private func buildGlyphAtlas() {
        let atlasW = glyphW * atlasCols
        let atlasH = glyphH * atlasRows

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil,
            width: atlasW, height: atlasH,
            bitsPerComponent: 8,
            bytesPerRow: atlasW * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { fatalError("Cannot create CGContext for glyph atlas") }

        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: atlasW, height: atlasH))

        let ctFont = CTFontCreateWithName(config.fontName as CFString, CGFloat(config.fontSize), nil)

        for (i, char) in characters.enumerated() {
            let col = i % atlasCols
            let row = i / atlasCols

            let attrStr = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0)!
            CFAttributedStringReplaceString(attrStr, CFRangeMake(0, 0), String(char) as CFString)
            CFAttributedStringSetAttribute(attrStr, CFRangeMake(0, 1), kCTFontAttributeName, ctFont)
            CFAttributedStringSetAttribute(attrStr, CFRangeMake(0, 1), kCTForegroundColorAttributeName,
                                           CGColor(red: 1, green: 1, blue: 1, alpha: 1))

            let line   = CTLineCreateWithAttributedString(attrStr)
            let bounds = CTLineGetBoundsWithOptions(line, [])

            let cellX   = CGFloat(col * glyphW)
            let cellY   = CGFloat(atlasH - (row + 1) * glyphH)
            let xOffset = (CGFloat(glyphW) - bounds.width)  / 2 - bounds.origin.x
            let yOffset = (CGFloat(glyphH) - bounds.height) / 2 - bounds.origin.y

            ctx.textPosition = CGPoint(x: cellX + xOffset, y: cellY + yOffset)
            CTLineDraw(line, ctx)
        }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: atlasW, height: atlasH,
            mipmapped: false
        )
        desc.usage  = .shaderRead
        atlasTexture = device.makeTexture(descriptor: desc)!

        let region = MTLRegion(origin: .init(x: 0, y: 0, z: 0),
                               size: .init(width: atlasW, height: atlasH, depth: 1))
        atlasTexture.replace(region: region, mipmapLevel: 0,
                             withBytes: ctx.data!, bytesPerRow: atlasW * 4)
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let elapsed = Float(CFAbsoluteTimeGetCurrent() - startTime)

        var frameUniforms = FrameUniforms(
            headColor:           config.foregroundColorSIMD,
            trailColor:          config.trailColorSIMD,
            glowColor:           config.glowColorSIMD,
            time:                elapsed,
            totalChars:          Int32(characters.count),
            atlasGridSize:       SIMD2(Float(atlasCols), Float(atlasRows)),
            fallSpeedMultiplier: config.fallSpeedMultiplier,
            characterBlur:       config.characterBlur,
            flowDirection:       Int32(config.flowDirection.rawValue),
            bidirectionalLayout: Int32(config.bidirectionalLayout.rawValue)
        )

        guard
            let drawable = view.currentDrawable,
            let rpd      = view.currentRenderPassDescriptor,
            let cb       = commandQueue.makeCommandBuffer(),
            let enc      = cb.makeRenderCommandEncoder(descriptor: rpd)
        else { return }

        enc.setRenderPipelineState(pipeline)
        enc.setDepthStencilState(depthState)
        enc.setCullMode(.none)
        enc.setVertexBuffer(quadBuffer, offset: 0, index: 0)
        enc.setFragmentBytes(&frameUniforms, length: MemoryLayout<FrameUniforms>.stride, index: 0)
        enc.setFragmentTexture(atlasTexture, index: 0)

        if config.is3D {
            draw3D(enc: enc, view: view, elapsed: elapsed)
        } else {
            draw2D(enc: enc, view: view)
        }

        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }

    private func draw2D(enc: MTLRenderCommandEncoder, view: MTKView) {
        let w = Float(view.drawableSize.width)
        let h = Float(view.drawableSize.height)
        let gridCols = Int(w / Float(glyphW))
        let gridRows = Int(h / Float(glyphH))

        let mvp = makeScale(SIMD3<Float>(2, 2, 1))
        var paneU = PaneUniforms(
            mvp:        mvp,
            gridSize:   SIMD2(Float(gridCols), Float(gridRows)),
            layerSeed:  0,
            brightness: 1.0
        )
        enc.setVertexBytes(&paneU,  length: MemoryLayout<PaneUniforms>.stride, index: 1)
        enc.setFragmentBytes(&paneU, length: MemoryLayout<PaneUniforms>.stride, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }

    private func draw3D(enc: MTLRenderCommandEncoder, view: MTKView, elapsed: Float) {
        let speed      = config.cameraSpeedMultiplier
        let orbitAngle = elapsed * 0.12 * speed
        let camRadius: Float = 2.0 + sin(elapsed * 0.08) * 0.4
        let camX = sin(orbitAngle) * camRadius
        let camZ = cos(orbitAngle) * camRadius
        let camY = sin(elapsed * 0.1) * 1.0
        let eye  = SIMD3<Float>(camX, camY, camZ)

        let viewMatrix = makeLookAt(eye: eye, center: SIMD3(0, 0, 0), up: SIMD3(0, 1, 0))
        let aspect     = Float(view.drawableSize.width / view.drawableSize.height)
        let projMatrix = makePerspective(fovY: .pi / 2.5, aspect: aspect, near: 0.1, far: 50)
        let viewProj   = projMatrix * viewMatrix

        for (i, pane) in panes.enumerated() {
            let model = makeTranslation(pane.position)
                      * makeRotationY(angle: pane.yRotation)
                      * makeScale(SIMD3(pane.width, pane.height, 1))
            let mvp = viewProj * model

            var paneU = PaneUniforms(
                mvp:        mvp,
                gridSize:   SIMD2(Float(pane.gridCols), Float(pane.gridRows)),
                layerSeed:  Int32(i),
                brightness: 1.0
            )
            enc.setVertexBytes(&paneU,  length: MemoryLayout<PaneUniforms>.stride, index: 1)
            enc.setFragmentBytes(&paneU, length: MemoryLayout<PaneUniforms>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }
}

// MARK: - Transform Helpers

private func makePerspective(fovY: Float, aspect: Float, near: Float, far: Float) -> float4x4 {
    let y = 1 / tan(fovY * 0.5)
    let x = y / aspect
    let z = far / (near - far)
    return float4x4(columns: (
        SIMD4(x, 0,  0,  0),
        SIMD4(0, y,  0,  0),
        SIMD4(0, 0,  z, -1),
        SIMD4(0, 0,  z * near, 0)
    ))
}

private func makeTranslation(_ t: SIMD3<Float>) -> float4x4 {
    float4x4(columns: (
        SIMD4(1, 0, 0, 0),
        SIMD4(0, 1, 0, 0),
        SIMD4(0, 0, 1, 0),
        SIMD4(t.x, t.y, t.z, 1)
    ))
}

private func makeRotationY(angle: Float) -> float4x4 {
    let c = cos(angle), s = sin(angle)
    return float4x4(columns: (
        SIMD4( c, 0, -s, 0),
        SIMD4( 0, 1,  0, 0),
        SIMD4( s, 0,  c, 0),
        SIMD4( 0, 0,  0, 1)
    ))
}

private func makeScale(_ s: SIMD3<Float>) -> float4x4 {
    float4x4(columns: (
        SIMD4(s.x,   0,   0, 0),
        SIMD4(  0, s.y,   0, 0),
        SIMD4(  0,   0, s.z, 0),
        SIMD4(  0,   0,   0, 1)
    ))
}

private func makeLookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> float4x4 {
    let f = normalize(center - eye)
    let s = normalize(cross(f, up))
    let u = cross(s, f)
    return float4x4(columns: (
        SIMD4(s.x,  u.x, -f.x, 0),
        SIMD4(s.y,  u.y, -f.y, 0),
        SIMD4(s.z,  u.z, -f.z, 0),
        SIMD4(-dot(s, eye), -dot(u, eye), dot(f, eye), 1)
    ))
}
