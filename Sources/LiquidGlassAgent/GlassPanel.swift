#if os(macOS)
import AppKit
import CoreGraphics
import MetalKit
import LiquidGlassCore

@MainActor
final class GlassPanel {
    let key: DisplaySegmentKey

    private let panel: NSPanel
    private let metalView: MTKView
    private let renderer: GlassRenderer
    private var targetWindowID: CGWindowID

    init(
        key: DisplaySegmentKey,
        context: MetalContext,
        targetWindowID: CGWindowID,
        frame: CGRect
    ) {
        self.key = key
        self.targetWindowID = targetWindowID
        self.panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.metalView = MTKView(frame: CGRect(origin: .zero, size: frame.size), device: context.device)
        self.renderer = GlassRenderer(context: context)

        metalView.delegate = renderer
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.clearColor = MTLClearColorMake(0, 0, 0, 0)
        metalView.framebufferOnly = true
        metalView.enableSetNeedsDisplay = false
        metalView.isPaused = false
        metalView.autoResizeDrawable = true
        metalView.preferredFramesPerSecond = 60

        panel.contentView = metalView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.level = .normal
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .transient
        ]
        panel.sharingType = .none
        panel.setFrame(frame, display: false)
    }

    func update(
        targetWindowID: CGWindowID,
        frame: CGRect,
        configuration: LiquidGlassConfiguration,
        segment: GlassSegmentDescriptor,
        framePool: DisplayFramePool
    ) {
        self.targetWindowID = targetWindowID
        if panel.frame != frame {
            panel.setFrame(frame, display: true, animate: false)
        }
        renderer.update(
            configuration: configuration,
            segment: segment,
            framePool: framePool,
            view: metalView
        )
        panel.order(.below, relativeTo: Int(targetWindowID))
    }

    func close() {
        metalView.isPaused = true
        panel.orderOut(nil)
        panel.close()
    }
}
#endif
