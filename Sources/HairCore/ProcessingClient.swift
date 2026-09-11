import Foundation

public struct ProcessingHTTPError: Error, LocalizedError, Sendable {
    public let statusCode: Int
    public var errorDescription: String? { "Processing request failed (HTTP \(statusCode)). Saved local data is unchanged." }
}

public struct GuestCredential: Codable, Sendable {
    public var owner: String
    public var token: String
    public init(owner: String, token: String) throws {
        self.owner = owner; self.token = token; try validate()
    }
    public func validate() throws {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        guard UUID(uuidString: owner) != nil, (32...128).contains(token.utf8.count),
              token.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw CaptureError.invalid("Invalid guest credential.")
        }
    }
}
public struct ProcessingJobStatus: Codable, Sendable {
    public var id: String
    public var state: String
    public var stage: String
    public var outputHash: String?
    enum CodingKeys: String, CodingKey { case id, state, stage; case outputHash = "output_hash" }
}
private struct UploadStatus: Decodable {
    var id: String
    var digest: String
    var size: Int
    var offset: Int
    var complete: Int
}
private final class NoProcessingRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Explicit network operations only; no capture files are discovered or uploaded automatically.
public actor ProcessingClient {
    private let base: URL
    private let session: URLSession
    private var credential: GuestCredential?
    public init(baseURL: URL, credential: GuestCredential? = nil) throws {
        base = try ProcessingEndpoint.origin(baseURL)
        try credential?.validate(); self.credential = credential
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration, delegate: NoProcessingRedirects(), delegateQueue: nil)
    }
    public func close() { session.invalidateAndCancel() }
    private func request(_ method: String, _ path: String, body: Data? = nil,
                         authenticated: Bool = true, headers: [String:String] = [:]) async throws -> Data {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated {
            guard let credential else { throw CaptureError.invalid("Create or restore a guest credential first.") }
            request.setValue("Bearer " + credential.token, forHTTPHeaderField: "Authorization")
        }
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CaptureError.invalid("Non-HTTP processing response.") }
        guard (200..<300).contains(http.statusCode) else { throw ProcessingHTTPError(statusCode: http.statusCode) }
        guard data.count <= 100_000_000 else { throw CaptureError.invalid("Processing response exceeds its byte budget.") }
        return data
    }
    private func id(_ value: String) throws -> String {
        guard UUID(uuidString: value) != nil else { throw CaptureError.invalid("Invalid processing identity.") }
        return value
    }
    public func createGuest() async throws -> GuestCredential {
        guard credential == nil else { throw CaptureError.invalid("A guest credential is already loaded.") }
        let data = try await request("POST", "v1/guests", authenticated: false)
        let guest = try JSONDecoder().decode(GuestCredential.self, from: data)
        try guest.validate()
        credential = guest; return guest
    }
    public func createSession(requestKey: String = UUID().uuidString) async throws -> String {
        _ = try id(requestKey)
        struct Response: Decodable { var id: String }
        return try id(JSONDecoder().decode(Response.self, from: await request("POST", "v1/sessions", headers: ["Idempotency-Key": requestKey])).id)
    }
    /// Repeating this call after interruption reuses the server's hash-bound upload and offset.
    public func upload(_ data: Data, sessionID: String) async throws -> String {
        guard !data.isEmpty, data.count <= 100_000_000 else { throw CaptureError.invalid("Artifact exceeds upload budget.") }
        let digest = EvidenceHash.sha256(data)
        let declaration = try JSONSerialization.data(withJSONObject: ["sha256": digest, "size": data.count])
        var upload = try JSONDecoder().decode(UploadStatus.self,
            from: await request("POST", "v1/sessions/\(id(sessionID))/uploads", body: declaration))
        _ = try id(upload.id)
        func validate(_ value: UploadStatus) throws {
            guard value.digest == digest, value.size == data.count, (0...data.count).contains(value.offset),
                  value.complete == 0 || value.complete == 1 else { throw CaptureError.invalid("Upload response does not match the local artifact.") }
        }
        try validate(upload)
        while upload.offset < data.count {
            try Task.checkCancellation()
            let previous = upload.offset; let end = min(data.count, previous + 1_048_576)
            let next = try JSONDecoder().decode(UploadStatus.self, from: await request("PUT", "v1/uploads/\(upload.id)",
                body: data.subdata(in: previous..<end), headers: ["Upload-Offset": String(previous)]))
            try validate(next)
            guard next.id == upload.id, next.offset == end else { throw CaptureError.invalid("Upload offset did not advance as expected.") }
            upload = next
        }
        let finished = try JSONDecoder().decode(UploadStatus.self, from: await request("POST", "v1/uploads/\(upload.id)/complete"))
        try validate(finished)
        guard finished.id == upload.id, finished.complete == 1, finished.offset == data.count else {
            throw CaptureError.invalid("Upload finalization is incomplete.")
        }
        return digest
    }
    public func submitCompilation(sessionID: String, inputHash: String, haircutHash: String, requestKey: String) async throws -> String {
        guard HairArtifactHash.valid(inputHash), HairArtifactHash.valid(haircutHash), UUID(uuidString: requestKey) != nil else {
            throw CaptureError.invalid("Invalid compilation request identity or artifact hashes.")
        }
        let body = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "kind": "compile_hair",
            "inputSHA256": inputHash, "haircutSHA256": haircutHash])
        struct Response: Decodable { var id: String }
        return try id(JSONDecoder().decode(Response.self, from: await request("POST", "v1/sessions/\(id(sessionID))/jobs",
            body: body, headers: ["Idempotency-Key": requestKey])).id)
    }
    public func job(_ identity: String) async throws -> ProcessingJobStatus {
        let result = try JSONDecoder().decode(ProcessingJobStatus.self, from: await request("GET", "v1/jobs/\(id(identity))"))
        guard result.id == identity else { throw CaptureError.invalid("Job response identity mismatch.") }
        return result
    }
    public func submitPersonalPreparation(sessionID: String, preparation: PersonalPreparationRequest, requestKey: String) async throws -> String {
        try preparation.validate(); _ = try id(requestKey)
        struct Response: Decodable { var id: String }
        return try id(JSONDecoder().decode(Response.self, from: await request("POST", "v1/sessions/\(id(sessionID))/jobs",
            body: ManifestCoding.encoder().encode(preparation), headers: ["Idempotency-Key": requestKey])).id)
    }
    public func personalPreparationResult(jobID: String, inputs: PersonalPreparationInputs) async throws -> ProcessingPreparationResult {
        let status = try await job(jobID)
        guard status.state == "succeeded", let hash = status.outputHash else {
            throw CaptureError.invalid("The personal preparation job has no completed result.")
        }
        let data = try await request("GET", "v1/jobs/\(id(jobID))/result")
        return try await Task.detached {
            try ProcessingPreparationResult.verify(data: data, outputSHA256: hash, inputs: inputs)
        }.value
    }
    public func submitPersonalConditioning(sessionID: String, conditioning: PersonalConditioningRequest, requestKey: String) async throws -> String {
        try conditioning.validate(); _ = try id(requestKey)
        struct Response: Decodable { var id: String }
        return try id(JSONDecoder().decode(Response.self,from:await request("POST","v1/sessions/\(id(sessionID))/jobs",
            body:ManifestCoding.encoder().encode(conditioning),headers:["Idempotency-Key":requestKey])).id)
    }
    /// Preserve the published preparation bytes; re-encoding its decoded value
    /// would produce a different object hash for the next job's input.
    public func personalConditioningInputs(preparationJobID: String, inputs: PersonalPreparationInputs,
                                           modelSampleSHA256: String) async throws -> PersonalConditioningInputs {
        let status = try await job(preparationJobID)
        guard status.state == "succeeded", let hash = status.outputHash else {
            throw CaptureError.invalid("The preparation job has no completed result.")
        }
        let data = try await request("GET","v1/jobs/\(id(preparationJobID))/result")
        return try await Task.detached {
            let context = PersonalConditioningInputs(preparationInputs:inputs,preparationData:data,
                preparationSHA256:hash,modelSampleSHA256:modelSampleSHA256)
            _ = try context.request()
            return context
        }.value
    }
    public func personalConditioningResult(jobID: String, inputs: PersonalConditioningInputs) async throws -> ProcessingConditioningResult {
        try await personalConditioningArtifact(jobID:jobID,inputs:inputs).result
    }
    public func personalConditioningArtifact(jobID: String, inputs: PersonalConditioningInputs) async throws -> (data: Data, outputSHA256: String, result: ProcessingConditioningResult) {
        let status = try await job(jobID)
        guard status.state == "succeeded", let hash = status.outputHash else {
            throw CaptureError.invalid("The personal conditioning job has no completed result.")
        }
        let data = try await request("GET","v1/jobs/\(id(jobID))/result")
        return try await Task.detached {
            let result = try ProcessingConditioningResult.verify(data:data,outputSHA256:hash,inputs:inputs)
            return (data:data,outputSHA256:hash,result:result)
        }.value
    }
    /// Idempotent request; inspect status afterward because completion may have won the race.
    public func cancelJob(_ identity: String) async throws {
        _ = try await request("POST", "v1/jobs/\(id(identity))/cancel")
    }
    public func compiledResult(jobID: String, inputData: Data, haircutData: Data) async throws -> ProcessingCompilationResult {
        let status = try await job(jobID)
        guard status.state == "succeeded", let hash = status.outputHash, HairArtifactHash.valid(hash) else {
            throw CaptureError.invalid("The requested job has no completed result.")
        }
        let data = try await request("GET", "v1/jobs/\(id(jobID))/result")
        return try await Task.detached {
            try ProcessingCompilationResult.verify(data: data, outputSHA256: hash, inputData: inputData, haircutData: haircutData)
        }.value
    }
    public func deleteSession(_ identity: String) async throws { _ = try await request("DELETE", "v1/sessions/\(id(identity))") }
    public func generatedGuides(jobID: String, description: String, seed: Int) async throws -> ProcessingGenerationResult {
        let status = try await job(jobID)
        guard status.state == "succeeded", let hash = status.outputHash else {
            throw CaptureError.invalid("The research generation job has no completed result.")
        }
        let data = try await request("GET", "v1/jobs/\(id(jobID))/result")
        return try await Task.detached {
            try ProcessingGenerationResult.verify(data: data, outputSHA256: hash, description: description, seed: seed)
        }.value
    }
    public func submitResearchGeneration(sessionID: String, description: String, seed: Int, requestKey: String) async throws -> String {
        guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, description.count <= 400,
              !description.unicodeScalars.contains(where: { $0.value < 32 }), (0...2_147_483_647).contains(seed) else {
            throw CaptureError.invalid("Invalid research description or seed.")
        }
        _ = try id(requestKey)
        let body = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "kind": "generate_haar_template",
            "description": description, "seed": seed])
        struct Response: Decodable { var id: String }
        return try id(JSONDecoder().decode(Response.self, from: await request("POST", "v1/sessions/\(id(sessionID))/jobs",
            body: body, headers: ["Idempotency-Key": requestKey])).id)
    }
}
