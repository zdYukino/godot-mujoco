import json,unittest
from audit import positive,negative,EXPECTED,MARKER
class AuditTests(unittest.TestCase):
 def setUp(self):self.clean=EXPECTED+'\n'+MARKER+json.dumps({'checks':3,'failed':0,'rejected':True,'unchanged':True})+'\n'
 def test_expected_only(self):negative(self.clean,0)
 def test_positive(self):positive('SMOKE TEST: PASS\n',0)
 def test_positive_rejects_errors(self):
  for s in ['ERROR: extra\n','SCRIPT ERROR: bad\n','ObjectDB instances leaked\n']:
   with self.subTest(s=s),self.assertRaises(AssertionError):positive(s+'SMOKE TEST: PASS\n',0)
 def test_negative_rejects_extra(self):
  for s in ['ERROR: extra\n',EXPECTED+'\n','SCRIPT ERROR: bad\n','ObjectDB instances leaked\n']:
   with self.subTest(s=s),self.assertRaises(AssertionError):negative(self.clean+s,0)
 def test_wrong_error(self):
  with self.assertRaises(AssertionError):negative(self.clean.replace('got 3','got 4'),0)
 def test_exit_codes(self):
  for code in [1,124,137,139,-11]:
   with self.subTest(code=code),self.assertRaises(AssertionError):negative(self.clean,code)
 def test_missing_duplicate_or_failed_result(self):
  for text in [EXPECTED,self.clean+self.clean.splitlines()[1],self.clean.replace('"failed": 0','"failed": 1')]:
   with self.subTest(text=text),self.assertRaises(AssertionError):negative(text,0)
if __name__=='__main__':unittest.main()
