import Foundation
import AppKit
import SceneKit
import Metal

// Diagnostic offline render of the actual compiled canonical revisions.
let args = CommandLine.arguments
guard args.count == 5 || args.count == 7 else { fatalError("Usage: render_model_mapping.swift SCALP_RESULT.json BEFORE_MESH.json AFTER_MESH.json OUTPUT.png [BEFORE_LABEL AFTER_LABEL]") }
func load(_ path: String) throws -> [String:Any] {
    try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath:path))) as! [String:Any]
}
func vector(_ p: [String:Any]) -> SCNVector3 {
    SCNVector3((p["x"] as! NSNumber).doubleValue,(p["y"] as! NSNumber).doubleValue,(p["z"] as! NSNumber).doubleValue)
}
func meshNode(_ vertices: [SCNVector3], _ normals: [SCNVector3]?, _ indices: [UInt32], _ color: NSColor) -> SCNNode {
    var sources = [SCNGeometrySource(vertices:vertices)]
    if let normals { sources.append(SCNGeometrySource(normals:normals)) }
    let element = SCNGeometryElement(data:indices.withUnsafeBytes { Data($0) },primitiveType:.triangles,primitiveCount:indices.count/3,bytesPerIndex:4)
    let geometry = SCNGeometry(sources:sources,elements:[element])
    let material = SCNMaterial();material.diffuse.contents=color;material.isDoubleSided=true;material.lightingModel = .lambert
    geometry.materials=[material]
    return SCNNode(geometry:geometry)
}
let result = try load(args[1]), before = try load(args[2]), after = try load(args[3])
guard before["scalpSHA256"] as! String == after["scalpSHA256"] as! String,
      (args.count == 7 || before["haircutID"] as! String == after["haircutID"] as! String),
      before["haircutRevision"] as! Int == 1, after["haircutRevision"] as! Int == (args.count == 7 ? 1 : 2) else { fatalError("Expected matching initial/edited revisions or explicitly labeled initial-candidate comparison") }
let face = result["observed"] as! [String:Any], scalp = result["scalp"] as! [String:Any]
let faceRaw = face["vertices"] as! [[String:Any]]
let faceVertices = faceRaw.map { vector($0["position"] as! [String:Any]) }
let scalpVertices = (scalp["vertices"] as! [[String:Any]]).map(vector)
let all = faceVertices + scalpVertices
let minimum = SCNVector3(all.map(\.x).min()!,all.map(\.y).min()!,all.map(\.z).min()!)
let maximum = SCNVector3(all.map(\.x).max()!,all.map(\.y).max()!,all.map(\.z).max()!)
let center = SCNVector3((minimum.x+maximum.x)/2,(minimum.y+maximum.y)/2,(minimum.z+maximum.z)/2)
let canvas = NSImage(size:NSSize(width:1800,height:1300));canvas.lockFocus()
NSColor(calibratedWhite:0.95,alpha:1).setFill();NSRect(x:0,y:0,width:1800,height:1300).fill()
let titleStyle: [NSAttributedString.Key:Any] = [.foregroundColor:NSColor.black,.font:NSFont.systemFont(ofSize:22,weight:.semibold)]
for (row,hair) in [before,after].enumerated() {
    let scene = SCNScene();scene.background.contents=NSColor(calibratedWhite:0.95,alpha:1)
    scene.rootNode.addChildNode(meshNode(faceVertices,faceRaw.map { vector($0["normal"] as! [String:Any]) },(face["triangles"] as! [[Int]]).flatMap{$0}.map(UInt32.init),NSColor(calibratedWhite:0.75,alpha:1)))
    scene.rootNode.addChildNode(meshNode(scalpVertices,nil,(scalp["triangles"] as! [[Int]]).flatMap{$0}.map(UInt32.init),NSColor(calibratedRed:0.86,green:0.64,blue:0.30,alpha:1)))
    let hairVertices = (hair["vertices"] as! [[String:Any]]).map(vector)
    let hairNormals = (hair["normals"] as! [[String:Any]]).map(vector)
    for batch in hair["batches"] as! [[String:Any]] {
        let color = batch["region"] as! String == "fringe" ? NSColor(calibratedRed:0.05,green:0.38,blue:0.30,alpha:1) : NSColor(calibratedRed:0.18,green:0.11,blue:0.075,alpha:1)
        scene.rootNode.addChildNode(meshNode(hairVertices,hairNormals,(batch["indices"] as! [Int]).map(UInt32.init),color))
    }
    let camera=SCNNode();camera.camera=SCNCamera();camera.camera!.zNear=0.001;camera.camera!.zFar=5
    camera.camera!.usesOrthographicProjection=true;camera.camera!.orthographicScale=0.19
    scene.rootNode.addChildNode(camera)
    let light=SCNNode();light.light=SCNLight();light.light!.type = .omni;light.light!.intensity=850;scene.rootNode.addChildNode(light)
    let ambient=SCNNode();ambient.light=SCNLight();ambient.light!.type = .ambient;ambient.light!.intensity=300;scene.rootNode.addChildNode(ambient)
    let renderer=SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil);renderer.scene=scene;renderer.pointOfView=camera
    for column in 0..<3 {
        let angle=Double(column)*Double.pi/2
        camera.position=SCNVector3(center.x+sin(angle)*0.8,center.y+0.025,center.z+cos(angle)*0.8)
        camera.look(at:center);light.position=camera.position;SCNTransaction.flush()
        let image=renderer.snapshot(atTime:0,with:CGSize(width:600,height:560),antialiasingMode:.multisampling4X)
        image.draw(in:NSRect(x:column*600,y:(1-row)*600+50,width:600,height:560))
    }
    let title = args.count == 7 ? args[5+row] : (row==0 ? "Revision 1 · Imported model guides on inferred personal scalp" : "Revision 2 · Fringe shortened to 30 mm; other guides unchanged")
    (title as NSString).draw(at:NSPoint(x:24,y:(1-row)*600+618),withAttributes:titleStyle)
}
("Gray: observed face · Amber: inferred scalp · Green: fringe · Guide radii enlarged 8× · Unreviewed fit" as NSString)
    .draw(at:NSPoint(x:24,y:15),withAttributes:[.foregroundColor:NSColor.darkGray,.font:NSFont.systemFont(ofSize:19)])
canvas.unlockFocus()
let bitmap=NSBitmapImageRep(data:canvas.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:args[4]))
print("Rendered actual compiled revisions with face/scalp occlusion.")
