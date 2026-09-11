import Foundation
import SceneKit
import CryptoKit

let args=CommandLine.arguments
guard args.count==3 else { fatalError("Usage: export_model_mesh.swift MODEL.usdz OUTPUT.json") }
let source=URL(fileURLWithPath:args[1]),data=try Data(contentsOf:source)
let scene=try SCNScene(url:source,options:nil)
var positions:[[Double]]=[],triangles:[[Int]]=[]
var failure:String?
scene.rootNode.enumerateChildNodes { node,_ in
    guard let geometry=node.geometry else { return }
    guard let vertices=geometry.sources(for:.vertex).first,vertices.usesFloatComponents,vertices.componentsPerVector==3,
          [4,8].contains(vertices.bytesPerComponent) else { failure="Unsupported vertex encoding";return }
    let base=positions.count
    for i in 0..<vertices.vectorCount {
        var values:[Double]=[]
        for axis in 0..<3 {
            let offset=vertices.dataOffset+i*vertices.dataStride+axis*vertices.bytesPerComponent
            guard offset>=0,offset+vertices.bytesPerComponent<=vertices.data.count else { failure="Vertex offset out of bounds";return }
            values.append(vertices.data.withUnsafeBytes { bytes in vertices.bytesPerComponent==4 ? Double(bytes.loadUnaligned(fromByteOffset:offset,as:Float.self)) : bytes.loadUnaligned(fromByteOffset:offset,as:Double.self) })
        }
        let p=node.convertPosition(SCNVector3(values[0],values[1],values[2]),to:scene.rootNode)
        guard [p.x,p.y,p.z].allSatisfy(\.isFinite) else { failure="Nonfinite transformed vertex";return }
        positions.append([p.x,p.y,p.z])
    }
    for element in geometry.elements {
        guard element.primitiveType == .triangles,[1,2,4].contains(element.bytesPerIndex),element.primitiveCount*3*element.bytesPerIndex<=element.data.count else { failure="Unsupported triangle encoding";return }
        var indices:[Int]=[]
        for i in 0..<(element.primitiveCount*3) {
            let index=element.data.withUnsafeBytes { bytes -> Int in
                let offset=i*element.bytesPerIndex
                switch element.bytesPerIndex {
                case 1:return Int(bytes.loadUnaligned(fromByteOffset:offset,as:UInt8.self))
                case 2:return Int(bytes.loadUnaligned(fromByteOffset:offset,as:UInt16.self))
                default:return Int(bytes.loadUnaligned(fromByteOffset:offset,as:UInt32.self))
                }
            }
            guard index<vertices.vectorCount else { failure="Triangle index out of bounds";return }
            indices.append(base+index)
        }
        for i in stride(from:0,to:indices.count,by:3) { triangles.append(Array(indices[i..<(i+3)])) }
    }
}
if let failure { fatalError(failure) }
guard !positions.isEmpty,!triangles.isEmpty else { fatalError("Empty mesh") }
let result:[String:Any] = ["schemaVersion":1,"method":"scenekit_usdz_mesh_export_v1","modelSHA256":SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined(),"positions":positions,"triangles":triangles,"acceptedForHeadFitting":false,"notes":["Coordinates include imported node transforms. Model units and measured/inferred provenance remain unvalidated."]]
try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]).write(to:URL(fileURLWithPath:args[2]),options:.atomic)
print("Exported \(positions.count) vertices and \(triangles.count) triangles")
