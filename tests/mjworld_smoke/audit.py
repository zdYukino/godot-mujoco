import json
EXPECTED = 'ERROR: MjWorld.set_qpos: set_qpos expects 1 values, got 3'
MARKER = 'MJWORLD_NEGATIVE_RESULT '
def positive(text,code):
 assert code==0,code
 assert 'ERROR:' not in text and 'leak' not in text.lower(),'positive diagnostics'
 assert text.splitlines().count('SMOKE TEST: PASS')==1,'missing or duplicate smoke result'
def negative(text,code):
 assert code==0,code
 assert 'leak' not in text.lower(),'negative leak'
 assert [line.strip() for line in text.splitlines() if 'ERROR:' in line]==[EXPECTED],'unexpected/extra error'
 rows=[line[len(MARKER):] for line in text.splitlines() if line.startswith(MARKER)]
 assert len(rows)==1,'missing or duplicate negative result'
 result=json.loads(rows[0])
 assert result=={'checks':3,'failed':0,'rejected':True,'unchanged':True},result
 return result
