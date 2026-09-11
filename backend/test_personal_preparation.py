import base64
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import uuid
from unittest.mock import patch
from backend.artifact_store import ArtifactStore
from backend.compile_worker import run_one
from backend.job_store import JobStore


class PersonalPreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.root = Path(self.temp.name)
        self.cli = Path('.build/debug/capture-inspect').resolve()
        self.fixture = self.root/'fixture'
        subprocess.run([self.cli, 'hair-fixture', self.fixture], check=True, capture_output=True)
        self.input = json.loads((self.fixture/'input.json').read_bytes())
        hair = json.loads((self.fixture/'haircut.json').read_bytes())
        self.root_y = hair['guides'][0]['points'][0]['y']
        zero = dict(x=0, y=0, z=0)
        self.mapping = dict(schemaVersion=1, id=str(uuid.uuid4()), sourceArtifactSHA256='a'*64,
            scalpSHA256=hair['scalpSHA256'], sourceCenter=zero, targetCenterMeters=zero,
            metersPerSourceUnit=dict(x=1,y=1,z=1), maximumRootCorrectionMeters=.03,
            mappings=[dict(guideID=g['id'], region=g['region'], binding=g['root']) for g in hair['guides']],
            method='Synthetic attachment preparation fixture; no model correspondence proven')
        self.anatomy = dict(schemaVersion=1, scalpSHA256=hair['scalpSHA256'], clearanceMeters=.001,
            surfaces=[dict(region='face', origin='observed', sourceSHA256='b'*64,
                vertices=[dict(x=-.3,y=-.3,z=-.3),dict(x=.3,y=-.3,z=-.3),dict(x=0,y=-.3,z=.3)],triangles=[[0,1,2]])])
        brief = dict(schemaVersion=1,id=str(uuid.uuid4()),mode='autonomous',seed=self.input['brief']['seed'],lengthRanges=[])
        (self.fixture/'request.json').write_text(json.dumps(brief))
        subprocess.run([self.cli,'brief-prepare',self.fixture/'input.json',self.fixture/'request.json',
                        self.fixture/'prepared.json'], check=True, capture_output=True)
        self.store=JobStore(self.root/'jobs.sqlite');self.session=self.store.create_session('owner')
        self.artifacts=self.root/'artifacts';self.files=ArtifactStore(self.store,self.artifacts)
        self.request=dict(schemaVersion=1,kind='prepare_personal_generation',
            inputSHA256=self.stage(self.input),preparedBriefSHA256=self.files.stage('owner',self.session,(self.fixture/'prepared.json').read_bytes()),
            mappingSHA256=self.stage(self.mapping),anatomySHA256=self.stage(self.anatomy))

    def stage(self, value):
        return self.files.stage('owner',self.session,json.dumps(value).encode())

    def tearDown(self):
        self.store.close();self.temp.cleanup()

    def run_request(self, request=None):
        job=self.store.submit('owner',self.session,str(uuid.uuid4()),request or self.request)
        return job,run_one(self.store,self.artifacts,self.cli)

    def test_real_replay_publication_and_owner_scoped_result(self):
        job,result=self.run_request();self.assertTrue(result['published'])
        data=self.files.read_result('owner',job);out=json.loads(data)
        self.assertTrue(out['attachmentsReady']);self.assertFalse(out['modelExecuted'])
        self.assertFalse(out['personalStyleVerified']);self.assertEqual(len(out['rootPreflight']['missingRegions']),2)
        prepared=base64.b64decode(out['generationInputData'],validate=True)
        self.assertEqual(hashlib.sha256(prepared).hexdigest(),out['generationInputFileSHA256'])
        self.assertEqual(json.loads(prepared)['scalp'],self.input['scalp'])
        self.assertEqual(hashlib.sha256(data).hexdigest(),self.store.get('owner',job)['output_hash'])
        with self.assertRaises(LookupError):self.files.read_result('another-owner',job)
        self.assertEqual([p.name for p in next((self.artifacts/self.session/'jobs'/job).iterdir()).iterdir()],['result.json'])

    def test_conflicts_publish_review_instead_of_claiming_readiness(self):
        # The broad triangle passes through the fixture attachments.
        for vertex in self.anatomy['surfaces'][0]['vertices']:vertex['y']=self.root_y
        request=dict(self.request,anatomySHA256=self.stage(self.anatomy))
        job,result=self.run_request(request);self.assertTrue(result['published'])
        out=json.loads(self.files.read_result('owner',job))
        self.assertFalse(out['attachmentsReady']);self.assertTrue(out['rootPreflight']['requiresAttachmentReview'])
        self.assertGreater(len(out['rootPreflight']['violations']),0)

    def test_stale_brief_and_unsafe_request_fail_without_publication(self):
        altered=json.loads(json.dumps(self.input));altered['brief']['seed']+=1
        with self.assertRaises(ValueError):self.stage([])
        for request in [dict(self.request,inputSHA256=self.stage(altered)),dict(self.request,extraPath='/tmp'),
                        dict(self.request,schemaVersion=True),
                        dict(self.request,anatomySHA256=self.stage(dict(self.anatomy,clearanceMeters=0)))]:
            job,result=self.run_request(request);self.assertFalse(result['published'])
            self.assertEqual(self.store.get('owner',job)['state'],'failed')
            with self.assertRaises(LookupError):self.files.read_result('owner',job)

    def test_cancel_before_publication_removes_attempt(self):
        job=self.store.submit('owner',self.session,'cancel',self.request);finish=self.store.finish
        def cancel(*args,**kwargs):
            self.store.cancel('owner',job);return finish(*args,**kwargs)
        with patch.object(self.store,'finish',side_effect=cancel):
            self.assertFalse(run_one(self.store,self.artifacts,self.cli)['published'])
        self.assertEqual(self.store.get('owner',job)['state'],'cancelled')
        self.assertEqual(list((self.artifacts/self.session/'jobs'/job).glob('*/result.json')),[])
