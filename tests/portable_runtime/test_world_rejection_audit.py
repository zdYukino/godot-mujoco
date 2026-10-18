import json
import unittest
from world_rejections import CASES, MARKER, audit


class RejectionAuditTests(unittest.TestCase):
    def fixture(self, case):
        error, count = CASES[case]
        result = {"case": case, "failed": 0, "checks": [{"name": str(i), "passed": True} for i in range(count)]}
        return "ERROR: " + error + "\n" + MARKER + json.dumps(result) + "\n"

    def test_exact_isolated_cases(self):
        for case in CASES:
            with self.subTest(case=case):
                audit(self.fixture(case), case, 0)

    def test_rejects_false_green_logs(self):
        case = "ownership"
        clean = self.fixture(case)
        mutations = [
            clean + "ERROR: unrelated failure\n",
            clean + "SCRIPT ERROR: invalid access\n",
            clean + "WARNING: ObjectDB instances leaked at exit\n",
            clean.replace("ERROR:", "WARNING:", 1),
            clean.replace("World3D", "World2D", 1),
            clean + clean.splitlines()[0] + "\n",
            clean + MARKER + "{}\n",
            clean.split(MARKER)[0],
            clean.replace('"passed": true', '"passed": false', 1),
            clean.replace('"failed": 0', '"failed": 1'),
            clean.replace('"case": "ownership"', '"case": "missing_model"'),
        ]
        for text in mutations:
            with self.subTest(text=text):
                with self.assertRaises(AssertionError):
                    audit(text, case, 0)
        for code in (1, 124, -11):
            with self.subTest(exit=code):
                with self.assertRaises(AssertionError):
                    audit(clean, case, code)


if __name__ == "__main__":
    unittest.main()
