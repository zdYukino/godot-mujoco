#!/usr/bin/env python3
"""GTR/Linux bounded, isolated acceptance; no existing project is modified."""
import argparse,hashlib,json,os,pathlib,platform,shutil,subprocess,sys,time
root=pathlib.Path(__file__).resolve().parents[2]
ap=argparse.ArgumentParser();ap.add_argument('--out',required=True);ap.add_argument('--godot',default=os.environ.get('GODOT_BIN'));ap.add_argument('--sdk',default=os.environ.get('MUJOCO_SDK_DIR'));ap.add_argument('--build-dir');ap.add_argument('--extended',action='store_true',help='retain unchanged seeded fuzz and multi-depth convergence as an optional extended run');a=ap.parse_args()
if not a.godot:ap.error('set GODOT_BIN or --godot')
if not a.sdk:ap.error('set MUJOCO_SDK_DIR or --sdk for the fixed 3.16 native-field test')
out=pathlib.Path(a.out).resolve()
if out.exists():ap.error('output must be new; existing evidence is preserved')
out.mkdir(parents=True)
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
sources={str(p.relative_to(root)):digest(p) for base in ['src','demo/addons','tests/spatial_queries','tests/sdf_terrain','examples/sdf_terrain'] for p in (root/base).rglob('*') if p.is_file() and p.suffix in ['.cpp','.h','.gd','.py','.sh','.gdshader','.json','.obj'] and '.godot' not in p.parts and 'bin' not in p.parts}
sources['CMakeLists.txt']=digest(root/'CMakeLists.txt')
provenance={'host':platform.node(),'system':platform.platform(),'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),'branch':subprocess.check_output(['git','branch','--show-current'],cwd=root,text=True).strip(),'sources':sources,'binary_sha256':digest(root/'demo/addons/godot_mujoco/bin/libgodot_mujoco.linux.template_debug.x86_64.so'),'godot':subprocess.check_output([a.godot,'--version'],text=True).strip()}
if a.build_dir:
    build=pathlib.Path(a.build_dir).resolve()
    cache=build/'CMakeCache.txt';flags=build/'CMakeFiles/godot_mujoco.dir/flags.make'
    provenance['build_dir']=str(build)
    provenance['compiler_settings']=[line for p in [cache,flags] if p.exists() for line in p.read_text().splitlines() if line.startswith(('CMAKE_BUILD_TYPE:','CMAKE_CXX_COMPILER:','CMAKE_CXX_FLAGS:','GMJ_OPTIMIZE_SPATIAL_QUERIES:','CXX_FLAGS =','# Custom options:'))]
(out/'provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
rows=[]
def run(name,command,marker=None,seconds=90):
    log=out/(name+'.log')
    with (out/(name+'-monitor.log')).open('x') as f:
        rc=subprocess.call([sys.executable,str(root/'tests/g1_hot_add_repro/bounded.py'),'--log',str(log),'--seconds',str(seconds),'--max-rss-mib','1400','--min-available-mib','1400','--',*map(str,command)],cwd=root,stdout=f,stderr=subprocess.STDOUT)
    text=log.read_text();row={'name':name,'exit':rc,'rss_scope':'direct monitored process; shell child RSS is not included','resources':json.loads(log.with_suffix('.resources.json').read_text())}
    if marker:
        found=[json.loads(line[len(marker)+1:]) for line in text.splitlines() if line.startswith(marker+' ')]
        if len(found)!=1 or found[0].get('failed',0):rc=1
        row['result']=found[0] if len(found)==1 else {'error':'missing or repeated result marker'}
    if 'SCRIPT ERROR:' in text or '\nERROR:' in text or 'leaked' in text:rc=1
    row['ok']=rc==0;rows.append(row)
    (out/'results.json').write_text(json.dumps({'provenance':'provenance.json','runs':rows,'ok':all(r['ok'] for r in rows)},indent=2,default=str)+'\n')
    print(name,'PASS' if row['ok'] else 'FAIL',flush=True)
    return row['ok']
for name in ['convex_numerics','convex_sat']:
    executable=out/name
    run(name+'-compile',['g++','-O2','-std=c++17',root/'tests/spatial_queries'/(name+'.cpp'),'-o',executable])
    run(name,[executable],seconds=30)
sdk=pathlib.Path(a.sdk).resolve();native=out/'sdf_interval'
if run('sdf-interval-compile',['g++','-O2','-std=c++17','-I'+str(sdk/'include'),root/'tests/spatial_queries/sdf_interval.cpp','-L'+str(sdk/'lib'),'-Wl,-rpath,'+str(sdk/'lib'),'-lmujoco','-o',native]):
    run('sdf-interval',[native,*(['--extended'] if a.extended else [])],'SDF_INTERVAL_NATIVE_RESULT',45)
query=out/'query-project';query.mkdir()
shutil.copy(root/'tests/static_map/project.godot',query)
shutil.copytree(root/'demo/addons',query/'addons')
shutil.copy(root/'tests/spatial_queries/query_test_base.gd',query)
for name in ['area','convex_cast','hfield_cast','status','asset_pair_matrix','sdf_thin']:shutil.copy(root/'tests/spatial_queries'/f'{name}.gd',query)
run('query-import',['bash',root/'scripts/import_headless.sh',query])
for name,marker in [('area','AREA_QUERY_RESULT'),('convex_cast','CONVEX_CAST_RESULT'),('hfield_cast','HFIELD_CAST_RESULT'),('status','QUERY_STATUS_RESULT'),('asset_pair_matrix','ASSET_PAIR_MATRIX_RESULT'),('sdf_thin','SDF_THIN_RESULT')]:
    run(name,[a.godot,'--headless','--path',query,'--fixed-fps','60','--script',f'res://{name}.gd'],marker,30)
terrain=out/'terrain';terrain.mkdir()
run('terrain-prepare',['env','OUT='+str(terrain),'GODOT_BIN='+a.godot,'bash',root/'examples/sdf_terrain/prepare.sh'],seconds=120)
project=terrain/'project'
shutil.copy(root/'tests/spatial_queries/query_test_base.gd',project)
for name,source,marker in [('terrain',root/'tests/sdf_terrain/acceptance.gd','SDF_TERRAIN_RESULT'),('asset_overlap',root/'tests/spatial_queries/asset_overlap.gd','ASSET_OVERLAP_RESULT'),('sdf_cast',root/'tests/spatial_queries/sdf_cast.gd','SDF_CAST_RESULT'),('sdf_terrain_edges',root/'tests/spatial_queries/sdf_terrain_edges.gd','SDF_TERRAIN_EDGES_RESULT'),('sdf_precision',root/'tests/spatial_queries/sdf_precision.gd','SDF_PRECISION_RESULT')]:
    shutil.copy(source,project/(name+'.gd'))
    run(name,[a.godot,'--headless','--path',project,'--fixed-fps','60','--script',f'res://{name}.gd'],marker,60)
if a.extended:
    run('sdf-precision-comparison',[a.godot,'--headless','--path',project,'--fixed-fps','60','--script','res://sdf_precision.gd','--','--compare'],'SDF_PRECISION_COMPARISON_RESULT',60)
    shutil.copy(root/'tests/sdf_terrain/convergence.gd',project/'convergence.gd')
    run('convergence',[a.godot,'--headless','--path',project,'--fixed-fps','60','--script','res://convergence.gd'],'SDF_CONVERGENCE_RESULT',60)
shutil.copy(root/'tests/sdf_terrain/editor.gd',project/'map_editor_test.gd')
shutil.copy(root/'tests/sdf_terrain/editor_reopen.gd',project)
if 'res://addons/mujoco_editor/plugin.cfg' not in (project/'project.godot').read_text():
    raise SystemExit('Terrain preparation did not enable the editor plugin; no test-only config repair is allowed')
run('terrain-editor',[a.godot,'--headless','--editor','--path',project,'--','--static-map-test'],'SDF_EDITOR_RESULT',120)
run('terrain-editor-reopen',[a.godot,'--headless','--path',project,'--fixed-fps','60','--script','res://editor_reopen.gd'],'SDF_EDITOR_REOPEN_RESULT',30)
ok=all(row['ok'] for row in rows)
print('QUERY_TERRAIN_ACCEPTANCE_PASS' if ok else 'QUERY_TERRAIN_ACCEPTANCE_FAIL',out)
raise SystemExit(0 if ok else 1)
