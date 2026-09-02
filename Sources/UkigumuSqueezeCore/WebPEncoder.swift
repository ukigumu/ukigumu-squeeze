import CoreGraphics
import Foundation
import libwebp

enum WebPEncoder {
    static func encode(_ image: CGImage, quality: Double, to url: URL) throws {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw UkigumuSqueezeError.validationFailed(url)
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var output: UnsafeMutablePointer<UInt8>?
        let byteCount = pixels.withUnsafeBytes { buffer in
            WebPEncodeRGBA(
                buffer.bindMemory(to: UInt8.self).baseAddress,
                Int32(width),
                Int32(height),
                Int32(bytesPerRow),
                Float(min(max(quality, 0), 1) * 100),
                &output
            )
        }
        guard byteCount > 0, let output else {
            throw UkigumuSqueezeError.validationFailed(url)
        }
        defer { WebPFree(output) }
        try Data(bytes: output, count: byteCount).write(to: url, options: .withoutOverwriting)
    }
}
