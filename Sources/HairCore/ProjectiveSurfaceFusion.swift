import Foundation

public struct ProjectiveFusionRequest: Codable, Sendable {
    public var schemaVersion = 1
    public var surfaceRequest: SurfaceRequest
    public var voxelMeters = 0.002
    public var truncationMeters = 0.006
    public var minimumNearSurfaceViews = 2
    public var maximumSignedDistanceSpreadMeters = 0.008
    public var depthDenoising: DepthDenoisingSettings?
    public init(surfaceRequest: SurfaceRequest) { self.surfaceRequest = surfaceRequest }
}

public struct ProjectiveFusedSurface: Codable, Sendable {
    public var schemaVersion = 1
    public var method = "masked_projective_tsdf_marching_tetrahedra_v2"
    public var requestSHA256: String
    public var sourceSurfaceSHA256: String
    public var request: ProjectiveFusionRequest
    public var source: CaptureSource
    public var coordinateConvention = "reference_optical_x_right_y_down_z_forward_meters"
    public var frames: [SurfaceFrameEvidence]
    public var counts: [String: Int]
    public var vertices: [RemeshedVertex]
    public var triangles: [[Int]]
    public var topology: SurfaceTopology
    public var completeHead = false
    public var suitableForHaircutFitting = false
    public var notes: [String]
}

/// Camera-aware experimental fusion of the original depth buffers. Accepted
/// landmark registrations are recomputed before any voxel integration.
public enum ProjectiveSurfaceFusion {
    private struct Frame {
        var camera: CalibratedDepthCamera
        var cameraFromReference: RigidTransform
        var depth: [Float]
        var integrationDepth: [Float]
        var usable: [Bool]
    }

    public static func rebuild(captureRoot: URL, request: ProjectiveFusionRequest) throws -> ProjectiveFusedSurface {
        let h = request.voxelMeters, mu = request.truncationMeters
        guard request.schemaVersion == 1, (0.001...0.005).contains(h),
              mu.isFinite, mu >= 2*h, mu <= min(4*h,0.015),
              (1...8).contains(request.surfaceRequest.frames.count),
              (1...request.surfaceRequest.frames.count).contains(request.minimumNearSurfaceViews),
              request.maximumSignedDistanceSpreadMeters.isFinite,
              request.maximumSignedDistanceSpreadMeters >= h,
              request.maximumSignedDistanceSpreadMeters <= 2*mu,
              !request.surfaceRequest.frames.contains(where: { $0.componentSelection != nil }) else {
            throw CaptureError.invalid("Invalid projective fusion bounds or unsupported component-selected input; use explicit complete masks.")
        }
        // This path reopens captures, verifies their payloads and rejects unsafe
        // registrations. It cannot accept an arbitrary claimed transform report.
        let source = try ObservedSurfaceBuilder.build(captureRoot: captureRoot, request: request.surfaceRequest)
        var frames: [Frame] = []
        var preprocessingCounts: [String:Int] = [:]
        for (index,item) in request.surfaceRequest.frames.enumerated() {
            let bundle = captureRoot.appendingPathComponent(item.captureID)
            let manifest = try CaptureBundle.load(bundle)
            guard let stored = manifest.frames.first(where: { $0.metadata.id == item.frameID }),
                  try HairArtifactHash.digest(stored) == source.frames[index].frameSHA256,
                  let evidence = stored.depth, let size = stored.metadata.depthSize else {
                throw CaptureError.invalid("Capture changed while preparing projective fusion.")
            }
            let depth = try DepthGeometry.decode(CaptureBundle.payload(evidence, in: bundle), size: size)
            let confidence = try stored.confidence.map { try CaptureBundle.payload($0, in: bundle) }
            var mask = try item.mask.decode()
            for pixel in mask.indices {
                mask[pixel] = mask[pixel] && depth[pixel].isFinite && (0.05...2).contains(depth[pixel])
                if let confidence {
                    let level = confidence[confidence.startIndex+pixel]
                    mask[pixel] = mask[pixel] && level >= request.surfaceRequest.minimumConfidence && level <= 2
                }
            }
            let matrix = source.frames[index].referenceFromCamera.rowMajor
            let inverse = RigidTransform(rowMajor: [matrix[0],matrix[4],matrix[8],-(matrix[0]*matrix[3]+matrix[4]*matrix[7]+matrix[8]*matrix[11]),
                matrix[1],matrix[5],matrix[9],-(matrix[1]*matrix[3]+matrix[5]*matrix[7]+matrix[9]*matrix[11]),
                matrix[2],matrix[6],matrix[10],-(matrix[2]*matrix[3]+matrix[6]*matrix[7]+matrix[10]*matrix[11]),0,0,0,1])
            guard inverse.isValid else { throw CaptureError.invalid("Invalid inverse capture pose.") }
            var integrationDepth=depth
            if let settings=request.depthDenoising {
                let filtered=try MaskedDepthDenoising.apply(depth,usable:mask,size:size,settings:settings)
                integrationDepth=filtered.values
                for (key,value) in filtered.counts { preprocessingCounts[key,default:0] += value }
            }
            frames.append(Frame(camera: try CalibratedDepthCamera(frame: stored.metadata), cameraFromReference: inverse,
                                depth: depth, integrationDepth: integrationDepth, usable: mask))
        }
        var candidates = Set<ProjectiveGridKey>()
        let extent = Int(ceil(mu/h))+1
        for vertex in source.vertices {
            let p = vertex.position
            guard p.finite, p.length <= 10 else { throw CaptureError.invalid("Invalid projective seed position.") }
            let center = ProjectiveGridKey(x: Int(floor(p.x/h)), y: Int(floor(p.y/h)), z: Int(floor(p.z/h)))
            for z in -extent...extent { for y in -extent...extent { for x in -extent...extent {
                let key = center.plus(.init(x: x, y: y, z: z))
                // A finite neighborhood prevents unknown distant space from
                // becoming a surface or an implicit whole-head closure.
                if (key.point(h)-p).length <= mu+h { candidates.insert(key) }
            } } }
            guard candidates.count <= 1_000_000 else { throw CaptureError.invalid("Projective fusion exceeds one million candidate nodes.") }
        }
        var grid: [ProjectiveGridKey: Double] = [:]
        var counts = ["candidateNodes": candidates.count, "retainedNodes": 0, "insufficientViewNodes": 0, "disagreementNodes": 0,
                      "outsideCameraSamples": 0, "maskedOrInvalidSamples": 0, "occludedSamples": 0, "farFreeSpaceSamples": 0,
                      "nearSurfaceSamples": 0]
        for key in candidates.sorted() {
            let point = key.point(h)
            var values: [Double] = [], integrationValues: [Double] = [], near = 0
            for frame in frames {
                let p = frame.cameraFromReference.apply(point)
                guard let pixel = frame.camera.pixel(point: p) else { counts["outsideCameraSamples",default:0] += 1; continue }
                let x = min(frame.camera.size.width-1, Int(pixel.x.rounded()))
                let y = min(frame.camera.size.height-1, Int(pixel.y.rounded()))
                let index = y*frame.camera.size.width+x
                guard frame.usable[index] else { counts["maskedOrInvalidSamples",default:0] += 1; continue }
                let distance = Double(frame.depth[index])-p.z
                // Space more than mu behind this visible surface is occluded;
                // it contributes no statement about hidden anatomy.
                guard distance >= -mu else { counts["occludedSamples",default:0] += 1; continue }
                if distance > mu { counts["farFreeSpaceSamples",default:0] += 1 }
                else { near += 1; counts["nearSurfaceSamples",default:0] += 1 }
                values.append(distance)
                integrationValues.append(max(-mu,min(mu,Double(frame.integrationDepth[index])-p.z)))
            }
            guard near >= request.minimumNearSurfaceViews else { counts["insufficientViewNodes",default:0] += 1; continue }
            guard values.max()!-values.min()! <= request.maximumSignedDistanceSpreadMeters else {
                counts["disagreementNodes",default:0] += 1; continue
            }
            // Check actual signed distances before truncating free space: a
            // distant contradictory observation must not become a small error.
            grid[key] = integrationValues.reduce(0,+)/Double(integrationValues.count)
        }
        counts["retainedNodes"] = grid.count
        counts.merge(preprocessingCounts,uniquingKeysWith:+)
        let extracted = try ProjectiveFieldExtraction.extract(grid, spacing: h)
        var supported: [Bool] = []
        counts["extractedVertices"] = extracted.vertices.count
        counts["verticesBelowMinimumViews"] = 0; counts["verticesWithDepthDisagreement"] = 0
        for vertex in extracted.vertices {
            var values: [Double] = [], near = 0
            for frame in frames {
                let p = frame.cameraFromReference.apply(vertex.position)
                guard let pixel = frame.camera.pixel(point: p) else { continue }
                let x = min(frame.camera.size.width-1, Int(pixel.x.rounded()))
                let y = min(frame.camera.size.height-1, Int(pixel.y.rounded()))
                let index = y*frame.camera.size.width+x
                guard frame.usable[index] else { continue }
                let distance = Double(frame.depth[index])-p.z
                guard distance >= -mu else { continue }
                if distance <= mu { near += 1 }
                values.append(distance)
            }
            let hasViews = near >= request.minimumNearSurfaceViews
            let agrees = !values.isEmpty && values.max()!-values.min()! <= request.maximumSignedDistanceSpreadMeters
            if !hasViews { counts["verticesBelowMinimumViews",default:0] += 1 }
            if !agrees { counts["verticesWithDepthDisagreement",default:0] += 1 }
            supported.append(hasViews && agrees)
        }
        let mesh = try ProjectiveFieldExtraction.retaining(extracted, supported: supported)
        counts["removedUnsupportedTriangles"] = extracted.triangles.count-mesh.triangles.count
        counts["retainedVertices"] = mesh.vertices.count
        return ProjectiveFusedSurface(method: request.depthDenoising == nil ? "masked_projective_tsdf_marching_tetrahedra_v2" : "masked_denoised_projective_tsdf_v1",
            requestSHA256: try HairArtifactHash.digest(request), sourceSurfaceSHA256: try HairArtifactHash.digest(source),
            request: request, source: source.source, frames: source.frames, counts: counts, vertices: mesh.vertices,
            triangles: mesh.triangles, topology: mesh.topology,
            notes: ["Projective signed distance uses original native depth, explicit masks, rigid registered camera poses and calibrated lens projection.",
                request.depthDenoising == nil ? "Depth integration uses unchanged original samples." : "Integration uses bounded, masked bilateral depth estimates. Invalid pixels remain invalid. Grid support, occlusion, raw disagreement and final vertex validation still use original unfiltered depth. The request records all denoising settings.",
                "Near-surface support is counted per distinct frame, not independent measurement; neighboring frames remain correlated.",
                "Far free-space samples contribute a clamped positive distance. Samples beyond the truncation band behind a visible surface are occluded, not evidence of hidden anatomy.",
                "All eight cube corners need passing view support and signed-distance agreement; unknown corners do not close holes.",
                "Every output vertex is independently reprojected through the same source frames after extraction. Triangles touching a vertex without the declared view support or raw signed-distance agreement are removed.",
                "Nearest-pixel depth and voxel interpolation can extend boundaries at subpixel/voxel scale. Vertices are interpolated estimates, not direct sensor observations.",
                "A capture-backed registration replay is not anatomical ground truth. Edge topology checks do not prove accuracy, self-intersection freedom or complete coverage.",
                "Partial experimental surface; not accepted for personal haircut fitting."])
    }
}
