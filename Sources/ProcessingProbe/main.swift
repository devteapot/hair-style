import Foundation
import HairCore

@main
struct ProcessingProbe {
    static func main() async throws {
        let args = CommandLine.arguments
        let preparation = args.count == 5 && args[3] == "--preparation"
        let conditioning = args.count == 5 && args[3] == "--conditioning"
        guard (args.count == 3 || (args.count == 4 && args[3] == "--research") || preparation || conditioning), let endpoint = URL(string: args[1]), endpoint.host == "127.0.0.1" else {
            fatalError("Usage: processing-probe http://127.0.0.1:PORT OUTPUT.json [--research | --preparation INPUT_DIRECTORY | --conditioning INPUT_DIRECTORY] (loopback only)")
        }
        if conditioning {
            try await PersonalConditioningProbe.run(endpoint:endpoint,directory:URL(fileURLWithPath:args[4]),output:URL(fileURLWithPath:args[2]))
            return
        }
        if preparation {
            try await PersonalPreparationProbe.run(endpoint:endpoint,directory:URL(fileURLWithPath:args[4]),output:URL(fileURLWithPath:args[2]))
            return
        }
        let client = try ProcessingClient(baseURL: endpoint)
        let guest = try await client.createGuest()
        let sessionKey = UUID().uuidString
        let sessionID = try await client.createSession(requestKey: sessionKey)
        if args.count == 4 {
            let description = "short wavy hair with a side part", seed = 43, key = UUID().uuidString
            let job = try await client.submitResearchGeneration(sessionID: sessionID, description: description, seed: seed, requestKey: key)
            await client.close()
            let restored = try ProcessingClient(baseURL: endpoint, credential: guest)
            guard try await restored.submitResearchGeneration(sessionID: sessionID, description: description, seed: seed, requestKey: key) == job else {
                fatalError("Research retry created a duplicate")
            }
            var succeeded = false
            for _ in 0..<1200 {
                let status = try await restored.job(job)
                if status.state == "succeeded" { succeeded = true; break }
                if status.state == "failed" { fatalError("Research generation failed") }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard succeeded else { fatalError("Research generation timed out") }
            let result = try await restored.generatedGuides(jobID: job, description: description, seed: seed)
            guard result.strandCount == 763 else { fatalError("Unexpected guide count") }
            try await restored.deleteSession(sessionID); await restored.close()
            let report: [String: Any] = ["researchOnly": true, "personalStyleVerified": false,
                "strandCount": result.strandCount, "outputSHA256": result.outputSHA256, "jobReused": true,
                "swiftDownloadValidated": true, "sessionDeleted": true]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: args[2]), options: .atomic)
            print("Swift research generation round trip passed.")
            return
        }
        let fixture = try SyntheticHaircut.create()
        let input = try ManifestCoding.encoder().encode(fixture.input)
        let haircut = try ManifestCoding.encoder().encode(fixture.haircut)
        let inputHash = try await client.upload(input, sessionID: sessionID)
        let haircutHash = try await client.upload(haircut, sessionID: sessionID)
        let key = UUID().uuidString
        let job = try await client.submitCompilation(sessionID: sessionID, inputHash: inputHash, haircutHash: haircutHash, requestKey: key)
        await client.close()
        let restored = try ProcessingClient(baseURL: endpoint, credential: guest)
        let repeatedSession = try await restored.createSession(requestKey: sessionKey)
        guard repeatedSession == sessionID else { fatalError("Session retry created a duplicate") }
        let repeatedHash = try await restored.upload(input, sessionID: sessionID)
        let repeatedJob = try await restored.submitCompilation(sessionID: sessionID, inputHash: repeatedHash, haircutHash: haircutHash, requestKey: key)
        guard repeatedHash == inputHash, repeatedJob == job else {
            fatalError("Restored client did not preserve upload/job identity")
        }
        var succeeded = false
        for _ in 0..<100 {
            let status = try await restored.job(job)
            if status.state == "succeeded" { succeeded = true; break }
            if status.state == "failed" { fatalError("Compiler job failed") }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard succeeded else { fatalError("Compiler did not finish within probe window") }
        let compiled = try await restored.compiledResult(jobID: job, inputData: input, haircutData: haircut)
        guard compiled.mesh.guideCount == 2 else { fatalError("Wrong compiled guide count") }
        try await restored.deleteSession(sessionID)
        try await restored.deleteSession(sessionID)
        var resurrectionRejected = false
        do { _ = try await restored.createSession(requestKey: sessionKey) }
        catch let error as ProcessingHTTPError { resurrectionRejected = error.statusCode == 404 }
        guard resurrectionRejected else { fatalError("Session retry resurrected deleted data") }
        var rejected = false
        do { _ = try await restored.job(job) } catch let error as ProcessingHTTPError { rejected = error.statusCode == 404 }
        guard rejected else { fatalError("Deleted job remained readable") }
        await restored.close()
        let report: [String: Any] = ["syntheticOnly": true, "guestRestored": true,
            "sessionReused": true, "deletionRetrySucceeded": true, "sessionResurrectionRejected": true,
            "uploadReused": true, "jobReused": true, "deletedJobRejected": true,
            "workerExecuted": true, "meshLocallyReplayed": true, "nativeUIIntegrated": false]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys])
            .write(to: URL(fileURLWithPath: args[2]), options: .atomic)
        print("Swift HTTP probe passed with synthetic artifacts only.")
    }
}
