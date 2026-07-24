#if os(macOS)
import Foundation
import Metal
import MetalKit
import LiquidGlassCore

final class MetalContext {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLRenderPipelineState
    let samplerState: MTLSamplerState

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw LiquidGlassError.agent("This Mac does not expose a Metal device.")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw LiquidGlassError.agent("Unable to create a Metal command queue.")
        }

        guard let shaderURL = Bundle.module.url(
            forResource: "LiquidGlass",
            withExtension: "metal"
        ) else {
            throw LiquidGlassError.agent("The bundled LiquidGlass.metal shader is missing.")
        }
        let source = try String(contentsOf: shaderURL, encoding: .utf8)
        let options = MTLCompileOptions()
        options.fastMathEnabled = true
        let library = try device.makeLibrary(source: source, options: options)

        guard let vertex = library.makeFunction(name: "liquidGlassVertex"),
              let fragment = library.makeFunction(name: "liquidGlassFragment") else {
            throw LiquidGlassError.agent("The Metal library does not contain the expected shader functions.")
        }

        let pipeline = MTLRenderPipelineDescriptor()
        pipeline.label = "LiquidGlass compositor pipeline"
        pipeline.vertexFunction = vertex
        pipeline.fragmentFunction = fragment
        pipeline.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline.colorAttachments[0].isBlendingEnabled = true
        pipeline.colorAttachments[0].rgbBlendOperation = .add
        pipeline.colorAttachments[0].alphaBlendOperation = .add
        pipeline.colorAttachments[0].sourceRGBBlendFactor = .one
        pipeline.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipeline.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipeline.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        let sampler = MTLSamplerDescriptor()
        sampler.minFilter = .linear
        sampler.magFilter = .linear
        sampler.mipFilter = .notMipmapped
        sampler.sAddressMode = .clampToEdge
        sampler.tAddressMode = .clampToEdge
        sampler.normalizedCoordinates = true

        guard let samplerState = device.makeSamplerState(descriptor: sampler) else {
            throw LiquidGlassError.agent("Unable to create the Metal sampler state.")
        }

        self.device = device
        self.commandQueue = commandQueue
        self.pipelineState = try device.makeRenderPipelineState(descriptor: pipeline)
        self.samplerState = samplerState
    }
}
#endif
