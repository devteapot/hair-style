import Foundation
import AppKit
import SceneKit
import Metal

// Offline rendering only. Observed face and separate inferred scalp; no completed anatomy claim.
let args = CommandLine.arguments
 guard args.count == 3 else { fatalError("Usage: render_world_preview.swift SCALP_RESULT.json OUTPUT.png") }
let value = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[1]))) as! [String:Any]
guard value["method"] as? String == "editable_ellipsoid_scalp_candidate_v1",
      value["acceptedForHeadFitting"] as? Bool == false else { fatalError("Requires inferred scalp candidate") }
let observed=value["observed"] as! [String:Any], scalp=value["scalp"] as! [String:Any]
let scene = SCNScene(); scene.background.contents = NSColor(calibratedWhite:0.10,alpha:1)
var all: [SCNVector3] = []
for (index,patch) in [observed,scalp].enumerated() {
    let raw=patch["vertices"] as! [[String:Any]]
    let positions=raw.map { v -> SCNVector3 in
        let p=(index==0 ? v["position"] as! [String:Any] : v)
        return SCNVector3(p["x"] as! Double,p["y"] as! Double,p["z"] as! Double)
    }
    all += positions
    let indices = (patch["triangles"] as! [[Int]]).flatMap { $0 }.map(UInt32.init)
    let element = SCNGeometryElement(data:indices.withUnsafeBytes { Data($0) },primitiveType:.triangles,primitiveCount:indices.count/3,bytesPerIndex:4)
    var sources=[SCNGeometrySource(vertices:positions)]
    if index==0 {
        let normals=raw.map { v -> SCNVector3 in
            let n=v["normal"] as! [String:Any]
            return SCNVector3(n["x"] as! Double,n["y"] as! Double,n["z"] as! Double)
        }
        sources.append(SCNGeometrySource(normals:normals))
    }
    let geometry = SCNGeometry(sources:sources,elements:[element])
    let material = SCNMaterial(); material.diffuse.contents = index==0 ? NSColor(calibratedWhite:0.85,alpha:1) : NSColor(calibratedRed:0.95,green:0.57,blue:0.12,alpha:1)
    material.isDoubleSided = true; material.lightingModel = .lambert; geometry.materials = [material]
    scene.rootNode.addChildNode(SCNNode(geometry:geometry))
}
let minX = all.map(\.x).min()!, maxX = all.map(\.x).max()!
let minY = all.map(\.y).min()!, maxY = all.map(\.y).max()!
let minZ = all.map(\.z).min()!, maxZ = all.map(\.z).max()!
let center = SCNVector3((minX+maxX)/2,(minY+maxY)/2,(minZ+maxZ)/2)
let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera!.zNear = 0.001; camera.camera!.zFar = 5
camera.camera!.usesOrthographicProjection = true; camera.camera!.orthographicScale = max(maxY-minY,max(maxX-minX,maxZ-minZ))*0.65
scene.rootNode.addChildNode(camera)
let light = SCNNode(); light.light = SCNLight(); light.light!.type = .omni; light.light!.intensity = 700
scene.rootNode.addChildNode(light)
let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light!.type = .ambient; ambient.light!.intensity = 250; scene.rootNode.addChildNode(ambient)
let renderer = SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil); renderer.scene = scene; renderer.pointOfView = camera
let canvas = NSImage(size:NSSize(width:1400,height:1400)); canvas.lockFocus()
for i in 0..<4 {
    let angle = Double(i)*Double.pi/2
    camera.position = SCNVector3(center.x+sin(angle)*0.8,center.y+0.025,center.z+cos(angle)*0.8)
    camera.look(at:center); light.position = camera.position; SCNTransaction.flush()
    let image = renderer.snapshot(atTime:0,with:CGSize(width:700,height:700),antialiasingMode:.multisampling4X)
    image.draw(in:NSRect(x:(i%2)*700,y:(i/2)*700,width:700,height:700))
}
let label="GRAY: observed face    AMBER: inferred scalp — shape and boundary require review"
(label as NSString).draw(at:NSPoint(x:24,y:1360),withAttributes:[.foregroundColor:NSColor.white,.font:NSFont.systemFont(ofSize:22,weight:.semibold)])
canvas.unlockFocus()
let bitmap = NSBitmapImageRep(data:canvas.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:args[2]))
print("Rendered observed face (gray) and inferred scalp (amber)")
