import AppKit
import CoreImage
import SwiftUI
import WidgetKit
#if canImport(IPWidgetCore)
import IPWidgetCore
#endif

/// A color bitmap flag, with a pre-muted variant for accented rendering.
public struct FlagView: View {
    private let countryCode: String?
    private let fallback: String
    private let height: CGFloat

    @Environment(\.widgetRenderingMode) private var renderingMode

    public init(countryCode: String?, fallback: String, height: CGFloat) {
        self.countryCode = countryCode
        self.fallback = fallback
        self.height = height
    }

    public var body: some View {
        let width = height * 1.40
        if let image = FlagImageCache.image(
            for: countryCode,
            muted: renderingMode != .fullColor,
            size: CGSize(width: width, height: height)
        ) {
            Image(nsImage: image)
                .interpolation(.high)
                .widgetAccentedRenderingMode(.fullColor)
        } else {
            Text(fallback)
                .font(.system(size: height * 0.86))
                .frame(width: width, height: height)
        }
    }
}

private enum FlagImageCache {
    nonisolated(unsafe) private static let cache = NSCache<NSString, NSImage>() // NSCache is thread-safe
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])
    private static let mutedSaturation: Float = 0.33

    static func image(for countryCode: String?, muted: Bool, size: CGSize) -> NSImage? {
        let flag = Country.flagEmoji(forISOCode: countryCode)
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        let key = "\(flag)|\(muted ? "muted" : "color")|\(width)x\(height)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let colored = rasterize(flag: flag, target: size) else { return nil }
        let image = muted ? desaturate(colored) ?? colored : colored
        cache.setObject(image, forKey: key)
        return image
    }

    private static func rasterize(flag: String, target: CGSize) -> NSImage? {
        let scale: CGFloat = 3
        let pointSize = max(target.width, target.height) * scale * 1.05
        let font = NSFont.systemFont(ofSize: pointSize)
        let string = NSAttributedString(string: flag, attributes: [.font: font])
        let textSize = string.size()
        guard textSize.width > 1, textSize.height > 1 else { return nil }

        let canvas = CGSize(
            width: ceil(textSize.width * 1.04),
            height: ceil(textSize.height * 1.04)
        )
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvas.width),
            pixelsHigh: Int(canvas.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        bitmap.size = canvas

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSGraphicsContext.current?.shouldAntialias = true
        string.draw(at: NSPoint(
            x: (canvas.width - textSize.width) / 2,
            y: (canvas.height - textSize.height) / 2
        ))
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = bitmap.cgImage else { return nil }

        // Match the bitmap's logical size to the displayed flag.
        let aspect = canvas.width / canvas.height
        let displayHeight = target.height
        let displayWidth = min(target.width, displayHeight * aspect)
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: displayWidth, height: displayHeight)
        )
    }

    private static func desaturate(_ image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(mutedSaturation, forKey: kCIInputSaturationKey)
        filter.setValue(1.02, forKey: kCIInputContrastKey)
        filter.setValue(0.02, forKey: kCIInputBrightnessKey)
        guard let output = filter.outputImage,
              let muted = ciContext.createCGImage(output, from: output.extent)
        else {
            return nil
        }
        return NSImage(cgImage: muted, size: image.size)
    }
}
