import Metal
import QuartzCore

/// How the game is drawn.
enum PictureMode: String, CaseIterable {
    /// Fills the window with crisp pixels: each game pixel is scaled to the
    /// nearest whole size and only the seams between pixels are blended.
    case sharp
    /// Whole-number scaling only, with a border: every game pixel is an exact
    /// square of screen pixels.
    case pixel

    var title: String { self == .sharp ? "Sharp (Fill Window)" : "Pixel-Perfect" }
}

/// Draws game frames into a CAMetalLayer.
final class GameRenderer {
    let layer = CAMetalLayer()
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let input: MTLTexture
    private var hasFrame = false

    var mode: PictureMode = .sharp

    /// Sharp scaling: inside each game pixel the colour is flat; across the
    /// last screen pixel at its edge it blends into the neighbour, so pixels
    /// stay crisp and even at any size. At whole-number scales this is exact.
    private static let shaders = """
    #include <metal_stdlib>
    using namespace metal;
    struct V { float4 pos [[position]]; float2 uv; };
    vertex V vertexMain(uint id [[vertex_id]]) {
        float2 p = float2((id << 1) & 2, id & 2);
        V o; o.pos = float4(p * 2 - 1, 0, 1); o.uv = float2(p.x, 1 - p.y); return o;
    }
    fragment float4 fragmentMain(V in [[stage_in]], texture2d<float> t [[texture(0)]],
                                 sampler s [[sampler(0)]], constant float2 &outSize [[buffer(0)]]) {
        float2 size = float2(t.get_width(), t.get_height());
        float2 scale = max(outSize / size, 1.0);
        float2 texel = in.uv * size;
        float2 cell = floor(texel);
        float2 offset = texel - cell - 0.5;
        float2 inner = 0.5 - 0.5 / scale;
        float2 f = (offset - clamp(offset, -inner, inner)) * scale + 0.5;
        return float4(t.sample(s, (cell + f) / size).rgb, 1);
    }
    """

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.shaders, options: nil) else { return nil }
        let p = MTLRenderPipelineDescriptor()
        p.vertexFunction = library.makeFunction(name: "vertexMain")
        p.fragmentFunction = library.makeFunction(name: "fragmentMain")
        p.colorAttachments[0].pixelFormat = .bgra8Unorm
        let s = MTLSamplerDescriptor()
        s.minFilter = .linear; s.magFilter = .linear
        s.sAddressMode = .clampToEdge; s.tAddressMode = .clampToEdge
        let t = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 640, height: 480, mipmapped: false)
        t.usage = [.shaderRead]
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: p),
              let sampler = device.makeSamplerState(descriptor: s),
              let input = device.makeTexture(descriptor: t) else { return nil }
        self.queue = queue; self.pipeline = pipeline; self.sampler = sampler; self.input = input
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer.framebufferOnly = true
        layer.isOpaque = true
    }

    /// Copies a new frame (BGRX, 640 x 480) into the input texture.
    func upload(_ bytes: UnsafeRawPointer) {
        input.replace(region: MTLRegionMake2D(0, 0, 640, 480), mipmapLevel: 0, withBytes: bytes, bytesPerRow: 640 * 4)
        hasFrame = true
    }

    /// Draws the current frame at the layer's drawable size.
    func draw() {
        let size = layer.drawableSize
        guard hasFrame, size.width >= 1, size.height >= 1,
              let drawable = layer.nextDrawable(), let commands = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        var outSize = SIMD2<Float>(Float(size.width), Float(size.height))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(input, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(&outSize, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }
}
