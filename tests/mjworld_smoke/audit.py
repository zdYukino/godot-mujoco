import json
EXPECTED = 'ERROR: MjWorld.set_qpos: set_qpos expects 1 values, got 3'
MARKER = 'MJWORLD_NEGATIVE_RESULT '
def require(condition, message):
 if not condition: raise AssertionError(message)
def positive(text,code):
 require(code==0,code)
 require('ERROR:' not in text and 'leak' not in text.lower(),'positive diagnostics')
 require(text.splitlines().count('SMOKE TEST: PASS')==1,'missing or duplicate smoke result')
def negative(text,code):
 require(code==0,code)
 require('leak' not in text.lower(),'negative leak')
 require([line.strip() for line in text.splitlines() if 'ERROR:' in line]==[EXPECTED],'unexpected/extra error')
 rows=[line[len(MARKER):] for line in text.splitlines() if line.startswith(MARKER)]
 require(len(rows)==1,'missing or duplicate negative result')
 result=json.loads(rows[0])
 require(result=={'checks':3,'failed':0,'rejected':True,'unchanged':True},result)
 return result
