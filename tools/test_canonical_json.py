import json
import math
import unittest
from tools.canonical_json import loads


class CanonicalJSONTests(unittest.TestCase):
    def test_preserves_negative_zero_and_exact_integer_seeds(self):
        value=loads('{"normal":-0,"seed":18446744073709551615,"index":0}')
        self.assertEqual(math.copysign(1,value['normal']),-1)
        self.assertEqual(value['seed'],18446744073709551615)
        self.assertIsInstance(value['seed'],int)
        self.assertIsInstance(value['index'],int)
        self.assertEqual(math.copysign(1,json.loads(json.dumps(value))['normal']),-1)
