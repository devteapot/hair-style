#!/usr/bin/env python3
"""Check imported node transforms using an asymmetric, non-personal SceneKit fixture."""
import json
from pathlib import Path
import subprocess
import tempfile

with tempfile.TemporaryDirectory(prefix='hair-mesh-export-') as folder:
    root=Path(folder);script=root/'fixture.swift';scene=root/'fixture.scn';output=root/'mesh.json'
    script.write_text('''import SceneKit
import Foundation
let scene=SCNScene()
let parent=SCNNode();parent.position=SCNVector3(0.1,0.2,0.3);parent.scale=SCNVector3(2,2,2)
let box=SCNNode(geometry:SCNBox(width:0.02,height:0.04,length:0.06,chamferRadius:0))
box.eulerAngles.z=Double.pi/2
parent.addChildNode(box);scene.rootNode.addChildNode(parent)
guard scene.write(to:URL(fileURLWithPath:CommandLine.arguments[1]),options:nil,delegate:nil,progressHandler:nil) else { fatalError("Fixture export failed") }
''')
    subprocess.run(['tools/dev.sh','swift',str(script),str(scene)],check=True)
    subprocess.run(['tools/dev.sh','swift','tools/export_model_mesh.swift',str(scene),str(output)],check=True)
    data=json.loads(output.read_text());p=data['positions']
    low=[min(v[i] for v in p) for i in range(3)];high=[max(v[i] for v in p) for i in range(3)]
    assert all(abs(a-b)<1e-6 for a,b in zip(low,[.06,.18,.24])),low
    assert all(abs(a-b)<1e-6 for a,b in zip(high,[.14,.22,.36])),high
    assert len(data['triangles'])==12
    assert all(0<=i<len(p) for t in data['triangles'] for i in t)
    assert not data['acceptedForHeadFitting']
print('Model mesh export check passed: hierarchy translation, rotation, scale and triangle indices.')
