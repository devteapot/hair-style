import Foundation
import HairCore

enum PersonalPreparationProbe {
    static func run(endpoint: URL, directory: URL, output: URL) async throws {
        func read(_ name: String) throws -> Data { try Data(contentsOf: directory.appendingPathComponent(name)) }
        let inputs = try PersonalPreparationInputs(input:read("input.json"),preparedBrief:read("brief.json"),
            mapping:read("mapping.json"),anatomy:read("anatomy.json"))
        let expected = try inputs.request()
        let client = try ProcessingClient(baseURL:endpoint)
        let credential = try await client.createGuest()
        let sessionKey = UUID().uuidString
        let session = try await client.createSession(requestKey:sessionKey)
        for (data,hash) in [(inputs.input,expected.inputSHA256),(inputs.preparedBrief,expected.preparedBriefSHA256),
                            (inputs.mapping,expected.mappingSHA256),(inputs.anatomy,expected.anatomySHA256)] {
            guard try await client.upload(data,sessionID:session) == hash else { throw CaptureError.invalid("Upload bytes changed.") }
        }
        let key=UUID().uuidString
        let job=try await client.submitPersonalPreparation(sessionID:session,preparation:expected,requestKey:key)
        await client.close()
        let restored=try ProcessingClient(baseURL:endpoint,credential:credential)
        guard try await restored.createSession(requestKey:sessionKey) == session,
              try await restored.submitPersonalPreparation(sessionID:session,preparation:expected,requestKey:key) == job else {
            throw CaptureError.invalid("Preparation retry did not preserve job/session identity.")
        }
        var ready=false
        for _ in 0..<1200 {
            let state=try await restored.job(job)
            if state.state == "succeeded" { ready=true;break }
            if ["failed","cancelled"].contains(state.state) { throw CaptureError.invalid("Preparation failed.") }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        guard ready else { throw CaptureError.invalid("Preparation timed out.") }
        let result=try await restored.personalPreparationResult(jobID:job,inputs:inputs)
        try await restored.deleteSession(session)
        var deletionVerified=false
        do { _ = try await restored.job(job) }
        catch let error as ProcessingHTTPError { deletionVerified=error.statusCode == 404 }
        await restored.close()
        guard deletionVerified else { throw CaptureError.invalid("Deleted preparation remained readable.") }
        let report:[String:Any]=["jobReused":true,"sessionReused":true,"sessionDeleted":true,"swiftReplayVerified":true,
            "attachmentsReady":result.attachmentsReady,"rootCount":result.rootPreflight.rootCount,
            "conflicts":result.rootPreflight.violations.count,"missingRegions":result.rootPreflight.missingRegions.map(\.rawValue),
            "generationInputFileSHA256":result.generationInputFileSHA256,"modelExecuted":false,"personalStyleVerified":false]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output,options:.atomic)
        print("Swift personal preparation round trip passed; no model executed.")
    }
}
