import Foundation

/// Portable ZIP32 (stored entries). Streams one evidence payload at a time.
public enum CaptureArchive {
    private static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1 }
        return crc
    }
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data { crc = crcTable[Int((crc ^ UInt32(byte)) & 255)] ^ (crc >> 8) }
        return crc ^ 0xffffffff
    }

    public static func export(bundle: URL, to destination: URL) throws {
        try Task.checkCancellation()
        let report = try CaptureBundle.inspect(bundle)
        guard report.valid else { throw CaptureError.invalid("Cannot export invalid evidence: \(report.errors.joined(separator: "; "))") }
        let manifest = try CaptureBundle.load(bundle)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw CaptureError.invalid("Export destination already exists.") }
        #if os(iOS)
        let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
        #else
        let attributes: [FileAttributeKey: Any] = [:]
        #endif
        guard FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: attributes) else { throw CaptureError.invalid("Cannot create archive.") }
        let handle = try FileHandle(forWritingTo: destination)
        var succeeded = false
        defer { try? handle.close(); if !succeeded { try? FileManager.default.removeItem(at: destination) } }
        var central = Data()
        var count = 0
        func entry(name: String, data: Data) throws {
            let offset = try handle.offset()
            let encodedName = Data(name.utf8)
            guard offset + UInt64(data.count) + 30 + UInt64(encodedName.count) < UInt64(UInt32.max),
                  encodedName.count < Int(UInt16.max), count < Int(UInt16.max) else {
                throw CaptureError.invalid("Capture exceeds ZIP32 export limits. Export shorter passes.")
            }
            let crc = crc32(data), size = UInt32(data.count)
            var header = Data()
            header.le(UInt32(0x04034b50)); header.le(UInt16(20)); header.le(UInt16(0x0800))
            header.le(UInt16(0)); header.le(UInt16(0)); header.le(UInt16(0x0021))
            header.le(crc); header.le(size); header.le(size); header.le(UInt16(encodedName.count)); header.le(UInt16(0))
            header.append(encodedName)
            try handle.write(contentsOf: header); try handle.write(contentsOf: data)
            central.le(UInt32(0x02014b50)); central.le(UInt16(20)); central.le(UInt16(20)); central.le(UInt16(0x0800))
            central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt16(0x0021))
            central.le(crc); central.le(size); central.le(size); central.le(UInt16(encodedName.count))
            central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt32(0))
            central.le(UInt32(offset)); central.append(encodedName)
            count += 1
        }
        try entry(name: "manifest.json", data: ManifestCoding.encoder().encode(manifest))
        for frame in manifest.frames {
            try Task.checkCancellation()
            try entry(name: "frames/\(frame.metadata.id)/frame.json", data: ManifestCoding.encoder().encode(frame))
            for evidence in [frame.image, frame.depth, frame.confidence].compactMap({ $0 }) {
                try Task.checkCancellation()
                try entry(name: evidence.path, data: CaptureBundle.payload(evidence, in: bundle))
            }
        }
        try Task.checkCancellation()
        let centralOffset = try handle.offset()
        guard centralOffset + UInt64(central.count) + 22 < UInt64(UInt32.max) else { throw CaptureError.invalid("Archive exceeds ZIP32 size limit.") }
        try handle.write(contentsOf: central)
        var end = Data()
        end.le(UInt32(0x06054b50)); end.le(UInt16(0)); end.le(UInt16(0)); end.le(UInt16(count)); end.le(UInt16(count))
        end.le(UInt32(central.count)); end.le(UInt32(centralOffset)); end.le(UInt16(0))
        try handle.write(contentsOf: end)
        try handle.synchronize()
        succeeded = true
    }
}

private extension Data {
    mutating func le<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
