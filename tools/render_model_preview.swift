import Foundation
import AppKit
import SceneKit
import Metal

let args = CommandLine.arguments
 guard (3...4).contains(args.count) else { fatalError("Usage: render_model_preview.swift MODEL.usdz OUTPUT.png [clay]") }
let scene = try SCNScene(url:URL(fileURLWithPath:args[1]),options:nil)
let root = scene.rootNode
var positions:[SCNVector3]=[], vertices=0, primitives=0
root.enumerateChildNodes { node,_ in
    guard let geometry=node.geometry else { return }
    if args.count == 4 && args[3] == "clay" {
        let material=SCNMaterial();material.diffuse.contents=NSColor(calibratedRed:0.7,green:0.76,blue:0.75,alpha:1)
        material.lightingModel = .lambert;material.isDoubleSided=true;geometry.materials=[material]
    } else {
        for material in geometry.materials { material.lightingModel = .constant;material.emission.contents=NSColor.black }
    }
    vertices += geometry.sources(for:.vertex).reduce(0) { $0+$1.vectorCount }
    primitives += geometry.elements.reduce(0) { $0+$1.primitiveCount }
    let (lo,hi)=geometry.boundingBox
    for x in [lo.x,hi.x] { for y in [lo.y,hi.y] { for z in [lo.z,hi.z] {
        positions.append(node.convertPosition(SCNVector3(x,y,z),to:root))
    } } }
}
guard !positions.isEmpty else { fatalError("No visible model geometry") }
let lo = SCNVector3(positions.map(\.x).min()!,positions.map(\.y).min()!,positions.map(\.z).min()!)
let hi = SCNVector3(positions.map(\.x).max()!,positions.map(\.y).max()!,positions.map(\.z).max()!)
let center = SCNVector3((lo.x+hi.x)/2,(lo.y+hi.y)/2,(lo.z+hi.z)/2)
let span = max(hi.x-lo.x,max(hi.y-lo.y,hi.z-lo.z))
let camera = SCNNode();camera.camera=SCNCamera();camera.camera!.zNear=0.0001;camera.camera!.zFar=max(10,span*10)
camera.camera!.usesOrthographicProjection=true;camera.camera!.orthographicScale=span*0.65
root.addChildNode(camera)
let light=SCNNode();light.light=SCNLight();light.light!.type = .omni;light.light!.intensity=650;root.addChildNode(light)
let ambient=SCNNode();ambient.light=SCNLight();ambient.light!.type = .ambient;ambient.light!.intensity=350;root.addChildNode(ambient)
scene.background.contents=NSColor(calibratedWhite:0.12,alpha:1)
let renderer=SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil);renderer.scene=scene;renderer.pointOfView=camera
let canvas=NSImage(size:NSSize(width:1400,height:1400));canvas.lockFocus()
for i in 0..<4 {
    let angle=Double(i)*Double.pi/2
    camera.position=SCNVector3(center.x+sin(angle)*span*3,center.y+span*0.2,center.z+cos(angle)*span*3)
    camera.look(at:center);light.position=camera.position;SCNTransaction.flush()
    renderer.snapshot(atTime:0,with:CGSize(width:700,height:700),antialiasingMode:.multisampling4X).draw(in:NSRect(x:(i%2)*700,y:(i/2)*700,width:700,height:700))
}
canvas.unlockFocus()
let bitmap=NSBitmapImageRep(data:canvas.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:args[2]))
let report:[String:Any] = ["vertices":vertices,"primitives":primitives,"lowerBound":[lo.x,lo.y,lo.z],"upperBound":[hi.x,hi.y,hi.z],"extent":[hi.x-lo.x,hi.y-lo.y,hi.z-lo.z],"units":"SceneKit imported coordinates; metric scale not independently validated"]
print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
