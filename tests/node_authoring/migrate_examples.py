#!/usr/bin/env python3
"""One-time reviewed scene migration, isolated from user editor sessions and imports."""
import argparse
from pathlib import Path
import re
import shutil
import subprocess

root=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--godot',required=True)
p.add_argument('--out',type=Path,required=True)
p.add_argument('examples',nargs='+')
a=p.parse_args()
for name in a.examples:
    source=root/'examples'/('templates/new_project' if name=='new_project' else name)
    project=a.out/name
    if project.exists(): raise SystemExit(f'Use a fresh directory: {project}')
    shutil.copytree(source,project,ignore=shutil.ignore_patterns('.godot','addons','bin','obj'))
    shutil.copytree(root/'addons',project/'addons')
    shutil.copyfile(root/'tests/node_authoring/migrate_examples.gd',project/'migrate_examples.gd')
    if name=='new_project':
        config=project/'project.godot'
        config.write_text(config.read_text().replace('__PROJECT_NAME__','"MuJoCo Template"'))
    # Migration loads scenes off-tree. The editor is used only to register scripts/assets.
    for stage,flags in [('import',['--editor','--import']),('migration',['--script','res://migrate_examples.gd','--',name])]:
        log=a.out/f'{name}-{stage}.log'
        with log.open('w') as stream:
            result=subprocess.run([a.godot,'--headless','--path',str(project),*flags],stdout=stream,stderr=subprocess.STDOUT,timeout=180)
        text=log.read_text()
        if result.returncode or any(x in text for x in ['SCRIPT ERROR:','ERROR:','leaked']):
            raise SystemExit(f'{name} {stage}: {result.returncode}\n{text[-8000:]}')
    paths=['G1.tscn'] if name=='g1_passive' else ['Main.tscn','ChaosPendulum.tscn','VisualDebug.tscn'] if name=='pendulum' else ['Main.tscn']
    for relative in paths:
        target=source/relative
        old=target.read_text()
        text=(project/relative).read_text()
        # Preserve existing scene and external resource UID identities, including user edits.
        uid=re.search(r'^\[gd_scene[^\n]* uid="([^"]+)"',old)
        if uid:
            header=text.splitlines()[0]
            header=re.sub(r' uid="[^"]+"','',header)[:-1]+f' uid="{uid[1]}"]'
            text=header+text[text.index('\n'):]
        old_uids={m[2]:m[1] for m in re.finditer(r'\[ext_resource[^\n]*uid="([^"]+)"[^\n]*path="([^"]+)"',old)}
        def preserve(m):
            line=m[0]; path=re.search(r'path="([^"]+)"',line)[1]
            if path in old_uids:
                line=re.sub(r' uid="[^"]+"','',line).replace(' path=',f' uid="{old_uids[path]}" path=')
            return line
        text=re.sub(r'\[ext_resource[^\n]*path="[^"]+"[^\n]*\]',preserve,text)
        target.write_text(text)
    if (project/'mujoco_models').exists(): shutil.copytree(project/'mujoco_models',source/'mujoco_models',dirs_exist_ok=True)
    print('MIGRATED',name,flush=True)
