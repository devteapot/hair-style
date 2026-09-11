import Foundation

/// Explicit seed in native depth pixel indexing. No automatic largest-component
/// assumption: a caller must identify the intended observed region.
public struct SurfaceComponentSelection: Codable, Sendable {
    public var seedDepthPixelIndex: Int
    public var maximumRemovedFraction: Double
    public init(seedDepthPixelIndex: Int, maximumRemovedFraction: Double = 0.05) {
        self.seedDepthPixelIndex = seedDepthPixelIndex
        self.maximumRemovedFraction = maximumRemovedFraction
    }
}

public struct SurfaceComponentReport: Codable, Sendable {
    public var method = "seed_connected_triangle_component_v1"
    public var seedDepthPixelIndex: Int
    public var componentVertexCounts: [Int]
    public var originalSampleCount: Int
    public var retainedSampleCount: Int
    public var excludedDepthPixelIndices: [Int]
    public var maximumRemovedFraction: Double
    public var notes: [String]
}

enum SurfaceConnectedComponent {
    /// Triangles use native depth pixel IDs, before any multi-view fusion.
    static func select(triangles: [[Int]], selection: SurfaceComponentSelection) throws -> SurfaceComponentReport {
        guard !triangles.isEmpty, triangles.count <= 2_000_000,
              (0...0.1).contains(selection.maximumRemovedFraction), selection.seedDepthPixelIndex >= 0 else {
            throw CaptureError.invalid("Component cleanup requires a valid seed and a removal budget of at most 10 percent.")
        }
        var parent: [Int:Int] = [:], rank: [Int:Int] = [:]
        func find(_ id: Int) -> Int {
            var root = id
            while parent[root]! != root { root = parent[root]! }
            var current = id
            while parent[current]! != current { let next = parent[current]!; parent[current] = root; current = next }
            return root
        }
        func join(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra == rb { return }
            let ar = rank[ra,default:0], br = rank[rb,default:0]
            if ar < br { parent[ra] = rb }
            else { parent[rb] = ra; if ar == br { rank[ra] = ar+1 } }
        }
        for t in triangles {
            guard t.count == 3, Set(t).count == 3, t.allSatisfy({ $0 >= 0 && $0 < 1_000_000 }) else {
                throw CaptureError.invalid("Invalid native depth triangle for component cleanup.")
            }
            for id in t where parent[id] == nil { parent[id] = id }
            join(t[0],t[1]); join(t[0],t[2])
        }
        guard parent[selection.seedDepthPixelIndex] != nil else {
            throw CaptureError.invalid("The component seed has no retained depth triangle. Select a visible surface sample.")
        }
        let seedRoot = find(selection.seedDepthPixelIndex)
        var counts: [Int:Int] = [:], excluded: [Int] = []
        for id in Array(parent.keys).sorted() {
            let root = find(id); counts[root,default:0] += 1
            if root != seedRoot { excluded.append(id) }
        }
        guard Double(excluded.count)/Double(parent.count) <= selection.maximumRemovedFraction else {
            throw CaptureError.invalid("Component cleanup would remove more than its sample budget. Check the seed, mask and capture continuity instead of discarding a large region.")
        }
        return SurfaceComponentReport(seedDepthPixelIndex:selection.seedDepthPixelIndex,
            componentVertexCounts:counts.values.sorted(by:>),originalSampleCount:parent.count,
            retainedSampleCount:parent.count-excluded.count,excludedDepthPixelIndices:excluded,
            maximumRemovedFraction:selection.maximumRemovedFraction,
            notes:["Only the triangle-connected component containing the explicit seed is retained; retained positions and normals are unchanged.",
                   "Disconnected geometry may be valid anatomy. Exclusion is a processing choice, not semantic skin/background classification.",
                   "Large removals fail the request; missing regions are not filled. Raw capture and supplied mask remain intact."])
    }
}
