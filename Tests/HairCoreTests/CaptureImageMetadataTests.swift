import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import HairCore

final class CaptureImageMetadataTests: XCTestCase {
    func testCapturedLensHintsSurviveJPEGRoundTripWithoutChangingOrientation() throws {
        let properties=CaptureImageMetadata.jpegProperties(exif:[kCGImagePropertyExifFocalLength as String:6.765,
            kCGImagePropertyExifFocalLenIn35mmFilm as String:24,kCGImagePropertyExifLensModel as String:"fixture lens",
            kCGImagePropertyOrientation as String:6,"BodySerialNumber":"not required"])
        let bytes=Data(repeating:150,count:8*6*4)
        let provider=CGDataProvider(data:bytes as CFData)!
        let image=CGImage(width:8,height:6,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:32,space:CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.noneSkipLast.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        let output=NSMutableData()
        let destination=CGImageDestinationCreateWithData(output,UTType.jpeg.identifier as CFString,1,nil)!
        CGImageDestinationAddImage(destination,image,properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let source=CGImageSourceCreateWithData(output as CFData,nil)!
        let read=CGImageSourceCopyPropertiesAtIndex(source,0,nil)! as NSDictionary
        let exif=read[kCGImagePropertyExifDictionary] as! NSDictionary
        XCTAssertEqual((exif[kCGImagePropertyExifFocalLength] as! NSNumber).doubleValue,6.765,accuracy:1e-6)
        XCTAssertEqual((exif[kCGImagePropertyExifFocalLenIn35mmFilm] as! NSNumber).intValue,24)
        XCTAssertEqual((read[kCGImagePropertyOrientation] as! NSNumber).intValue,1)
        XCTAssertNil(exif["BodySerialNumber"])
    }
    func testMissingInvalidAndNestedMetadata() {
        XCTAssertNil(CaptureImageMetadata.jpegProperties()[kCGImagePropertyExifDictionary as String])
        let invalid=CaptureImageMetadata.jpegProperties(exif:[kCGImagePropertyExifFocalLength as String:Double.nan,
            kCGImagePropertyExifFocalLenIn35mmFilm as String:true])
        XCTAssertNil(invalid[kCGImagePropertyExifDictionary as String])
        let nested=CaptureImageMetadata.jpegProperties(exif:[kCGImagePropertyExifDictionary as String:[kCGImagePropertyExifFocalLength as String:4.0]])
        XCTAssertNotNil(nested[kCGImagePropertyExifDictionary as String])
    }
}
