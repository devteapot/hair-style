import Foundation
import ImageIO

/// Preserve captured lens hints for image reconstruction without inventing them from a device name.
public enum CaptureImageMetadata {
    public static func jpegProperties(exif: [String:Any] = [:]) -> [String:Any] {
        let values = (exif[kCGImagePropertyExifDictionary as String] as? [String:Any]) ?? exif
        var lens: [String:Any] = [:]
        for key in [kCGImagePropertyExifFocalLength,kCGImagePropertyExifFocalLenIn35mmFilm] {
            if let number = values[key as String] as? NSNumber,
               CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
               number.doubleValue > 0, number.doubleValue <= 1000 { lens[key as String] = number }
        }
        for key in [kCGImagePropertyExifLensMake,kCGImagePropertyExifLensModel] {
            if let text = values[key as String] as? String, !text.isEmpty, text.count <= 256 { lens[key as String] = text }
        }
        // Image buffers remain sensor-native; an orientation copied from a display must not rotate decoding.
        var result: [String:Any] = [kCGImageDestinationLossyCompressionQuality as String:0.9,
                                   kCGImagePropertyOrientation as String:1]
        if !lens.isEmpty { result[kCGImagePropertyExifDictionary as String] = lens }
        return result
    }
}
