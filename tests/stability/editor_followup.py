#!/usr/bin/env python3
"""Re-run the current author editor/live suite for each retained lifecycle project."""
import argparse,json,pathlib,subprocess
parser=argparse.ArgumentParser();parser.add_argument('--source',type=pathlib.Path,required=True);parser.add_argument('--lifecycle',type=pathlib.Path,required=True);args=parser.parse_args()
rows=[]
for index in range(3):
 out=args.lifecycle/f'author-editor-followup-{index}'
 command=['python3',str(args.source/'tests/node_authoring/run.py'),'--out',str(out)]
 with (args.lifecycle/f'author-editor-followup-{index}.log').open('w') as log:
  result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=600)
 rows.append({'index':index,'exit':result.returncode})
(args.lifecycle/'editor-followup.json').write_text(json.dumps(rows,indent=2)+'\n')
raise SystemExit(any(row['exit'] for row in rows))
