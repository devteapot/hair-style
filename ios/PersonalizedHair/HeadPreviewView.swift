import SwiftUI
import SceneKit
import UniformTypeIdentifiers

struct HeadPreviewView: View {
    @State private var scene: SCNScene?
    @State private var importing = false
    @State private var clay = false
    @State private var reset = 0
    @State private var error: String?
    @State private var confirmingDelete = false
    private var savedURL: URL { FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("reconstructed-head.usdz") }

    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                Text("Reconstructed head preview").font(.title2.bold())
                Text("Experimental reconstruction. Hair and the bun may be included, and missing areas may have been filled. This model is not ready for haircut fitting.")
                    .font(.callout).foregroundStyle(Theme.ink.opacity(0.8)).accessibilityIdentifier("headPreviewNotice")
                if let scene {
                    Text("Saved locally").font(.caption).accessibilityIdentifier("headPreviewLoaded")
                    ReconstructedHeadScene(scene:scene,clay:clay,reset:reset)
                        .frame(height:380).clipShape(RoundedRectangle(cornerRadius:20))
                        .accessibilityLabel("Interactive reconstructed head. Drag to rotate and pinch to zoom.")
                        .accessibilityIdentifier("reconstructedHeadScene")
                    Toggle("Show geometry without photo texture",isOn:$clay).accessibilityIdentifier("headClayToggle")
                    Button("Reset view") { reset += 1 }.accessibilityIdentifier("resetHeadView")
                    Text("Drag to rotate; pinch to zoom. Turn off the photo texture to inspect the actual surface detail.")
                        .font(.footnote).foregroundStyle(Theme.ink.opacity(0.8))
                    ShareLink("Export preview",item:savedURL)
                    Button("Delete this preview",role:.destructive) { confirmingDelete = true }
                } else {
                    ContentUnavailableView("No reconstructed model",systemImage:"person.crop.square",description:Text("Import a USDZ preview created from your capture. Saved camera captures remain separate."))
                        .accessibilityIdentifier("headPreviewEmpty")
                }
                Button("Import reconstructed model") { importing = true }.accessibilityIdentifier("importHeadPreview")
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }.padding(24)
        }.background(Theme.paper).foregroundStyle(Theme.ink).navigationTitle("Head preview")
            .task { loadSaved() }
            .fileImporter(isPresented:$importing,allowedContentTypes:[.usdz]) { result in
                do {
                    let url = try result.get(), access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf:url,options:.mappedIfSafe)
                    guard data.count <= 25_000_000 else { throw PreviewError.invalid("Use a preview smaller than 25 MB.") }
                    // Validate the new asset before replacing the saved preview.
                    _ = try checkedScene(url)
                    try data.write(to:savedURL,options:[.atomic,.completeFileProtectionUnlessOpen])
                    var destination=savedURL;var values=URLResourceValues();values.isExcludedFromBackup=true
                    try destination.setResourceValues(values)
                    scene=try checkedScene(savedURL);error=nil;reset += 1
                } catch { self.error=error.localizedDescription }
            }
            .confirmationDialog("Delete the reconstructed preview? Your camera captures are kept.",isPresented:$confirmingDelete,titleVisibility:.visible) {
                Button("Delete preview",role:.destructive) {
                    do { try FileManager.default.removeItem(at:savedURL);scene=nil;error=nil }
                    catch { self.error=error.localizedDescription }
                }
            }
    }
    private func loadSaved() {
        guard FileManager.default.fileExists(atPath:savedURL.path) else { return }
        do {
            scene=try checkedScene(savedURL);error=nil
            try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUnlessOpen],ofItemAtPath:savedURL.path)
            var url=savedURL;var values=URLResourceValues();values.isExcludedFromBackup=true;try url.setResourceValues(values)
        } catch { self.error=error.localizedDescription }
    }
    private func checkedScene(_ url:URL) throws -> SCNScene {
        guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max) <= 25_000_000 else { throw PreviewError.invalid("Use a preview smaller than 25 MB.") }
        let scene=try SCNScene(url:url,options:nil)
        var count=0
        scene.rootNode.enumerateChildNodes { node,_ in count += node.geometry?.elements.reduce(0) { $0+$1.primitiveCount } ?? 0 }
        guard count>0,count<=500_000 else { throw PreviewError.invalid("The preview must contain geometry and at most 500,000 primitives.") }
        let (low,high)=scene.rootNode.boundingBox
        let extent=max(high.x-low.x,max(high.y-low.y,high.z-low.z))
        guard extent.isFinite,extent>0.001,extent<2 else { throw PreviewError.invalid("The preview has unsupported bounds. Check its scale before import.") }
        return scene
    }
    private enum PreviewError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case .invalid(let message)=self { return message };return nil }
    }
}

private struct ReconstructedHeadScene: UIViewRepresentable {
    let scene: SCNScene
    let clay: Bool
    let reset: Int
    final class Coordinator {
        var reset = -1
        var source: SCNScene?
        var materials: [(SCNGeometry,[SCNMaterial])] = []
        var camera=SCNNode()
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context:Context) -> SCNView {
        let view=SCNView();view.allowsCameraControl=true;view.autoenablesDefaultLighting=false;view.preferredFramesPerSecond=30
        view.backgroundColor=UIColor(white:0.12,alpha:1);return view
    }
    func updateUIView(_ view:SCNView,context:Context) {
        let c=context.coordinator
        if c.source !== scene {
            c.source=scene;c.materials=[]
            let shown=SCNScene();shown.rootNode.addChildNode(scene.rootNode.clone())
            shown.rootNode.enumerateChildNodes { node,_ in
                if let geometry=node.geometry {
                    let copy=geometry.copy() as! SCNGeometry;node.geometry=copy
                    c.materials.append((copy,copy.materials.map { $0.copy() as! SCNMaterial }))
                }
            }
            c.camera=SCNNode();c.camera.camera=SCNCamera();c.camera.camera!.zNear=0.001;c.camera.camera!.zFar=10;c.camera.camera!.fieldOfView=40
            shown.rootNode.addChildNode(c.camera)
            let ambient=SCNNode();ambient.light=SCNLight();ambient.light!.type = .ambient;ambient.light!.intensity=300;shown.rootNode.addChildNode(ambient)
            let light=SCNNode();light.light=SCNLight();light.light!.type = .omni;light.light!.intensity=500;c.camera.addChildNode(light)
            view.scene=shown;view.pointOfView=c.camera;c.reset = -1
        }
        for (geometry,originals) in c.materials {
            if clay {
                let material=SCNMaterial();material.diffuse.contents=UIColor(red:0.7,green:0.76,blue:0.75,alpha:1)
                material.lightingModel = .lambert;material.isDoubleSided=true;geometry.materials=[material]
            } else {
                geometry.materials=originals.map { original in
                    let material=original.copy() as! SCNMaterial;material.lightingModel = .constant;material.emission.contents=UIColor.black;return material
                }
            }
        }
        if c.reset != reset {
            let (lo,hi)=scene.rootNode.boundingBox
            let center=SCNVector3((lo.x+hi.x)/2,(lo.y+hi.y)/2,(lo.z+hi.z)/2)
            let span=max(hi.x-lo.x,max(hi.y-lo.y,hi.z-lo.z))
            c.camera.position=SCNVector3(center.x+span*1.5,center.y+span*0.2,center.z)
            c.camera.look(at:center);view.pointOfView=c.camera;view.defaultCameraController.target=center;c.reset=reset
        }
    }
}
