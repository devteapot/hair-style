import Foundation
import HairCore

enum PersonalConditioningProbe {
    static func run(endpoint:URL,directory:URL,output:URL) async throws {
        func read(_ name:String) throws -> Data { try Data(contentsOf:directory.appendingPathComponent(name)) }
        struct Context:Decodable { var preparationSHA256:String;var modelSampleSHA256:String }
        let context=try ManifestCoding.decoder().decode(Context.self,from:read("conditioning-context.json"))
        let preparationInputs=try PersonalPreparationInputs(input:read("source-input.json"),preparedBrief:read("prepared-brief.json"),
            mapping:read("mapping.json"),anatomy:read("anatomy.json"))
        var inputs=try PersonalConditioningInputs(preparationInputs:preparationInputs,preparationData:read("preparation-result.json"),
            preparationSHA256:context.preparationSHA256,modelSampleSHA256:context.modelSampleSHA256)
        var expected=try inputs.request()
        let client=try ProcessingClient(baseURL:endpoint)
        let credential=try await client.createGuest(), sessionKey=UUID().uuidString
        let session=try await client.createSession(requestKey:sessionKey)
        for (data,hash) in [(preparationInputs.input,expected.inputSHA256),(preparationInputs.preparedBrief,expected.preparedBriefSHA256),
                            (preparationInputs.mapping,expected.mappingSHA256),(preparationInputs.anatomy,expected.anatomySHA256),
                            (inputs.preparationData,expected.preparationSHA256)] {
            guard try await client.upload(data,sessionID:session)==hash else { throw CaptureError.invalid("Conditioning upload changed.") }
        }
        let preparationKey=UUID().uuidString
        let preparationJob=try await client.submitPersonalPreparation(sessionID:session,preparation:preparationInputs.request(),requestKey:preparationKey)
        var preparationComplete=false
        for _ in 0..<600 {
            let status=try await client.job(preparationJob)
            if status.state=="succeeded" { preparationComplete=true;break }
            if ["failed","cancelled"].contains(status.state) { throw CaptureError.invalid("Preceding preparation failed.") }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        guard preparationComplete else { throw CaptureError.invalid("Preceding preparation timed out.") }
        inputs=try await client.personalConditioningInputs(preparationJobID:preparationJob,inputs:preparationInputs,modelSampleSHA256:context.modelSampleSHA256)
        expected=try inputs.request()
        guard try await client.upload(inputs.preparationData,sessionID:session)==expected.preparationSHA256 else {
            throw CaptureError.invalid("Published preparation bytes changed before conditioning.")
        }
        let key=UUID().uuidString
        let job=try await client.submitPersonalConditioning(sessionID:session,conditioning:expected,requestKey:key)
        await client.close()
        let restored=try ProcessingClient(baseURL:endpoint,credential:credential)
        guard try await restored.createSession(requestKey:sessionKey)==session,
              try await restored.submitPersonalPreparation(sessionID:session,preparation:preparationInputs.request(),requestKey:preparationKey)==preparationJob,
              try await restored.submitPersonalConditioning(sessionID:session,conditioning:expected,requestKey:key)==job else {
            throw CaptureError.invalid("Conditioning retry changed session/job identity.")
        }
        var complete=false
        for _ in 0..<1800 {
            let status=try await restored.job(job)
            if status.state=="succeeded" { complete=true;break }
            if ["failed","cancelled"].contains(status.state) { throw CaptureError.invalid("Conditioning job failed.") }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        guard complete else { throw CaptureError.invalid("Conditioning job timed out.") }
        let result=try await restored.personalConditioningResult(jobID:job,inputs:inputs)
        try await restored.deleteSession(session)
        var deleted=false
        do { _=try await restored.job(job) }
        catch let error as ProcessingHTTPError { deleted=error.statusCode==404 }
        await restored.close()
        guard deleted else { throw CaptureError.invalid("Deleted conditioning job remained readable.") }
        let report:[String:Any]=["jobReused":true,"preparationJobReused":true,"publishedPreparationBytesPreserved":true,
            "sessionReused":true,"sessionDeleted":true,"swiftReplayVerified":true,
            "guideCount":result.haircut.guides.count,"meshVertexCount":result.mesh.vertices.count,
            "haircutSHA256":result.validation.haircutSHA256,"segmentViolations":result.clearance.violations.count,
            "missingRegions":result.clearance.missingRegions.map(\.rawValue),"acceptedForPersonalHaircut":false]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output,options:.atomic)
        print("Swift personal conditioning round trip passed; research review remains required.")
    }
}
