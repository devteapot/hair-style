import Foundation
import AppKit
import SceneKit
import Metal

// Offline rendering only. World-positioned patches are not a registered head.
let args = CommandLine.arguments
 guard args.count == 3 else { fatalError("Usage: render_world_preview.swift WORLD_PREVIEW.json OUTPUT.png") }
let value = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[1]))) as! [String:Any]
guard value["method"] as? String == "unmerged_world_depth_patch_preview_v1",
      value["acceptedForFusion"] as? Bool == false else { fatalError("Requires diagnostic world patch preview") }
let patches = value["patches"] as! [[String:Any]]
let scene = SCNScene(); scene.background.contents = NSColor(calibratedWhite:0.10,alpha:1)
var all: [SCNVector3] = []
for (index,patch) in patches.enumerated() {
    func vectors(_ key:String) -> [SCNVector3] {
        (patch[key] as! [[Double]]).map { SCNVector3($0[0],$0[1],$0[2]) }
    }
    let positions = vectors("positions"); all += positions
    let indices = (patch["triangles"] as! [[Int]]).flatMap { $0 }.map(UInt32.init)
    let element = SCNGeometryElement(data:indices.withUnsafeBytes { Data($0) },primitiveType:.triangles,primitiveCount:indices.count/3,bytesPerIndex:4)
    let geometry = SCNGeometry(sources:[SCNGeometrySource(vertices:positions),SCNGeometrySource(normals:vectors("normals"))],elements:[element])
    let material = SCNMaterial(); material.diffuse.contents = NSColor(calibratedHue:Double(index)/Double(patches.count),saturation:0.4,brightness:0.8,alpha:1)
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
    camera.position = SCNVector3(center.x+sin(angle)*0.8,center.y+0.12,center.z+cos(angle)*0.8)
    camera.look(at:center); light.position = camera.position; SCNTransaction.flush()
    let image = renderer.snapshot(atTime:0,with:CGSize(width:700,height:700),antialiasingMode:.multisampling4X)
    image.draw(in:NSRect(x:(i%2)*700,y:(i/2)*700,width:700,height:700))
}
canvas.unlockFocus()
let bitmap = NSBitmapImageRep(data:canvas.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:args[2]))
print("Rendered four diagnostic views; colors identify source frames")
