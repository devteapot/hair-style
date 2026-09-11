import Foundation

/// Call once at process startup, before any export worker can begin.
/// Only recognizes the app's UUID-named export files directly inside its tmp directory.
public enum TemporaryExportCleanup {
    @discardableResult
    public static func removeAbandonedExports(in directory: URL) throws -> Int {
        let manager = FileManager.default
        var removed = 0
        for file in try manager.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
            let name = file.lastPathComponent
            let identifier: String
            if name.hasPrefix("capture-"), name.hasSuffix(".zip") {
                identifier = String(name.dropFirst(8).dropLast(4))
            } else if name.hasPrefix("live-timing-"), name.hasSuffix(".json") {
                identifier = String(name.dropFirst(12).dropLast(5))
            } else { continue }
            guard UUID(uuidString: identifier) != nil else { continue }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            try manager.removeItem(at: file)
            removed += 1
        }
        return removed
    }
}
