import unittest
from create_prepared_model_sample import description_for, NAMES


class PreparedSamplePromptTests(unittest.TestCase):
    def fixture(self):
        return {'request':{'lengthRanges':[]}, 'compiled':{'input':{'brief':{'lengthLimits':[
            dict(region=r,minimumMeters=.001,maximumMeters=1.5) for r in NAMES]}}}}

    def test_unknown_preferences_do_not_become_style_claims(self):
        self.assertEqual(description_for(self.fixture()),'a hairstyle')

    def test_applied_limit_replaces_requested_limit(self):
        value=self.fixture()
        value['request']['lengthRanges']=[dict(region='fringe',minimumMeters=.04,maximumMeters=.06)]
        value['compiled']['input']['brief']['lengthLimits'][0].update(minimumMeters=.04,maximumMeters=.055)
        self.assertEqual(description_for(value),'a hairstyle with fringe 40 to 55 millimeters')

    def test_all_regions_fit_without_caption_truncation(self):
        value=self.fixture();value['request']['lengthRanges']=[dict(region=r) for r in reversed(NAMES)]
        prompt=description_for(value)
        self.assertLessEqual(len(('From frontal view image depicts '+prompt).split()),50)
        self.assertLess(prompt.index('fringe'),prompt.index('nape'))


if __name__=='__main__':unittest.main()
