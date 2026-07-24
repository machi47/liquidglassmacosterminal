#if os(macOS)
import CoreGraphics
import Foundation
import Metal
import MetalKit
import QuartzCore
import LiquidGlassCore

private struct GlassUniforms {
    var viewportTimeRadius: SIMD4<Float>
    var sourceOriginSize: SIMD4<Float>
    var windowSizeSegmentOrigin: SIMD4<Float>
    var opticalPrimary: SIMD4<Float>
    var opticalSecondary: SIMD4<Float>
    var tint: SIMD4<Float>
    var flags: SIMD4<Float>
}

struct GlassSegmentDescriptor: Sendable {
    let windowID: CGWindowID
    let windowQuartzFrame: CGRect
    let displayQuartzBounds: CGRect
    let segmentQuartzFrame: CGRect
}

final class GlassRenderer: NSObject, MTKViewDelegate {
    private struct State {
        var configuration: LiquidGlassConfiguration
        var segment: GlassSegmentDescriptor
        var framePool: DisplayFramePool
    }

    private let context: MetalContext
    private let lock = NSLock()
    private var state: State?
    private let startTime = CACurrentMediaTime()

    init(context: MetalContext) {
        self.context = context
        super.init()
    }

    func update(
        configuration: LiquidGlassConfiguration,
        segment: GlassSegmentDescriptor,
        framePool: DisplayFramePool,
        view: MTKView
    ) {
        lock.lock()
        state = State(
            configuration: configuration,
            segment: segment,
            framePool: framePool
        )
        lock.unlock()
        view.preferredFramesPerSecond = configuration.renderFramesPerSecond
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        lock.lock()
        let current = state
        lock.unlock()
        guard let current,
              let lease = current.framePool.leaseCurrent(),
              let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = context.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        let configuration = current.configuration
        let segment = current.segment
        let display = segment.displayQuartzBounds
        let sourceOrigin = SIMD2<Float>(
            Float((segment.segmentQuartzFrame.minX - display.minX) / display.width),
            Float((segment.segmentQuartzFrame.minY - display.minY) / display.height)
        )
        let sourceSize = SIMD2<Float>(
            Float(segment.segmentQuartzFrame.width / display.width),
            Float(segment.segmentQuartzFrame.height / display.height)
        )

        let drawableWidth = max(Float(view.drawableSize.width), 1)
        let drawableHeight = max(Float(view.drawableSize.height), 1)
        let pointWidth = max(Float(segment.segmentQuartzFrame.width), 1)
        let pointHeight = max(Float(segment.segmentQuartzFrame.height), 1)
        let scaleX = drawableWidth / pointWidth
        let scaleY = drawableHeight / pointHeight
        let scalarScale = min(scaleX, scaleY)
        let fullWindowSize = SIMD2<Float>(
            Float(segment.windowQuartzFrame.width) * scaleX,
            Float(segment.windowQuartzFrame.height) * scaleY
        )
        let segmentOrigin = SIMD2<Float>(
            Float(segment.segmentQuartzFrame.minX - segment.windowQuartzFrame.minX) * scaleX,
            Float(segment.segmentQuartzFrame.minY - segment.windowQuartzFrame.minY) * scaleY
        )
        let elapsed = configuration.reduceMotion
            ? Float(0)
            : Float(CACurrentMediaTime() - startTime)

        var uniforms = GlassUniforms(
            viewportTimeRadius: SIMD4<Float>(
                drawableWidth,
                drawableHeight,
                elapsed,
                Float(configuration.cornerRadius) * scalarScale
            ),
            sourceOriginSize: SIMD4<Float>(
                sourceOrigin.x,
                sourceOrigin.y,
                sourceSize.x,
                sourceSize.y
            ),
            windowSizeSegmentOrigin: SIMD4<Float>(
                fullWindowSize.x,
                fullWindowSize.y,
                segmentOrigin.x,
                segmentOrigin.y
            ),
            opticalPrimary: SIMD4<Float>(
                Float(configuration.refractionStrength) * scalarScale,
                Float(configuration.dispersionStrength) * scalarScale,
                Float(configuration.flowScale),
                Float(configuration.flowSpeed)
            ),
            opticalSecondary: SIMD4<Float>(
                Float(configuration.edgeStrength),
                Float(configuration.causticStrength),
                Float(configuration.saturation),
                Float(configuration.grainStrength)
            ),
            tint: SIMD4<Float>(
                Float(configuration.tint.red),
                Float(configuration.tint.green),
                Float(configuration.tint.blue),
                Float(configuration.tint.alpha)
            ),
            flags: SIMD4<Float>(
                configuration.reduceMotion ? 1 : 0,
                Float(configuration.blurSigma),
                Float(lease.generation & 0xFFFF),
                0
            )
        )

        encoder.label = "LiquidGlass segment \(segment.windowID)"
        encoder.setRenderPipelineState(context.pipelineState)
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<GlassUniforms>.stride,
            index: 0
        )
        encoder.setFragmentTexture(lease.sharpTexture, index: 0)
        encoder.setFragmentTexture(lease.blurredTexture, index: 1)
        encoder.setFragmentSamplerState(context.samplerState, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { _ in lease.release() }
        commandBuffer.commit()
    }
}
#endif
