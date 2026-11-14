import UIKit

// Pictures used by the scene. Most are files written by `npm run ios:data`;
// the moon is painted here because its shape changes through the month.

enum Textures {
    /// The sheet of tiny surface textures (soil, stone, wood, cloth, metal...).
    static let atlas = bundleImage("atlas")
    /// A soft round blob, for flames and halos.
    static let glow = bundleImage("glow")

    private static let faceSheet = bundleImage("face")
    /// The hero's eyes, open and closed.
    static let faceOpen = crop(faceSheet, x: 0, y: 0, width: 24, height: 12)
    static let faceClosed = crop(faceSheet, x: 0, y: 12, width: 24, height: 12)

    private static let runeSheet = bundleImage("runes")
    /// The seven weekday runes, Monday first.
    static let runes: [UIImage] = (0..<7).map { crop(runeSheet, x: $0 * 8, y: 0, width: 8, height: 8) }

    /// Paints the moon. `phase` runs from 0 (new) to 1 (full).
    static func moon(phase: Float, haze: RGB) -> UIImage {
        let size = 112
        let lit = RGB(0.914, 0.902, 0.788)
        let shadow = RGB(0.106, 0.169, 0.176)
        var pixels = [UInt8](repeating: 0, count: size * size * 4)

        func fract(_ v: Float) -> Float { v - v.rounded(.down) }
        func hash(_ x: Float, _ y: Float) -> Float { fract(sin(x * 127.1 + y * 311.7) * 43758.5453) }
        func smooth(_ a: Float, _ b: Float, _ v: Float) -> Float {
            let t = max(0, min(1, (v - a) / (b - a)))
            return t * t * (3 - 2 * t)
        }
        // Soft random blotches: the moon's dark "seas".
        func blotch(_ x: Float, _ y: Float) -> Float {
            let ix = x.rounded(.down), iy = y.rounded(.down)
            var fx = x - ix, fy = y - iy
            fx = fx * fx * (3 - 2 * fx)
            fy = fy * fy * (3 - 2 * fy)
            let top = hash(ix, iy) * (1 - fx) + hash(ix + 1, iy) * fx
            let bottom = hash(ix, iy + 1) * (1 - fx) + hash(ix + 1, iy + 1) * fx
            return top * (1 - fy) + bottom * fy
        }

        for row in 0..<size {
            for col in 0..<size {
                let x = (Float(col) + 0.5) / Float(size) * 2 - 1
                let y = 1 - (Float(row) + 0.5) / Float(size) * 2
                let r = (x * x + y * y).squareRoot()
                if r > 1 { continue }
                // The line between day and night on a ball is half an ellipse.
                let edge = (1 - 2 * phase) * max(0, 1 - y * y).squareRoot()
                let isLit: Float = x >= edge ? 1 : 0
                var seas = smooth(0.52, 0.7, blotch(x * 2.3 + 4, y * 2.3 + 4)) * 0.26
                seas += smooth(0.62, 0.72, blotch(x * 5.5 + 9, y * 5.5 + 9)) * 0.12
                var color = shadow + (lit * (1 - seas) - shadow) * isLit
                // Slight darkening toward the rim makes it read as a ball, not a disc.
                color *= 1 - 0.28 * smooth(0.55, 1, r) * isLit
                // Low in the sky the moon picks up haze.
                color += (haze - color) * (smooth(0.2, -1.0, y) * 0.3)
                let at = (row * size + col) * 4
                pixels[at] = UInt8(max(0, min(255, color.x * 255)))
                pixels[at + 1] = UInt8(max(0, min(255, color.y * 255)))
                pixels[at + 2] = UInt8(max(0, min(255, color.z * 255)))
                pixels[at + 3] = 255
            }
        }
        return image(fromRGBA: pixels, width: size, height: size)
    }

    /// Makes a picture from raw pixels (red, green, blue, see-through-ness; top row first).
    static func image(fromRGBA pixels: [UInt8], width: Int, height: Int, scale: CGFloat = 1) -> UIImage {
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let cg = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else { return UIImage() }
        return UIImage(cgImage: cg, scale: scale, orientation: .up)
    }
}
