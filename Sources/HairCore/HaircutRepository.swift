import Foundation

public struct StoredHaircut: Codable, Sendable {
    public var input: HairDesignInput
    public var haircut: HaircutRevision
    public init(input: HairDesignInput, haircut: HaircutRevision) { self.input=input;self.haircut=haircut }
}

/// Immutable, content-addressed local revisions. Branches may share a revision
/// number; the hash is always part of their identity. No implicit current selection.
public final class HaircutRepository {
    public let root: URL
    public init(root: URL) { self.root = root }

    @discardableResult
    public func save(input: HairDesignInput, haircut: HaircutRevision) throws -> String {
        guard haircut.revision <= 128 else { throw CaptureError.invalid("Revision exceeds the local repository's 128-entry replay limit.") }
        let report = try HaircutValidator.validate(input: input, haircut: haircut)
        if let parent = haircut.parentSHA256 {
            let previous = try load(id: haircut.id, sha256: parent)
            guard try HairArtifactHash.digest(input) == HairArtifactHash.digest(previous.input) else {
                throw CaptureError.invalid("An edit cannot replace its source profile or brief.")
            }
            try HaircutEditor.verifyTransition(from: previous.haircut, to: haircut, input: input)
        }
        let url = try location(id: haircut.id, sha256: report.haircutSHA256)
        let record = StoredHaircut(input: input, haircut: haircut)
        let bytes = try ManifestCoding.encoder().encode(record)
        guard bytes.count <= 100_000_000 else { throw CaptureError.invalid("Haircut record exceeds the 100 MB local storage limit.") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.deletingLastPathComponent().path)
        var excluded = url.deletingLastPathComponent()
        var resource = URLResourceValues(); resource.isExcludedFromBackup = true
        try excluded.setResourceValues(resource)
        #endif
        // Move a complete temporary record into place without replacing an
        // existing revision. A concurrent identical writer is idempotent.
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try EvidenceIO.write(bytes, to: temporary)
        do { try FileManager.default.moveItem(at: temporary, to: url) }
        catch {
            guard FileManager.default.fileExists(atPath: url.path), try Data(contentsOf: url) == bytes else { throw error }
        }
        return report.haircutSHA256
    }

    public func load(id: String, sha256: String) throws -> StoredHaircut {
        var chain: [StoredHaircut] = [], next: String? = sha256
        while let hash = next {
            guard chain.count < 128 else { throw CaptureError.invalid("Revision history exceeds the 128-entry replay limit.") }
            let url = try location(id: id, sha256: hash)
            let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
            guard let size, (1...100_000_000).contains(size.intValue) else { throw CaptureError.invalid("Invalid haircut record size.") }
            let record = try ManifestCoding.decoder().decode(StoredHaircut.self, from: Data(contentsOf: url))
            guard record.haircut.id == id, try HairArtifactHash.digest(record.haircut) == hash else {
                throw CaptureError.invalid("Stored haircut failed identity or checksum verification.")
            }
            _ = try HaircutValidator.validate(input: record.input, haircut: record.haircut)
            if let newer = chain.last {
                guard record.haircut.revision == newer.haircut.revision - 1,
                      try HairArtifactHash.digest(record.input) == HairArtifactHash.digest(newer.input) else {
                    throw CaptureError.invalid("Revision history has a gap or changed input.")
                }
                try HaircutEditor.verifyTransition(from: record.haircut, to: newer.haircut, input: record.input)
            }
            chain.append(record); next = record.haircut.parentSHA256
        }
        return chain[0]
    }

    private func location(id: String, sha256: String) throws -> URL {
        guard UUID(uuidString: id) != nil, HairArtifactHash.valid(sha256) else { throw CaptureError.invalid("Invalid haircut address.") }
        let base = root.resolvingSymlinksInPath()
        let directory = base.appendingPathComponent(id)
        let file = directory.appendingPathComponent(sha256 + ".json")
        guard directory.resolvingSymlinksInPath().path == directory.path,
              file.resolvingSymlinksInPath().path == file.path else { throw CaptureError.invalid("Haircut address traverses a symlink.") }
        return file
    }
}
