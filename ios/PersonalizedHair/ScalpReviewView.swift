import SwiftUI
import SceneKit
import UniformTypeIdentifiers
import HairCore

struct ScalpReviewView: View {
    @State private var document:ScalpReviewDocument?
    @State private var result:ScalpCompletionResult?
    @State private var draft:ScalpEnvelope?
    @State private var importing=false
    @State private var confirmingDelete=false
    @State private var error:String?
    @State private var reset=0
    @State private var showScalp=true
    @State private var dirty=false
    @State private var busy=false
    private var savedURL:URL { FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("scalp-review.json") }

    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                Text("Review estimated scalp").font(.title2.bold())
                if busy { ProgressView("Checking scalp revision…") }
                Text("Gray is your recorded face. Amber is an estimated scalp, including hidden areas. Its shape and boundary need review before haircut fitting.")
                    .font(.callout).accessibilityIdentifier("scalpReviewNotice")
                if let result {
                    Text("Saved revision \(result.scalp.revision)").font(.caption.monospacedDigit()).accessibilityIdentifier("scalpRevision")
                    ScalpReviewScene(result:result,showScalp:showScalp,reset:reset)
                        .frame(height:330).clipShape(RoundedRectangle(cornerRadius:20))
                        .accessibilityLabel("Recorded face and estimated scalp. Drag to rotate and pinch to zoom.")
                        .accessibilityIdentifier("scalpReviewScene")
                    Toggle("Show estimated scalp",isOn:$showScalp).accessibilityIdentifier("showEstimatedScalp")
                    Button("Reset view") { reset+=1 }
                    Text("Adjust the estimate").font(.headline)
                    Text("Dimensions are assumptions, not measurements. Your recorded face stays fixed. Save to update the preview.")
                        .font(.footnote).foregroundStyle(Theme.ink.opacity(0.8))
                    if draft != nil {
                        control("Width",id:"scalpWidth",keyPath:\.radii.x,multiplier:2000,range:50...500)
                        control("Height",id:"scalpHeight",keyPath:\.radii.y,multiplier:2000,range:50...500)
                        control("Depth",id:"scalpDepth",keyPath:\.radii.z,multiplier:2000,range:50...500)
                        Text("Position relative to the face").font(.subheadline.bold())
                        Text("Positive values point toward your left, upward, and forward. Position changes move the entire estimate, including its boundary.")
                            .font(.footnote)
                        positionControl("Left / right", id:"scalpPositionX", axis:0)
                        positionControl("Up / down", id:"scalpPositionY", axis:1)
                        positionControl("Forward / back", id:"scalpPositionZ", axis:2)
                        control("Front boundary height",id:"scalpFrontBoundary",keyPath:\.frontBoundaryY,multiplier:1000,range:-200...200)
                        control("Side boundary height",id:"scalpSideBoundary",keyPath:\.sideBoundaryY,multiplier:1000,range:-200...200)
                        control("Back boundary height",id:"scalpBackBoundary",keyPath:\.backBoundaryY,multiplier:1000,range:-200...200)
                    }
                    Button("Save adjustment") { saveDraft() }.buttonStyle(.borderedProminent)
                        .disabled(!dirty).accessibilityIdentifier("saveScalpAdjustment")
                    if dirty {
                        Text("Unsaved adjustments. The preview shows the saved revision.").font(.footnote)
                        Button("Discard adjustments") { draft=result.request.envelope;dirty=false;error=nil }
                    }
                    ShareLink("Export scalp review",item:savedURL)
                    Button("Delete scalp review",role:.destructive) { confirmingDelete=true }
                } else {
                    ContentUnavailableView("No scalp estimate",systemImage:"person.crop.circle",
                        description:Text("Import a scalp-review document prepared from a recorded face patch."))
                        .accessibilityIdentifier("scalpReviewEmpty")
                }
                Button("Import scalp review") { importing=true }.accessibilityIdentifier("importScalpReview")
                if let error { Text(error).foregroundStyle(.red).font(.footnote).accessibilityIdentifier("scalpReviewError") }
            }.padding(24).disabled(busy)
        }.background(Theme.paper).foregroundStyle(Theme.ink).navigationTitle("Scalp review")
            .task { load() }
            .fileImporter(isPresented:$importing,allowedContentTypes:[.json]) { response in
                do {
                    let url=try response.get(),access=url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let imported=try read(url);validateAndDisplay(imported)
                } catch { self.error=error.localizedDescription }
            }
            .confirmationDialog("Delete this scalp review and its saved revisions? Camera captures are kept.",isPresented:$confirmingDelete,titleVisibility:.visible) {
                Button("Delete review",role:.destructive) {
                    do { try FileManager.default.removeItem(at:savedURL);document=nil;result=nil;draft=nil;dirty=false;error=nil }
                    catch { self.error=error.localizedDescription }
                }
            }
    }
    private func control(_ title:String,id:String,keyPath:WritableKeyPath<ScalpEnvelope,Double>,multiplier:Double,range:ClosedRange<Double>)->some View {
        let value=(draft?[keyPath:keyPath] ?? 0)*multiplier
        return Stepper(value:Binding(get:{ (draft?[keyPath:keyPath] ?? 0)*multiplier },set:{ value in
            draft?[keyPath:keyPath]=value/multiplier;dirty=true
        }),in:range,step:2) {
            Text("\(title): \(value,format:.number.precision(.fractionLength(0))) mm")
        }.accessibilityIdentifier(id)
    }
    private func positionControl(_ title:String,id:String,axis:Int)->some View {
        let center=draft?.center ?? Point3D(x:0,y:0,z:0)
        let value=[center.x,center.y,center.z][axis]*1000
        return Stepper(value:Binding(get:{
            guard let center=draft?.center else { return 0 }
            return [center.x,center.y,center.z][axis]*1000
        },set:{ newValue in
            guard let envelope=draft else { return }
            let old=[envelope.center.x,envelope.center.y,envelope.center.z][axis]
            let delta=newValue/1000-old
            do {
                draft=try envelope.translated(by:Point3D(x:axis==0 ? delta:0,y:axis==1 ? delta:0,z:axis==2 ? delta:0))
                dirty=true;error=nil
            } catch { self.error=error.localizedDescription }
        }),in:-250...250,step:1) {
            Text("\(title): \(value,format:.number.precision(.fractionLength(0))) mm")
        }.accessibilityIdentifier(id)
    }
    private func read(_ url:URL) throws -> ScalpReviewDocument {
        guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max)<=25_000_000 else { throw CaptureError.invalid("Use a scalp-review document smaller than 25 MB.") }
        return try ManifestCoding.decoder().decode(ScalpReviewDocument.self,from:Data(contentsOf:url))
    }
    private func persist(_ value:ScalpReviewDocument) throws {
        let data=try ManifestCoding.encoder().encode(value)
        guard data.count<=25_000_000 else { throw CaptureError.invalid("The scalp-review document exceeds 25 MB.") }
        try data.write(to:savedURL,options:[.atomic,.completeFileProtectionUnlessOpen])
        var url=savedURL;var attributes=URLResourceValues();attributes.isExcludedFromBackup=true;try url.setResourceValues(attributes)
    }
    private func display(_ value:ScalpReviewDocument,_ checked:ScalpCompletionResult) {
        document=value;result=checked;draft=checked.request.envelope;dirty=false;error=nil;reset+=1
    }
    private func load() {
        guard FileManager.default.fileExists(atPath:savedURL.path) else { return }
        do { let value=try read(savedURL);validateAndDisplay(value) }
        catch { self.error=error.localizedDescription }
    }
    private func validateAndDisplay(_ value:ScalpReviewDocument) {
        busy=true;error=nil
        Task {
            defer { busy=false }
            do {
                let checked=try await Task.detached(priority:.userInitiated) { try value.latestResult() }.value
                try persist(value);display(value,checked)
            } catch { self.error=error.localizedDescription }
        }
    }
    private func saveDraft() {
        guard let document,var envelope=draft,!busy else { return }
        envelope.origin = .userSupplied;envelope.method="User-adjusted scalp envelope in native review; hidden anatomy remains inferred."
        let edited=envelope
        busy=true;error=nil
        Task {
            defer { busy=false }
            do {
                let (changed,checked)=try await Task.detached(priority:.userInitiated) {
                    let changed=try document.appending(envelope:edited)
                    return (changed,try changed.latestResult())
                }.value
                try persist(changed);display(changed,checked)
            } catch { self.error=error.localizedDescription }
        }
    }

}

private struct ScalpReviewScene:UIViewRepresentable {
    let result:ScalpCompletionResult
    let showScalp:Bool
    let reset:Int
    final class Coordinator { var hash="";var reset = -1;var scalp=SCNNode();var camera=SCNNode() }
    func makeCoordinator()->Coordinator { Coordinator() }
    func makeUIView(context:Context)->SCNView {
        let view=SCNView();view.allowsCameraControl=true;view.autoenablesDefaultLighting=true
        view.backgroundColor=UIColor(white:0.1,alpha:1);view.preferredFramesPerSecond=30;return view
    }
    func updateUIView(_ view:SCNView,context:Context) {
        let c=context.coordinator
        if c.hash != result.requestSHA256 {
            c.hash=result.requestSHA256
            let scene=SCNScene()
            func node(points:[Point3D],triangles:[[Int]],color:UIColor)->SCNNode {
                let positions=points.map { SCNVector3($0.x,$0.y,$0.z) }
                let indices=triangles.flatMap { $0 }.map(UInt32.init)
                let element=SCNGeometryElement(data:indices.withUnsafeBytes { Data($0) },primitiveType:.triangles,primitiveCount:triangles.count,bytesPerIndex:4)
                let geometry=SCNGeometry(sources:[SCNGeometrySource(vertices:positions)],elements:[element])
                let material=SCNMaterial();material.diffuse.contents=color;material.lightingModel = .lambert;material.isDoubleSided=true
                geometry.materials=[material];return SCNNode(geometry:geometry)
            }
            scene.rootNode.addChildNode(node(points:result.observed.vertices.map(\.position),triangles:result.observed.triangles,color:UIColor(white:0.85,alpha:1)))
            c.scalp=node(points:result.scalp.vertices,triangles:result.scalp.triangles,color:UIColor(red:0.95,green:0.57,blue:0.12,alpha:1))
            scene.rootNode.addChildNode(c.scalp)
            c.camera=SCNNode();c.camera.camera=SCNCamera();c.camera.camera!.zNear=0.001;c.camera.camera!.zFar=5;c.camera.camera!.fieldOfView=40
            scene.rootNode.addChildNode(c.camera);view.scene=scene;view.pointOfView=c.camera;c.reset = -1
        }
        c.scalp.isHidden = !showScalp
        if c.reset != reset {
            c.reset=reset;c.camera.position=SCNVector3(0,0.03,0.55);c.camera.look(at:SCNVector3(0,0.03,-0.03))
            view.pointOfView=c.camera;view.defaultCameraController.target=SCNVector3(0,0.03,-0.03)
        }
    }
}
