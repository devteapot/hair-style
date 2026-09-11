import Foundation
import SceneKit
import AppKit
import Metal

let args = CommandLine.arguments
guard args.count == 5 || (args.count == 6 && args[5] == "projective") || args.count == 7 else {
    fatalError("Usage: render_face_mask_comparison.swift SCALP_RESULT.json OLD_SURFACE.json NEW_SURFACE.json OUTPUT.png [projective | OLD_LABEL NEW_LABEL]")
}
func read(_ path: String) throws -> [String:Any] { try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath:path))) as! [String:Any] }
let canonical = try read(args[1])["observed"] as! [String:Any]
let matrix = (canonical["canonicalFromReference"] as! [String:Any])["rowMajor"] as! [Double]
let inputs = try [read(args[2]),read(args[3])]
let frames = inputs.map { $0["frames"] as! [[String:Any]] }
guard !frames[0].isEmpty, frames[0].count == frames[1].count,
      zip(frames[0],frames[1]).allSatisfy({ ($0["frameSHA256"] as? String) == ($1["frameSHA256"] as? String) &&
          (($0["referenceFromCamera"] as? [String:Any])?["rowMajor"] as? [Double]) == (($1["referenceFromCamera"] as? [String:Any])?["rowMajor"] as? [Double]) }),
      inputs.allSatisfy({ input in
          input["completeHead"] as? Bool == false && input["coordinateConvention"] as? String == "reference_optical_x_right_y_down_z_forward_meters" &&
          (input["includesInferredAnatomy"] as? Bool == false ||
           (["local_oriented_point_field_marching_tetrahedra_v1", "masked_projective_tsdf_marching_tetrahedra_v1", "masked_projective_tsdf_marching_tetrahedra_v2", "masked_denoised_projective_tsdf_v1"].contains(input["method"] as? String ?? "") && input["suitableForHaircutFitting"] as? Bool == false))
      }) else { fatalError("Comparison requires matching captured frames and fixed registration transforms") }
let projectiveComparison = args.count == 6 && args[5] == "projective"
let isRemesh = inputs[0]["method"] as? String == "local_oriented_point_field_marching_tetrahedra_v1"

func transformed(_ p:[String:Any], normal:Bool=false)->SCNVector3 {
    let x=p["x"] as! Double,y=p["y"] as! Double,z=p["z"] as! Double
    return SCNVector3(matrix[0]*x+matrix[1]*y+matrix[2]*z+(normal ? 0:matrix[3]),
                     matrix[4]*x+matrix[5]*y+matrix[6]*z+(normal ? 0:matrix[7]),
                     matrix[8]*x+matrix[9]*y+matrix[10]*z+(normal ? 0:matrix[11]))
}
var nodes:[SCNNode]=[], all:[SCNVector3]=[]
for input in inputs {
    let vertices=input["vertices"] as! [[String:Any]]
    let points=vertices.map{transformed($0["position"] as! [String:Any])}
    let normals=vertices.map{transformed($0["normal"] as! [String:Any],normal:true)}
    all += points
    let indices=(input["triangles"] as! [[Int]]).flatMap{$0}.map(UInt32.init)
    let element=SCNGeometryElement(data:indices.withUnsafeBytes{Data($0)},primitiveType:.triangles,primitiveCount:indices.count/3,bytesPerIndex:4)
    let geometry=SCNGeometry(sources:[SCNGeometrySource(vertices:points),SCNGeometrySource(normals:normals)],elements:[element])
    let material=SCNMaterial();material.diffuse.contents=NSColor(calibratedWhite:0.82,alpha:1);material.isDoubleSided=true;material.lightingModel = .lambert
    geometry.materials=[material];nodes.append(SCNNode(geometry:geometry))
}
let minX=all.map(\.x).min()!,maxX=all.map(\.x).max()!,minY=all.map(\.y).min()!,maxY=all.map(\.y).max()!,minZ=all.map(\.z).min()!,maxZ=all.map(\.z).max()!
let center=SCNVector3((minX+maxX)/2,(minY+maxY)/2,(minZ+maxZ)/2)
let scene=SCNScene();scene.background.contents=NSColor(calibratedWhite:0.12,alpha:1)
let camera=SCNNode();camera.camera=SCNCamera();camera.camera!.usesOrthographicProjection=true;camera.camera!.orthographicScale=max(maxY-minY,maxX-minX)*0.6
camera.camera!.zNear=0.001;camera.camera!.zFar=5;scene.rootNode.addChildNode(camera)
let light=SCNNode();light.light=SCNLight();light.light!.type = .omni;light.light!.intensity=700;scene.rootNode.addChildNode(light)
let ambient=SCNNode();ambient.light=SCNLight();ambient.light!.type = .ambient;ambient.light!.intensity=250;scene.rootNode.addChildNode(ambient)
let renderer=SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil);renderer.scene=scene;renderer.pointOfView=camera
let canvas=NSImage(size:NSSize(width:1400,height:1100));canvas.lockFocus()
NSColor(calibratedWhite:0.12,alpha:1).setFill();NSRect(x:0,y:0,width:1400,height:1100).fill()
for row in 0..<2 {
    scene.rootNode.addChildNode(nodes[row])
    for column in 0..<2 {
        let angle=Double(column)*Double.pi/2
        camera.position=SCNVector3(center.x+sin(angle)*0.8,center.y,center.z+cos(angle)*0.8)
        camera.look(at:center);light.position=camera.position;SCNTransaction.flush()
        let image=renderer.snapshot(atTime:0,with:CGSize(width:700,height:500),antialiasingMode:.multisampling4X)
        let y=(1-row)*550
        image.draw(in:NSRect(x:column*700,y:y,width:700,height:500))
        let name = args.count == 7 ? args[5+row] : (projectiveComparison ? (row==0 ? "Local tangent field" : "Projective depth fusion") : (row==0 ? "Landmark hull" : "Face segmentation"))
        let viewLabel = args.count == 7 ? (column==0 ? "camera view" : "quarter turn") : (column==0 ? "front" : "profile")
        let label="\(name)\(isRemesh && !projectiveComparison ? " field remesh" : "") · \(viewLabel)"
        (label as NSString).draw(at:NSPoint(x:column*700+20,y:y+510),withAttributes:[.foregroundColor:NSColor.white,.font:NSFont.systemFont(ofSize:22,weight:.semibold)])
    }
    nodes[row].removeFromParentNode()
}
canvas.unlockFocus()
let bitmap=NSBitmapImageRep(data:canvas.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:args[4]))
print("Rendered same-frame mask comparison with fixed scale, camera, transform and lighting")
