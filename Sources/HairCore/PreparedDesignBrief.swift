import Foundation

/// Shared native/worker handoff. Preparation is not generated-design acceptance.
public struct PreparedDesignBrief: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var sourceSHA256: String
    public var request: DesignBriefRequest
    public var compiled: CompiledDesignBrief

    public static func prepare(source: HairDesignInput, request: DesignBriefRequest) throws -> Self {
        try HaircutValidator.validateInput(source)
        var compiled=try DesignBriefCompiler.compile(scalp:source.scalp,profile:source.hairProfile,request:request)
        compiled.input.brief.envelopeGuard=source.brief.envelopeGuard
        try HaircutValidator.validateInput(compiled.input)
        return Self(sourceSHA256:try HairArtifactHash.digest(source),request:request,compiled:compiled)
    }

    public func validatedInput(source: HairDesignInput) throws -> HairDesignInput {
        guard schemaVersion==1,sourceSHA256 == (try HairArtifactHash.digest(source)) else {
            throw CaptureError.invalid("Prepared brief belongs to a different source or unsupported version.")
        }
        let replay=try Self.prepare(source:source,request:request)
        guard try HairArtifactHash.digest(replay.compiled)==HairArtifactHash.digest(compiled) else {
            throw CaptureError.invalid("Prepared brief does not reproduce its requested constraints.")
        }
        return replay.compiled.input
    }

    private enum CodingKeys:String,CodingKey { case schemaVersion,sourceSHA256,request,compiled }
    public init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        // Earlier native-only documents omitted the version; replay remains mandatory.
        schemaVersion=try c.decodeIfPresent(Int.self,forKey:.schemaVersion) ?? 1
        sourceSHA256=try c.decode(String.self,forKey:.sourceSHA256)
        request=try c.decode(DesignBriefRequest.self,forKey:.request)
        compiled=try c.decode(CompiledDesignBrief.self,forKey:.compiled)
    }
    private init(sourceSHA256:String,request:DesignBriefRequest,compiled:CompiledDesignBrief) {
        self.sourceSHA256=sourceSHA256;self.request=request;self.compiled=compiled
    }
}
