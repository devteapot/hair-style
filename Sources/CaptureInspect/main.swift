import Foundation
import HairCore
import CoreImage

func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else { throw CaptureError.invalid("Usage: capture-inspect fixture OUTPUT_DIR [front|rear] | inspect BUNDLE | ply BUNDLE FRAME_INDEX OUTPUT.ply | register INPUT.json OUTPUT.json | register-captures SOURCE_BUNDLE TARGET_BUNDLE SELECTION.json REPORT.json | surface CAPTURE_ROOT REQUEST.json OUTPUT.json OUTPUT.ply | face-landmarks BUNDLE FRAME_INDEX ROTATION REPORT.json | surface-hash SURFACE.json | canonical-surface SURFACE.json SELECTION.json OUTPUT.json | hair-fixture OUTPUT_DIR | hair-clearance INPUT.json HAIRCUT.json ANATOMY.json REPORT.json | hair-validate INPUT.json HAIRCUT.json REPORT.json | hair-edit INPUT.json BASE.json EDIT.json RESULT.json REPOSITORY_DIR [ANATOMY.json]") }
    switch command {
    case "conditioning-fit-verify":
        guard args.count == 9 else { throw CaptureError.invalid("conditioning-fit-verify requires INPUT BASE CANDIDATE MAPPING ANATOMY FIT EXPECTED_SAMPLE_SHA256 OUTPUT.") }
        let decoder = ManifestCoding.decoder()
        func data(_ index: Int) throws -> Data {
            let url = URL(fileURLWithPath: args[index])
            guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max) <= 100_000_000 else { throw CaptureError.invalid("Fit input exceeds its byte budget.") }
            return try Data(contentsOf:url)
        }
        let result = try decoder.decode(ConditioningDirectionFit.self,from:data(6)).verify(
            input:decoder.decode(HairDesignInput.self,from:data(1)),
            base:decoder.decode(HaircutRevision.self,from:data(2)),
            candidate:decoder.decode(HaircutRevision.self,from:data(3)),
            mapping:decoder.decode(ModelGuideImportRequest.self,from:data(4)),
            anatomy:decoder.decode(GuideClearanceInput.self,from:data(5)),expectedSampleSHA256:args[7])
        try ManifestCoding.encoder().encode(result).write(to:URL(fileURLWithPath:args[8]),options:.atomic)
        print("Replayed bounded direction fit and complete supplied-anatomy clearance; physical acceptance remains false.")
    case "image-detail":
        guard args.count == 4, let index = Int(args[2]), index >= 0 else {
            throw CaptureError.invalid("image-detail requires BUNDLE FRAME_INDEX OUTPUT.json.")
        }
        let bundle = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[3])
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw CaptureError.invalid("Image-detail output already exists.")
        }
        guard try CaptureBundle.inspect(bundle).valid else { throw CaptureError.invalid("Capture integrity failed.") }
        let manifest = try CaptureBundle.load(bundle)
        guard index < manifest.frames.count else { throw CaptureError.invalid("Frame index is outside this recording.") }
        let frame = manifest.frames[index]
        let data = try Data(contentsOf: bundle.appendingPathComponent(frame.image.path))
        guard EvidenceHash.sha256(data) == frame.image.sha256,
              let image = CIImage(data: data, options: [.applyOrientationProperty: false]) else {
            throw CaptureError.invalid("Image changed or could not be decoded.")
        }
        let context = CIContext()
        let detail = try ImageDetailEvidence.measure(image: image, context: context)
        struct Report: Encodable {
            var captureID: String; var frameID: String; var imageSHA256: String
            var source = "saved_jpeg"
            var diagnostic: ImageDetailEvidence
            var scanQualityValidated = false
            var note = "JPEG compression can change this diagnostic relative to the pre-encoding camera buffer. Lighting, contrast and texture affect detail; no blur or scan-acceptance threshold is calibrated."
        }
        try ManifestCoding.encoder().encode(Report(captureID: manifest.id, frameID: frame.metadata.id,
            imageSHA256: frame.image.sha256, diagnostic: detail)).write(to: output, options: .atomic)
        print("Measured saved JPEG image detail. Original capture unchanged; scan quality remains unverified.")
    case "preparation-consume":
        guard args.count == 8 else { throw CaptureError.invalid("preparation-consume requires RESULT.json OUTPUT_SHA256 INPUT.json BRIEF.json MAPPING.json ANATOMY.json OUTPUT_INPUT.json.") }
        func readBounded(_ path:String, maximum:Int) throws -> Data {
            let url=URL(fileURLWithPath:path)
            guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max) <= maximum else {
                throw CaptureError.invalid("Preparation file exceeds its size limit.")
            }
            return try Data(contentsOf:url)
        }
        let inputs=try PersonalPreparationInputs(input:readBounded(args[3],maximum:25_000_000),
            preparedBrief:readBounded(args[4],maximum:25_000_000),mapping:readBounded(args[5],maximum:25_000_000),
            anatomy:readBounded(args[6],maximum:25_000_000))
        let result=try ProcessingPreparationResult.verify(data:readBounded(args[1],maximum:100_000_000),outputSHA256:args[2],inputs:inputs)
        guard result.attachmentsReady else { throw CaptureError.invalid("Attachment review is required before model execution.") }
        guard !FileManager.default.fileExists(atPath:args[7]) else { throw CaptureError.invalid("Preparation output already exists.") }
        try result.generationInputData.write(to:URL(fileURLWithPath:args[7]),options:.atomic)
        print("Consumed exact verified preparation bytes. Missing anatomy and physical fit remain unverified.")
    case "brief-prepare", "brief-consume":
        guard args.count==4 else { throw CaptureError.invalid("\(command) requires SOURCE.json REQUEST_OR_PREPARED.json OUTPUT.json.") }
        let decoder=ManifestCoding.decoder()
        let source=try decoder.decode(HairDesignInput.self,from:Data(contentsOf:URL(fileURLWithPath:args[1])))
        let data=try Data(contentsOf:URL(fileURLWithPath:args[2]))
        let output:Data
        if command=="brief-prepare" {
            let request=try decoder.decode(DesignBriefRequest.self,from:data)
            output=try ManifestCoding.encoder().encode(PreparedDesignBrief.prepare(source:source,request:request))
        } else {
            let prepared=try decoder.decode(PreparedDesignBrief.self,from:data)
            output=try ManifestCoding.encoder().encode(prepared.validatedInput(source:source))
        }
        try output.write(to:URL(fileURLWithPath:args[3]),options:.atomic)
        print("Verified brief handoff. Personal generation and feasibility remain unverified.")
    case "capture-timing":
        guard args.count == 3 else { throw CaptureError.invalid("capture-timing requires BUNDLE OUTPUT.json.") }
        let bundle = URL(fileURLWithPath: args[1])
        let integrity = try CaptureBundle.inspect(bundle)
        guard integrity.valid else { throw CaptureError.invalid("Capture payload integrity failed.") }
        let report = try CaptureTimingReport.analyze(CaptureBundle.load(bundle))
        try ManifestCoding.encoder().encode(report).write(to: URL(fileURLWithPath: args[2]), options: .atomic)
        print("Audited saved timestamps for \(report.frameCount) frames; requested rate is not measured throughput.")
    case "face-conditioned-brief":
        guard args.count==5 else { throw CaptureError.invalid("face-conditioned-brief requires INPUT.json SCALP_REVIEW.json REQUEST.json OUTPUT.json.") }
        let decoder=ManifestCoding.decoder()
        let input=try decoder.decode(HairDesignInput.self,from:Data(contentsOf:URL(fileURLWithPath:args[1])))
        let review=try decoder.decode(ScalpReviewDocument.self,from:Data(contentsOf:URL(fileURLWithPath:args[2])))
        let request=try decoder.decode(FaceConditionedBriefRequest.self,from:Data(contentsOf:URL(fileURLWithPath:args[3])))
        let result=try FaceConditionedBrief.compile(input:input,review:review,request:request)
        try ManifestCoding.encoder().encode(result).write(to:URL(fileURLWithPath:args[4]),options:.atomic)
        print("Experimental feature-conditioned fringe cap: \(result.constrainedFringeLengthMeters*1000) mm. Aesthetic suitability unverified.")
    case "model-review-check":
        guard args.count==3 else { throw CaptureError.invalid("model-review-check requires PACKAGE.json REPORT.json.") }
        let data=try Data(contentsOf:URL(fileURLWithPath:args[1]))
        guard data.count<=100_000_000 else { throw CaptureError.invalid("Model review package exceeds 100 MB.") }
        let package=try ManifestCoding.decoder().decode(ModelReviewPackage.self,from:data)
        let prepared=try package.prepare()
        let report:[String:Any]=["packageSHA256":EvidenceHash.sha256(data),
            "haircutSHA256":prepared.mesh.haircutSHA256,"sourceImportSHA256":prepared.imported.validation.haircutSHA256,
            "researchRevision":package.researchRevision != nil,"guideCount":prepared.haircut.guides.count,"meshVertexCount":prepared.mesh.vertices.count,
            "faceVertexCount":prepared.observedFace.vertices.count,"acceptedForPersonalHaircut":false,
            "guardChecked":prepared.imported.validation.checksCompleted.contains("continuous_inferred_envelope_centerline")]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:args[2]),options:.atomic)
        print("Replayed model import, face/scalp binding and mesh preparation for \(prepared.mesh.guideCount) guides.")
    case "conditioning-review-package":
        guard args.count == 6 else { throw CaptureError.invalid("conditioning-review-package requires RESULT.json OUTPUT_SHA256 CONTEXT.json SCALP_REVIEW.json PACKAGE.json.") }
        func boundedRead(_ path: String, limit: Int) throws -> Data {
            let url=URL(fileURLWithPath:path)
            guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max)<=limit else { throw CaptureError.invalid("Conditioning handoff input exceeds its byte limit.") }
            let data=try Data(contentsOf:url)
            guard data.count<=limit else { throw CaptureError.invalid("Conditioning handoff input grew beyond its byte limit.") }
            return data
        }
        let output=URL(fileURLWithPath:args[5])
        guard !FileManager.default.fileExists(atPath:output.path) else { throw CaptureError.invalid("Refusing to overwrite an existing review handoff.") }
        let context=try ManifestCoding.decoder().decode(PersonalConditioningInputs.self,from:boundedRead(args[3],limit:100_000_000))
        let result=try ProcessingConditioningResult.verify(data:boundedRead(args[1],limit:100_000_000),outputSHA256:args[2],inputs:context)
        let scalp=try ManifestCoding.decoder().decode(ScalpReviewDocument.self,from:boundedRead(args[4],limit:100_000_000))
        let package=try result.modelReviewPackage(scalpReview:scalp)
        try ManifestCoding.encoder().encode(package).write(to:output,options:.atomic)
        print("Created exact candidate review handoff. Physical/style acceptance remains false.")
    case "hair-image-color":
        guard args.count == 8, let region = HairRegion(rawValue: args[6]) else {
            throw CaptureError.invalid("hair-image-color requires INPUT.json HAIRCUT.json CAPTURE_BUNDLE FRAME_ID REPORT.json REGION OUTPUT.json.")
        }
        let input = try ManifestCoding.decoder().decode(HairDesignInput.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let haircut = try ManifestCoding.decoder().decode(HaircutRevision.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let reportURL = URL(fileURLWithPath: args[5])
        guard let size = try reportURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_048_576 else { throw CaptureError.invalid("Color report is too large.") }
        let color = try RecordedHairColor.fromReport(Data(contentsOf: reportURL), bundle: URL(fileURLWithPath: args[3]), frameID: args[4])
        let edit = HairEdit(baseSHA256: try HairArtifactHash.digest(haircut), operation: .matchRecordedColor, region: region, value: 0, recordedColor: color)
        let result = try HaircutEditor.apply(edit, to: haircut, input: input)
        let output = URL(fileURLWithPath: args[7])
        guard !FileManager.default.fileExists(atPath: output.path) else { throw CaptureError.invalid("Output already exists.") }
        try ManifestCoding.encoder().encode(result.haircut).write(to: output, options: .atomic)
        print("Created approximate recorded-color revision for \(result.changedGuideIDs.count) guides. Geometry and fit status are unchanged.")
    case "hair-image-review":
        guard args.count == 4 else { throw CaptureError.invalid("hair-image-review requires CAPTURE_BUNDLE FRAME_ID REPORT.json.") }
        let reportURL = URL(fileURLWithPath: args[3])
        guard let size = try reportURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_048_576 else {
            throw CaptureError.invalid("Hair analysis file is too large.")
        }
        let value = try HairImageAnalysis.validated(Data(contentsOf: reportURL),
            bundle: URL(fileURLWithPath: args[1]), frameID: args[2])
        print("Validated review-only image report: \(value.observation.hairPixels) hair pixels. Profile acceptance remains false.")
    case "hair-mesh":
        guard (4...6).contains(args.count) else { throw CaptureError.invalid("hair-mesh requires INPUT.json HAIRCUT.json OUTPUT.json [RADIAL_SIDES] [DIAGNOSTIC_RADIUS_SCALE].") }
        let input = try ManifestCoding.decoder().decode(HairDesignInput.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let haircut = try ManifestCoding.decoder().decode(HaircutRevision.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let sides: Int
        if args.count >= 5 { guard let value = Int(args[4]) else { throw CaptureError.invalid("Invalid radial sides.") }; sides = value } else { sides = 6 }
        let scale: Double
        if args.count >= 6 { guard let value = Double(args[5]) else { throw CaptureError.invalid("Invalid diagnostic radius scale.") }; scale = value } else { scale = 1 }
        let mesh = try HairMeshCompiler.compile(input: input, haircut: haircut, radialSides: sides, radiusScale: scale)
        try ManifestCoding.encoder().encode(mesh).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
        print("Compiled \(mesh.guideCount) guides into \(mesh.vertices.count) vertices. Canonical revision hash: \(mesh.haircutSHA256).")
    case "hair-ribbon-mesh":
        guard (4...5).contains(args.count) else { throw CaptureError.invalid("hair-ribbon-mesh requires INPUT.json HAIRCUT.json OUTPUT.json [RADIUS_SCALE].") }
        let input=try ManifestCoding.decoder().decode(HairDesignInput.self,from:Data(contentsOf:URL(fileURLWithPath:args[1])))
        let haircut=try ManifestCoding.decoder().decode(HaircutRevision.self,from:Data(contentsOf:URL(fileURLWithPath:args[2])))
        let scale: Double
        if args.count==5 { guard let value=Double(args[4]) else { throw CaptureError.invalid("Invalid ribbon radius scale.") };scale=value }
        else { scale=1 }
        let mesh=try HairRibbonCompiler.compile(input:input,haircut:haircut,radiusScale:scale)
        try ManifestCoding.encoder().encode(mesh).write(to:URL(fileURLWithPath:args[3]),options:.atomic)
        print("Compiled \(mesh.guideCount) guides into \(mesh.vertices.count) ribbon vertices. Canonical source unchanged.")
    case "hair-model-import":
        guard args.count == 5 else { throw CaptureError.invalid("hair-model-import requires INPUT.json SOURCE_STRANDS.json MAPPING.json RESULT.json.") }
        let input = try ManifestCoding.decoder().decode(HairDesignInput.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let source = try Data(contentsOf: URL(fileURLWithPath: args[2]))
        let request = try ManifestCoding.decoder().decode(ModelGuideImportRequest.self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
        let result = try ModelGuideImport.apply(sourceData: source, input: input, request: request)
        try ManifestCoding.encoder().encode(result).write(to: URL(fileURLWithPath: args[4]), options: .atomic)
        print("Imported \(result.haircut.guides.count) editable model guides. Correspondence, personal design and physical feasibility remain unvalidated.")
    case "hair-conditioning-binding":
        guard args.count == 4 else { throw CaptureError.invalid("hair-conditioning-binding requires INPUT.json MAPPING.json OUTPUT.json.") }
        let input = try ManifestCoding.decoder().decode(HairDesignInput.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let mapping = try ManifestCoding.decoder().decode(ModelGuideImportRequest.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        try HaircutValidator.validateInput(input)
        let binding = ["inputSHA256": try HairArtifactHash.digest(input), "mappingGeometrySHA256": try ModelGuideImport.conditioningGeometryHash(mapping)]
        try JSONSerialization.data(withJSONObject: binding, options: [.sortedKeys, .prettyPrinted]).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
    case "hair-clearance-batch":
        guard args.count == 5 else { throw CaptureError.invalid("hair-clearance-batch requires INPUT.json HAIRCUTS.json ANATOMY.json REPORTS.json.") }
        let input = try ManifestCoding.decoder().decode(HairDesignInput.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let haircuts = try ManifestCoding.decoder().decode([HaircutRevision].self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let anatomy = try ManifestCoding.decoder().decode(GuideClearanceInput.self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
        let reports = try GuideClearance.checkBatch(input: input, haircuts: haircuts, anatomy: anatomy)
        try ManifestCoding.encoder().encode(reports).write(to: URL(fileURLWithPath: args[4]), options: .atomic)
        print("Checked \(reports.count) candidates with shared anatomy. Physical validation remains incomplete.")
        if reports.contains(where: { !$0.surfaceChecksPassed }) { exit(2) }
    case "hair-clearance":
        guard args.count == 5 else { throw CaptureError.invalid("hair-clearance requires INPUT.json HAIRCUT.json ANATOMY.json REPORT.json.") }
        let input = try ManifestCoding.decoder().decode(HairDesignInput.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let haircut = try ManifestCoding.decoder().decode(HaircutRevision.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let anatomy = try ManifestCoding.decoder().decode(GuideClearanceInput.self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
        let report = try GuideClearance.check(input: input, haircut: haircut, anatomy: anatomy)
        try ManifestCoding.encoder().encode(report).write(to: URL(fileURLWithPath: args[4]), options: .atomic)
        print("Guide clearance: \(report.violations.count) segment violations; \(report.rootViolations?.count ?? 0) fixed-root violations; \(report.missingRegions.count) missing regions. Physical validation remains incomplete.")
        if !report.surfaceChecksPassed { exit(2) }
    case "hair-root-preflight":
        guard args.count == 6, let radius = Double(args[4]) else { throw CaptureError.invalid("hair-root-preflight requires INPUT.json MAPPING.json ANATOMY.json RADIUS_METERS REPORT.json.") }
        let input = try ManifestCoding.decoder().decode(HairDesignInput.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let mapping = try ManifestCoding.decoder().decode(ModelGuideImportRequest.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let anatomy = try ManifestCoding.decoder().decode(GuideClearanceInput.self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
        guard mapping.scalpSHA256 == input.brief.scalpSHA256 else { throw CaptureError.invalid("Root mapping is stale.") }
        let report = try GuideClearance.preflightRoots(input: input, bindings: mapping.mappings, materialRadiusMeters: radius, anatomy: anatomy)
        try ManifestCoding.encoder().encode(report).write(to: URL(fileURLWithPath: args[5]), options: .atomic)
        print("Checked \(report.rootCount) proposed roots before generation: \(report.violations.count) conflicts, \(report.missingRegions.count) missing regions.")
        if report.requiresAttachmentReview { exit(2) }
    case "face-landmarks":
        guard args.count == 5, let index = Int(args[2]), let rotation = ImageQuarterTurn(rawValue: args[3]) else {
            throw CaptureError.invalid("face-landmarks requires BUNDLE FRAME_INDEX none|clockwise90|clockwise180|clockwise270 REPORT.json.")
        }
        let bundle = URL(fileURLWithPath: args[1])
        let manifest = try CaptureBundle.load(bundle)
        guard manifest.frames.indices.contains(index) else { throw CaptureError.invalid("Frame index out of bounds.") }
        let result = try FaceLandmarkExtractor.extract(bundle: bundle, frameID: manifest.frames[index].metadata.id, rotation: rotation)
        try ManifestCoding.encoder().encode(result).write(to: URL(fileURLWithPath: args[4]), options: .atomic)
        print("Face analysis: \(result.status.rawValue), \(result.points.count) landmark estimates. Source: \(result.source.rawValue).")
        if result.status != .detected { exit(2) }
    case "surface-hash":
        guard args.count == 2 else { throw CaptureError.invalid("surface-hash requires SURFACE.json.") }
        let surface = try ManifestCoding.decoder().decode(ObservedSurface.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        print(try HairArtifactHash.digest(surface))
    case "canonical-surface":
        guard args.count == 4 else { throw CaptureError.invalid("canonical-surface requires SURFACE.json SELECTION.json OUTPUT.json.") }
        let surface = try ManifestCoding.decoder().decode(ObservedSurface.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let selection = try ManifestCoding.decoder().decode(AnatomicalSelection.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let result = try AnatomicalFrame.canonicalize(surface, selection: selection)
        try ManifestCoding.encoder().encode(result).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
        print("Reoriented \(result.vertices.count) observed vertices. Source: \(result.source.rawValue). Scalp completion remains unavailable.")
    case "live-calibrate":
        guard args.count == 4 else { throw CaptureError.invalid("live-calibrate requires SCALP.json REQUEST.json RESULT.json.") }
        let scalp = try ManifestCoding.decoder().decode(ScalpProfile.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let request = try ManifestCoding.decoder().decode(LiveCalibrationRequest.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let result = try LiveHairAlignment.calibrate(request, scalp: scalp)
        try ManifestCoding.encoder().encode(result).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
        print("Fitted canonical-to-face calibration with held-out landmarks. Actual camera alignment remains unverified.")
    case "hair-baseline":
        guard (4...5).contains(args.count) else { throw CaptureError.invalid("hair-baseline requires INPUT.json REQUEST.json RESULT.json [ANATOMY.json].") }
        let input = try ManifestCoding.decoder().decode(HairDesignInput.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let request = try ManifestCoding.decoder().decode(BaselineGenerationRequest.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let anatomy = try args.count == 5 ? ManifestCoding.decoder().decode(GuideClearanceInput.self, from: Data(contentsOf: URL(fileURLWithPath: args[4]))) : nil
        let result = try ProceduralHairBaseline.generate(input: input, request: request, anatomy: anatomy)
        try ManifestCoding.encoder().encode(result).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
        print("Generated \(result.haircut.guides.count) procedural baseline guides. AI styling and physical feasibility are not verified.")
    case "hair-brief":
        guard args.count == 5 else { throw CaptureError.invalid("hair-brief requires SCALP.json PROFILE.json REQUEST.json RESULT.json.") }
        let scalp = try ManifestCoding.decoder().decode(ScalpProfile.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let profile = try ManifestCoding.decoder().decode(HairLengthProfile.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let request = try ManifestCoding.decoder().decode(DesignBriefRequest.self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
        let result = try DesignBriefCompiler.compile(scalp: scalp, profile: profile, request: request)
        try ManifestCoding.encoder().encode(result).write(to: URL(fileURLWithPath: args[4]), options: .atomic)
        print("Compiled \(result.input.brief.mode.rawValue) regional constraints. This is a brief, not a generated haircut.")
    case "hair-fixture":
        guard args.count == 2 else { throw CaptureError.invalid("hair-fixture requires OUTPUT_DIRECTORY.") }
        let (input, haircut) = try SyntheticHaircut.create()
        let directory = URL(fileURLWithPath: args[1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try ManifestCoding.encoder().encode(input).write(to: directory.appendingPathComponent("input.json"), options: .atomic)
        try ManifestCoding.encoder().encode(haircut).write(to: directory.appendingPathComponent("haircut.json"), options: .atomic)
        print("Wrote synthetic scalp/guide fixture. This is not a personalized generated hairstyle.")
    case "hair-rotate-proposal":
        guard args.count == 5 || (args.count == 6 && ["--diagonal-axes","--dense-axes"].contains(args[5])) else { throw CaptureError.invalid("hair-rotate-proposal requires INPUT.json HAIRCUT.json ANATOMY.json OUTPUT.json [--diagonal-axes|--dense-axes].") }
        let decoder = ManifestCoding.decoder()
        let input = try decoder.decode(HairDesignInput.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let haircut = try decoder.decode(HaircutRevision.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let anatomy = try decoder.decode(GuideClearanceInput.self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
        let result = try GuideRotationProposal.propose(input: input, haircut: haircut, anatomy: anatomy, includeDiagonalAxes: args.count == 6, includeDenseAxes: args.count == 6 && args[5] == "--dense-axes")
        try ManifestCoding.encoder().encode(result).write(to: URL(fileURLWithPath: args[4]), options: .atomic)
        print("Rotation proposal: \(result.clearance.violations.count) remaining segment conflicts. Physical/style acceptance remains false.")
        if !result.clearance.surfaceChecksPassed { exit(2) }
    case "hair-validate":
        guard args.count == 4 else { throw CaptureError.invalid("hair-validate requires INPUT.json HAIRCUT.json REPORT.json.") }
        let input = try ManifestCoding.decoder().decode(HairDesignInput.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let haircut = try ManifestCoding.decoder().decode(HaircutRevision.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let report = try HaircutValidator.validate(input: input, haircut: haircut)
        try ManifestCoding.encoder().encode(report).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
        print("Geometry checks passed for \(report.guideCount) guides. Physical/design validation remains incomplete.")
    case "hair-edit":
        guard (6...7).contains(args.count) else { throw CaptureError.invalid("hair-edit requires INPUT.json BASE.json EDIT.json RESULT.json REPOSITORY_DIRECTORY [ANATOMY.json].") }
        let input = try ManifestCoding.decoder().decode(HairDesignInput.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let base = try ManifestCoding.decoder().decode(HaircutRevision.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let edit = try ManifestCoding.decoder().decode(HairEdit.self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
        let anatomy = try args.count == 7 ? ManifestCoding.decoder().decode(GuideClearanceInput.self, from: Data(contentsOf: URL(fileURLWithPath: args[6]))) : nil
        let result = try HaircutEditor.apply(edit, to: base, input: input, anatomy: anatomy)
        let repository = HaircutRepository(root: URL(fileURLWithPath: args[5]))
        try repository.save(input: input, haircut: base)
        let hash = try repository.save(input: input, haircut: result.haircut)
        try ManifestCoding.encoder().encode(result).write(to: URL(fileURLWithPath: args[4]), options: .atomic)
        print("Saved revision \(result.haircut.revision), hash \(hash). Changed \(result.changedGuideIDs.count) guides. Feasibility remains uncertain.")
    case "scalp-suggest":
        guard args.count == 4 else { throw CaptureError.invalid("scalp-suggest requires SURFACE.json SELECTION.json ENVELOPE.json.") }
        let surface=try ManifestCoding.decoder().decode(ObservedSurface.self,from:Data(contentsOf:URL(fileURLWithPath:args[1])))
        let selection=try ManifestCoding.decoder().decode(AnatomicalSelection.self,from:Data(contentsOf:URL(fileURLWithPath:args[2])))
        let envelope=try ScalpCompletion.suggestedEnvelope(surface:surface,selection:selection)
        try ManifestCoding.encoder().encode(envelope).write(to:URL(fileURLWithPath:args[3]))
    case "scalp-complete":
        guard args.count == 4 else { throw CaptureError.invalid("scalp-complete requires SURFACE.json REQUEST.json RESULT.json.") }
        let surface=try ManifestCoding.decoder().decode(ObservedSurface.self,from:Data(contentsOf:URL(fileURLWithPath:args[1])))
        let request=try ManifestCoding.decoder().decode(ScalpCompletionRequest.self,from:Data(contentsOf:URL(fileURLWithPath:args[2])))
        let result=try ScalpCompletion.build(surface:surface,request:request)
        try ManifestCoding.encoder().encode(result).write(to:URL(fileURLWithPath:args[3]))
        print("Inferred scalp candidate: \(result.scalp.triangles.count) triangles. Shape and hairline review required.")
    case "tracked-register":
        guard args.count == 4 else { throw CaptureError.invalid("tracked-register requires BUNDLE REQUEST.json OUTPUT.json.") }
        let request = try ManifestCoding.decoder().decode(HeadPoseRegistrationRequest.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let report = try HeadPoseRegistration.inspect(bundle: URL(fileURLWithPath: args[1]), request: request)
        try ManifestCoding.encoder().encode(report).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
        print("Tracked initializer evaluated against \(report.validationResiduals.count) independent landmarks. Not accepted for fusion.")
    case "flow-register":
        guard args.count == 4 else { throw CaptureError.invalid("flow-register requires BUNDLE REQUEST.json OUTPUT.json.") }
        let request = try ManifestCoding.decoder().decode(CaptureFlowRequest.self,from:Data(contentsOf:URL(fileURLWithPath:args[2])))
        let report = try CaptureFlowRegistration.estimate(bundle:URL(fileURLWithPath:args[1]),request:request)
        try ManifestCoding.encoder().encode(report).write(to:URL(fileURLWithPath:args[3]),options:.atomic)
        print("Flow matches: \(report.counts["consistentDepthMatches",default:0]); local rigid gate: \(report.registration?.registration.accepted == true). Full-head validation remains incomplete.")
    case "world-region-masks":
        guard args.count == 4 else { throw CaptureError.invalid("world-region-masks requires BUNDLE REQUEST.json OUTPUT.json.") }
        let request = try ManifestCoding.decoder().decode(WorldRegionRequest.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let report = try WorldRegionMasks.build(bundle: URL(fileURLWithPath: args[1]), request: request)
        try ManifestCoding.encoder().encode(report).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
        print("Spatial masks: \(report.frames.filter { $0.mask != nil }.count) frames. Subject motion and semantic masking remain unresolved.")
    case "projective-agreement":
        guard args.count == 5 else { throw CaptureError.invalid("projective-agreement requires SOURCE_SURFACE.json TARGET_BUNDLE REQUEST.json OUTPUT.json.") }
        let decoder = ManifestCoding.decoder()
        let surface = try decoder.decode(ObservedSurface.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let request = try decoder.decode(ProjectiveDepthRequest.self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
        let report = try ProjectiveDepthAgreement.inspect(surface: surface, targetBundle: URL(fileURLWithPath: args[2]), request: request)
        try ManifestCoding.encoder().encode(report).write(to: URL(fileURLWithPath: args[4]), options: .atomic)
        print("Projective diagnostic: \(report.counts). No fusion acceptance.")
    case "surface-agreement":
        guard args.count == 5 else { throw CaptureError.invalid("surface-agreement requires SOURCE_SURFACE.json TARGET_SURFACE.json CAPTURED_REGISTRATION.json OUTPUT.json.") }
        let decoder = ManifestCoding.decoder()
        let source = try decoder.decode(ObservedSurface.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let target = try decoder.decode(ObservedSurface.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let registration = try decoder.decode(CapturedRegistrationReport.self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
        let result = try DenseSurfaceAgreement.compare(source: source, target: target, registration: registration)
        try ManifestCoding.encoder().encode(result).write(to: URL(fileURLWithPath: args[4]), options: .atomic)
        print("Dense diagnostic p95: source→target \(result.sourceToTarget.p95Meters*1000) mm, target→source \(result.targetToSource.p95Meters*1000) mm. Not an accuracy certification.")
    case "projective-fuse":
        guard args.count == 4 else { throw CaptureError.invalid("projective-fuse requires CAPTURE_ROOT REQUEST.json OUTPUT.json.") }
        let request = try ManifestCoding.decoder().decode(ProjectiveFusionRequest.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let result = try ProjectiveSurfaceFusion.rebuild(captureRoot: URL(fileURLWithPath: args[1]), request: request)
        try ManifestCoding.encoder().encode(result).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
        print("Experimental projective fusion: \(result.vertices.count) vertices, \(result.triangles.count) triangles. Not accepted for haircut fitting.")
    case "remesh-surface":
        guard args.count == 3 else { throw CaptureError.invalid("remesh-surface requires OBSERVED_SURFACE.json OUTPUT.json.") }
        let source = try ManifestCoding.decoder().decode(ObservedSurface.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let result = try SurfaceRemesher.rebuild(source)
        try ManifestCoding.encoder().encode(result).write(to: URL(fileURLWithPath: args[2]), options: .atomic)
        print("Experimental remesh: \(result.vertices.count) vertices, \(result.triangles.count) triangles, \(result.topology.boundaryEdges) boundary edges. Not approved for haircut fitting.")
    case "surface":
        guard args.count == 5 else { throw CaptureError.invalid("surface requires CAPTURE_ROOT REQUEST.json OUTPUT.json OUTPUT.ply.") }
        let request = try ManifestCoding.decoder().decode(SurfaceRequest.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let surface = try ObservedSurfaceBuilder.build(captureRoot: URL(fileURLWithPath: args[1]), request: request)
        try ManifestCoding.encoder().encode(surface).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
        try surface.ply().write(to: URL(fileURLWithPath: args[4]), options: .atomic)
        print("Partial observed surface: \(surface.vertices.count) vertices, \(surface.triangles.count) triangles. Source: \(surface.source.rawValue). Not a complete head.")
    case "register-captures":
        guard args.count == 5 else { throw CaptureError.invalid("register-captures requires SOURCE_BUNDLE TARGET_BUNDLE SELECTION.json REPORT.json.") }
        let selection = try ManifestCoding.decoder().decode(CaptureLandmarkSelection.self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
        let report = try CalibratedLandmarks.register(sourceBundle: URL(fileURLWithPath: args[1]),
            targetBundle: URL(fileURLWithPath: args[2]), selection: selection)
        try ManifestCoding.encoder().encode(report).write(to: URL(fileURLWithPath: args[4]), options: .atomic)
        print("Captured-frame registration \(report.registration.accepted ? "accepted" : "rejected"). Source: \(report.registration.evidenceSource.rawValue).")
        if !report.registration.accepted { exit(2) }
    case "register":
        guard args.count == 3 else { throw CaptureError.invalid("register requires landmark INPUT.json and report OUTPUT.json.") }
        let input = try ManifestCoding.decoder().decode(RegistrationInput.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let report = try RigidRegistration.register(input)
        try ManifestCoding.encoder().encode(report).write(to: URL(fileURLWithPath: args[2]), options: .atomic)
        print("Registration \(report.accepted ? "accepted" : "rejected"): held-out median \(report.validationMedianMeters * 1000) mm, p95 \(report.validationP95Meters * 1000) mm.")
        if !report.accepted { exit(2) }
    case "fixture":
        guard (2...3).contains(args.count) else { throw CaptureError.invalid("fixture requires an output directory and optional front|rear.") }
        let kind: CaptureKind = args.count == 3 && args[2] == "front" ? .frontFace : .rearHead
        let url = try SyntheticCapture.create(in: URL(fileURLWithPath: args[1]), kind: kind)
        print(url.path)
    case "inspect":
        guard args.count == 2 else { throw CaptureError.invalid("inspect requires a bundle directory.") }
        let report = try CaptureBundle.inspect(URL(fileURLWithPath: args[1]))
        print(String(decoding: try ManifestCoding.encoder().encode(report), as: UTF8.self))
        if !report.valid { exit(2) }
    case "ply":
        guard args.count == 4, let index = Int(args[2]) else { throw CaptureError.invalid("ply requires BUNDLE FRAME_INDEX OUTPUT.ply.") }
        let root = URL(fileURLWithPath: args[1])
        let report = try CaptureBundle.inspect(root)
        guard report.valid else { throw CaptureError.invalid("Bundle failed validation: \(report.errors.joined(separator: "; "))") }
        let manifest = try CaptureBundle.load(root)
        guard manifest.frames.indices.contains(index) else { throw CaptureError.invalid("Frame index out of bounds.") }
        let frame = manifest.frames[index]
        guard let depth = frame.depth, let size = frame.metadata.depthSize, let intrinsics = frame.metadata.intrinsics else {
            throw CaptureError.invalid("Selected frame has no calibrated depth.")
        }
        let values = try DepthGeometry.decode(CaptureBundle.payload(depth, in: root), size: size)
        let points = try DepthGeometry.pointCloud(values: values, size: size, intrinsics: intrinsics)
        try DepthGeometry.ply(points).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
        print("Wrote \(points.count) camera-space points. No head fusion or lens correction has been applied.")
    default: throw CaptureError.invalid("Unknown command: \(command)")
    }
}

do { try run() }
catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1) }
