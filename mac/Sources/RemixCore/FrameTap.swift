import CoreGraphics
import Foundation

/// Reads the frames the in-game agent writes to remix-frames.bin
/// (runtime/agent/frametap.c): a 64-byte header, then two 640x480 BGRX
/// buffers; the header names the one finished last.
public final class FrameTap {
    public static let width = 640, height = 480
    private static let header = 64
    private static let frameBytes = width * height * 4

    private let url: URL
    private var base: UnsafeMutableRawPointer?
    private var mappedSize = 0
    private var inode: UInt64 = 0
    private var lastFrame: UInt32 = .max
    private var lastCheck = Date.distantPast

    public init(url: URL) { self.url = url }
    deinit { unmap() }

    /// The newest frame, or nil when nothing new has arrived.
    public func newFrame() -> CGImage? {
        var image: CGImage?
        _ = withNewFrame { bytes in
            let pixels = Data(bytes: bytes, count: Self.frameBytes)
            guard let provider = CGDataProvider(data: pixels as CFData) else { return }
            image = CGImage(width: Self.width, height: Self.height, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: Self.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
        return image
    }

    /// Calls body with the newest frame's BGRX pixels (640 x 480, rows of
    /// 2560 bytes) if a new frame has arrived; returns whether it did.
    public func withNewFrame(_ body: (UnsafeRawPointer) -> Void) -> Bool {
        remapIfNeeded()
        guard let base, base.load(as: UInt32.self) == 0x5446_524C else { return false }   // "LRFT"
        let latest = Int(base.load(fromByteOffset: 20, as: UInt32.self) & 1)
        let frame = base.load(fromByteOffset: 24, as: UInt32.self)
        guard frame != lastFrame else { return false }
        lastFrame = frame
        body(UnsafeRawPointer(base + Self.header + latest * Self.frameBytes))
        return true
    }

    /// The game recreates the file each time it starts; follow it.
    private func remapIfNeeded() {
        guard base == nil || Date().timeIntervalSince(lastCheck) > 1 else { return }
        lastCheck = Date()
        var st = stat()
        guard stat(url.path, &st) == 0, Int(st.st_size) >= Self.header + 2 * Self.frameBytes else { unmap(); return }
        guard base == nil || UInt64(st.st_ino) != inode else { return }
        unmap()
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return }
        defer { close(fd) }
        let size = Int(st.st_size)
        let p = mmap(nil, size, PROT_READ, MAP_SHARED, fd, 0)
        guard p != MAP_FAILED, let p else { return }
        base = p
        mappedSize = size
        inode = UInt64(st.st_ino)
        lastFrame = .max
    }

    private func unmap() {
        if let base { munmap(base, mappedSize) }
        base = nil
    }
}
