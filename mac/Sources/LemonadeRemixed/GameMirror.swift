import AppKit
import ScreenCaptureKit

/// Mirrors the original game's 640x480 window and hands each frame to its layers.
final class GameMirror: NSObject, SCStreamOutput, SCStreamDelegate {
    static let gameSize = CGSize(width: 640, height: 480)
    private var stream: SCStream?
    private var layers: [CALayer] = []
    var onStatus: ((String) -> Void)?

    func attach(_ layer: CALayer) { layers.append(layer) }

    func start() {
        Task { @MainActor in
            do {
                try await connect()
            } catch {
                onStatus?("Waiting for the game… (\(error.localizedDescription))")
                try? await Task.sleep(for: .seconds(2))
                start()
            }
        }
    }

    @MainActor private func connect() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let window = content.windows.first(where: { $0.title == "Lemonade Tycoon Deluxe" && $0.frame.width >= 640 }) else {
            throw NSError(domain: "Lemonade", code: 1, userInfo: [NSLocalizedDescriptionKey: "game window not found"])
        }
        let config = SCStreamConfiguration()
        let titleBar = window.frame.height - Self.gameSize.height
        config.sourceRect = CGRect(x: 0, y: titleBar, width: Self.gameSize.width, height: Self.gameSize.height)
        config.width = Int(Self.gameSize.width)
        config.height = Int(Self.gameSize.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        try await stream.startCapture()
        self.stream = stream
        onStatus?("")
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pixels = buffer.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(pixels)?.takeUnretainedValue() else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in layers { layer.contents = surface }
        CATransaction.commit()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        self.stream = nil
        start()
    }
}

extension CALayer {
    /// A layer that shows game frames with sharp, unfiltered pixels.
    static func gamePixels() -> CALayer {
        let layer = CALayer()
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        layer.contentsGravity = .resize
        return layer
    }

    /// Show only part of the game screen, given in game coordinates (top-left
    /// origin). Layer content rectangles count from the bottom on macOS.
    func showGameRegion(_ r: CGRect) {
        let s = GameMirror.gameSize
        contentsRect = CGRect(x: r.minX / s.width, y: (s.height - r.maxY) / s.height,
                              width: r.width / s.width, height: r.height / s.height)
    }
}
