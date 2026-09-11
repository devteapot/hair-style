import Foundation

public enum ClearanceRegion: String, Codable, CaseIterable, Sendable {
    case face, anatomicalLeftEar = "anatomical_left_ear", anatomicalRightEar = "anatomical_right_ear"
}
public struct ClearanceSurface: Codable, Sendable {
    public var region: ClearanceRegion
    public var origin: ScalpSurfaceOrigin
    public var sourceSHA256: String
    public var vertices: [Point3D]
    public var triangles: [[Int]]
    public init(region: ClearanceRegion, origin: ScalpSurfaceOrigin, sourceSHA256: String, vertices: [Point3D], triangles: [[Int]]) {
        self.region=region; self.origin=origin; self.sourceSHA256=sourceSHA256; self.vertices=vertices; self.triangles=triangles
    }
}
public struct GuideClearanceInput: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var scalpSHA256: String
    public var clearanceMeters: Double
    public var surfaces: [ClearanceSurface]
    public init(schemaVersion: Int = 1, scalpSHA256: String, clearanceMeters: Double, surfaces: [ClearanceSurface]) {
        self.schemaVersion=schemaVersion; self.scalpSHA256=scalpSHA256; self.clearanceMeters=clearanceMeters; self.surfaces=surfaces
    }
}
public struct GuideClearanceViolation: Codable, Sendable {
    public var guideID: String
    public var segmentIndex: Int
    public var region: ClearanceRegion
    public var triangleIndex: Int
    public var distanceMeters: Double
    public var requiredDistanceMeters: Double
}
public struct GuideRootClearanceViolation: Codable, Sendable {
    public var guideID: String
    public var region: ClearanceRegion
    public var triangleIndex: Int
    public var distanceMeters: Double
    public var requiredDistanceMeters: Double
}
public struct GuideClearanceReport: Codable, Sendable {
    public var method: String = "guide_capsule_triangle_clearance_v1"
    public var haircutSHA256: String
    public var anatomySHA256: String
    public var surfaceChecksPassed: Bool
    public var violations: [GuideClearanceViolation]
    /// Nil in legacy reports. A colliding fixed root cannot be repaired by curve-only regeneration.
    public var rootViolations: [GuideRootClearanceViolation]? = nil
    public var missingRegions: [ClearanceRegion]
    public var synthetic: Bool
    public var triangleComparisons: Int
    public var publishableAsValidatedDesign: Bool = false
    public var unverifiedChecks: [String]
}

public struct RootClearancePreflight: Codable, Sendable {
    public var method = "proposed_root_clearance_preflight_v1"
    public var inputSHA256: String
    public var bindingsSHA256: String
    public var anatomySHA256: String
    public var materialRadiusMeters: Double
    public var rootCount: Int
    public var violations: [GuideRootClearanceViolation]
    public var missingRegions: [ClearanceRegion]
    public var suppliedSurfacesPassed: Bool
    public var requiresAttachmentReview: Bool
    public var physicalFitVerified = false
}

public enum GuideClearance {
    /// Reuses anatomy acceleration across a bounded candidate set. Every haircut
    /// still receives the complete canonical validation and segment/root checks.
    public static func checkBatch(input: HairDesignInput, haircuts: [HaircutRevision],
                                  anatomy: GuideClearanceInput) throws -> [GuideClearanceReport] {
        guard (1...256).contains(haircuts.count),
              haircuts.reduce(0, { $0 + $1.guides.count }) <= 10_000 else {
            throw CaptureError.invalid("Clearance batch exceeds candidate or guide budget.")
        }
        let evaluate = try preparedEvaluator(input: input, anatomy: anatomy)
        return try haircuts.map { try evaluate($0) }
    }

    /// Requires no generated curve or neural-model loading. Missing anatomy remains explicit.
    public static func preflightRoots(input: HairDesignInput, bindings: [ModelGuideMapping],
                                     materialRadiusMeters: Double, anatomy: GuideClearanceInput) throws -> RootClearancePreflight {
        try Task.checkCancellation()
        try HaircutValidator.validateInput(input)
        guard (1...10_000).contains(bindings.count), materialRadiusMeters.isFinite,
              (0.000001...0.005).contains(materialRadiusMeters),
              Set(bindings.map(\.guideID)).count == bindings.count, bindings.allSatisfy({ !$0.guideID.isEmpty }),
              bindings.allSatisfy({ b in input.brief.lengthLimits.contains { $0.region == b.region } }) else {
            throw CaptureError.invalid("Invalid proposed root identities, regions or material radius.")
        }
        let (trees, regions) = try prepare(anatomy: anatomy, scalpSHA256: input.brief.scalpSHA256)
        let required = materialRadiusMeters+anatomy.clearanceMeters
        var violations: [GuideRootClearanceViolation] = [], comparisons = 0
        for binding in bindings {
            try Task.checkCancellation()
            let root = try HaircutValidator.attachment(binding.binding, scalp: input.scalp).position
            let query = Box([root],padding: required)
            for tree in trees {
                var stack = [0], nearest: (Int,Double)?
                while let index = stack.popLast() {
                    let node = tree.nodes[index]
                    guard node.box.overlaps(query) else { continue }
                    if let left=node.left, let right=node.right { stack.append(left); stack.append(right) }
                    else {
                        for triangle in node.triangles {
                            comparisons += 1
                            guard comparisons <= 10_000_000 else { throw CaptureError.invalid("Root preflight exceeds its comparison budget.") }
                            let p = tree.surface.triangles[triangle].map { tree.surface.vertices[$0] }
                            let distance = pointTriangle(root,p[0],p[1],p[2])
                            if distance <= required, distance < (nearest?.1 ?? .infinity) { nearest = (triangle,distance) }
                        }
                    }
                }
                if let nearest {
                    violations.append(GuideRootClearanceViolation(guideID: binding.guideID,region: tree.surface.region,
                        triangleIndex: nearest.0,distanceMeters: nearest.1,requiredDistanceMeters: required))
                }
            }
        }
        return RootClearancePreflight(inputSHA256: try HairArtifactHash.digest(input), bindingsSHA256: try HairArtifactHash.digest(bindings),
            anatomySHA256: try HairArtifactHash.digest(anatomy),materialRadiusMeters: materialRadiusMeters,
            rootCount: bindings.count,violations: violations,missingRegions: ClearanceRegion.allCases.filter { !regions.contains($0) },
            suppliedSurfacesPassed: violations.isEmpty,requiresAttachmentReview: !violations.isEmpty)
    }

    public static func check(input: HairDesignInput, haircut: HaircutRevision, anatomy: GuideClearanceInput) throws -> GuideClearanceReport {
        try Task.checkCancellation()
        let validation = try HaircutValidator.validate(input: input, haircut: haircut)
        let (trees, regions) = try prepare(anatomy: anatomy, scalpSHA256: haircut.scalpSHA256)
        return try checkPrepared(input: input,haircut: haircut,anatomy: anatomy,validation: validation,trees: trees,regions: regions)
    }

    /// Internal reuse for bounded candidate search; each candidate still gets full
    /// canonical validation and its own exact segment/triangle comparison budget.
    static func preparedEvaluator(input: HairDesignInput, anatomy: GuideClearanceInput) throws -> (HaircutRevision) throws -> GuideClearanceReport {
        try HaircutValidator.validateInput(input)
        let (trees, regions) = try prepare(anatomy: anatomy, scalpSHA256: input.brief.scalpSHA256)
        return { haircut in
            let validation = try HaircutValidator.validate(input: input, haircut: haircut)
            return try checkPrepared(input: input, haircut: haircut, anatomy: anatomy,
                validation: validation, trees: trees, regions: regions)
        }
    }

    private static func prepare(anatomy: GuideClearanceInput, scalpSHA256: String) throws -> ([Tree],Set<ClearanceRegion>) {
        guard anatomy.schemaVersion == 1, anatomy.scalpSHA256 == scalpSHA256,
              anatomy.clearanceMeters.isFinite, (0...0.02).contains(anatomy.clearanceMeters),
              (1...3).contains(anatomy.surfaces.count) else { throw CaptureError.invalid("Invalid clearance anatomy, scalp revision or margin.") }
        var regions = Set<ClearanceRegion>()
        var trees: [Tree] = []
        for surface in anatomy.surfaces {
            guard regions.insert(surface.region).inserted, HairArtifactHash.valid(surface.sourceSHA256),
                  (3...100_000).contains(surface.vertices.count), (1...200_000).contains(surface.triangles.count),
                  surface.vertices.allSatisfy({ $0.finite && $0.length <= 1 }) else { throw CaptureError.invalid("Invalid or duplicate clearance surface.") }
            for t in surface.triangles {
                guard t.count == 3, Set(t).count == 3, t.allSatisfy({ surface.vertices.indices.contains($0) }),
                      (surface.vertices[t[1]]-surface.vertices[t[0]]).cross(surface.vertices[t[2]]-surface.vertices[t[0]]).length > 1e-10 else {
                    throw CaptureError.invalid("Invalid clearance triangle.")
                }
            }
            trees.append(Tree(surface))
        }
        return (trees,regions)
    }

    private static func checkPrepared(input: HairDesignInput, haircut: HaircutRevision, anatomy: GuideClearanceInput,
                                      validation: HairValidationReport, trees: [Tree], regions: Set<ClearanceRegion>) throws -> GuideClearanceReport {
        let radii = Dictionary(uniqueKeysWithValues: haircut.materials.map { ($0.id,$0.radiusMeters) })
        var violations: [GuideClearanceViolation] = [], comparisons = 0
        var rootViolations: [GuideRootClearanceViolation] = []
        for guide in haircut.guides {
            try Task.checkCancellation()
            let required = radii[guide.materialID]! + anatomy.clearanceMeters
            for segment in -1..<(guide.points.count-1) {
                let a = guide.points[max(0,segment)], b = guide.points[max(0,segment+1)]
                let query = Box([a,b], padding: required)
                for tree in trees {
                    var stack = [0]
                    var nearest: (Int,Double)?
                    while let index = stack.popLast() {
                        let node = tree.nodes[index]
                        guard node.box.overlaps(query) else { continue }
                        if let left = node.left, let right = node.right { stack.append(left); stack.append(right) }
                        else {
                            for triangleIndex in node.triangles {
                                comparisons += 1
                                guard comparisons <= 10_000_000 else { throw CaptureError.invalid("Clearance check exceeds the ten-million triangle-comparison budget.") }
                                let t = tree.surface.triangles[triangleIndex].map { tree.surface.vertices[$0] }
                                let distance = segment == -1 ? pointTriangle(a,t[0],t[1],t[2]) : segmentTriangleDistance(a,b,t[0],t[1],t[2])
                                if distance <= required, distance < (nearest?.1 ?? .infinity) { nearest = (triangleIndex,distance) }
                            }
                        }
                    }
                    if let hit = nearest {
                        guard violations.count+rootViolations.count < 10_000 else { throw CaptureError.invalid("Too many clearance violations; reject or repair this candidate.") }
                        if segment == -1 {
                            rootViolations.append(GuideRootClearanceViolation(guideID: guide.id, region: tree.surface.region,
                                triangleIndex: hit.0, distanceMeters: hit.1, requiredDistanceMeters: required))
                        } else {
                            violations.append(GuideClearanceViolation(guideID: guide.id, segmentIndex: segment, region: tree.surface.region,
                                triangleIndex: hit.0, distanceMeters: hit.1, requiredDistanceMeters: required))
                        }
                    }
                }
            }
        }
        return GuideClearanceReport(haircutSHA256: validation.haircutSHA256, anatomySHA256: try HairArtifactHash.digest(anatomy),
            surfaceChecksPassed: violations.isEmpty && rootViolations.isEmpty, violations: violations, rootViolations: rootViolations,
            missingRegions: ClearanceRegion.allCases.filter { !regions.contains($0) },
            synthetic: validation.synthetic || anatomy.surfaces.contains { $0.origin == .synthetic }, triangleComparisons: comparisons,
            unverifiedChecks: ["Whether guide segments lie wholly inside closed anatomy without crossing a surface",
                "Scalp clearance, root emergence and hairline constraints", "Clearance of interpolated strands between guides",
                "Completeness/anatomical accuracy of supplied face and ear meshes", "Physical styling behavior and regional continuity"])
    }

    /// Exact minimum for a segment and a nondegenerate triangle: intersection,
    /// endpoint-to-face distance, and segment-to-edge distances cover the cases.
    static func segmentTriangleDistance(_ a: Point3D, _ b: Point3D, _ p: Point3D, _ q: Point3D, _ r: Point3D) -> Double {
        let normal = (q-p).cross(r-p).unit
        let denominator = (b-a).dot(normal)
        if abs(denominator) > 1e-15 {
            let t = (p-a).dot(normal)/denominator
            if (0...1).contains(t), inside(a+(b-a)*t,p,q,r) { return 0 }
        }
        return min(pointTriangle(a,p,q,r),pointTriangle(b,p,q,r),
                   segmentDistance(a,b,p,q),segmentDistance(a,b,q,r),segmentDistance(a,b,r,p))
    }
    private static func inside(_ x: Point3D, _ p: Point3D, _ q: Point3D, _ r: Point3D) -> Bool {
        let u = q-p, v = r-p, w = x-p
        let uu = u.dot(u), uv = u.dot(v), vv = v.dot(v), wu = w.dot(u), wv = w.dot(v)
        let denominator = u.cross(v).dot(u.cross(v))
        let b = (vv*wu-uv*wv)/denominator, c = (uu*wv-uv*wu)/denominator
        return b >= -1e-10 && c >= -1e-10 && b+c <= 1+1e-10
    }
    private static func pointTriangle(_ x: Point3D, _ p: Point3D, _ q: Point3D, _ r: Point3D) -> Double {
        let normal = (q-p).cross(r-p).unit
        let distance = (x-p).dot(normal)
        if inside(x-normal*distance,p,q,r) { return abs(distance) }
        return min(segmentDistance(x,x,p,q),segmentDistance(x,x,q,r),segmentDistance(x,x,r,p))
    }
    private static func segmentDistance(_ p: Point3D, _ q: Point3D, _ a: Point3D, _ b: Point3D) -> Double {
        let d1 = q-p, d2 = b-a, r = p-a
        let aa = d1.dot(d1), ee = d2.dot(d2), f = d2.dot(r)
        func clamp(_ x: Double) -> Double { min(1,max(0,x)) }
        var s = 0.0, t = 0.0
        if aa <= 1e-20 && ee <= 1e-20 { return (p-a).length }
        if aa <= 1e-20 { t = clamp(f/ee) }
        else {
            let c = d1.dot(r)
            if ee <= 1e-20 { s = clamp(-c/aa) }
            else {
                let bb = d1.dot(d2), cross = d1.cross(d2), denominator = cross.dot(cross)
                if denominator > 1e-12*aa*ee { s = clamp((bb*f-c*ee)/denominator) }
                t = (bb*s+f)/ee
                if t < 0 { t = 0; s = clamp(-c/aa) }
                else if t > 1 { t = 1; s = clamp((bb-c)/aa) }
            }
        }
        return (p+d1*s-a-d2*t).length
    }
    private struct Box {
        var low: [Double]; var high: [Double]
        init(_ points: [Point3D], padding: Double = 0) {
            low = (0..<3).map { axis in points.map { $0.components[axis] }.min()! - padding }
            high = (0..<3).map { axis in points.map { $0.components[axis] }.max()! + padding }
        }
        func overlaps(_ b: Box) -> Bool { (0..<3).allSatisfy { low[$0] <= b.high[$0] && high[$0] >= b.low[$0] } }
    }
    private struct Node {
        var box: Box
        var left: Int?
        var right: Int?
        var triangles: [Int]
    }
    private struct Tree {
        let surface: ClearanceSurface
        var nodes: [Node] = []
        init(_ surface: ClearanceSurface) {
            self.surface = surface
            _ = build(Array(surface.triangles.indices))
        }
        mutating func build(_ ids: [Int]) -> Int {
            let box = Box(ids.flatMap { surface.triangles[$0].map { surface.vertices[$0] } })
            let index = nodes.count
            nodes.append(Node(box: box, triangles: []))
            if ids.count <= 8 { nodes[index].triangles = ids; return index }
            let axis = (0..<3).max { box.high[$0]-box.low[$0] < box.high[$1]-box.low[$1] }!
            let sorted = ids.sorted { a,b in
                let ca = surface.triangles[a].reduce(0.0) { $0+surface.vertices[$1].components[axis] }
                let cb = surface.triangles[b].reduce(0.0) { $0+surface.vertices[$1].components[axis] }
                return ca == cb ? a < b : ca < cb
            }
            let middle = sorted.count/2
            let left = build(Array(sorted[..<middle])), right = build(Array(sorted[middle...]))
            nodes[index].left = left; nodes[index].right = right
            return index
        }
    }
}
