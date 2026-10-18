"""无项目缓存GUI首次导入，以及独立进程重新打开/API结果核对。"""
import sys,time,json,pathlib
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'editor_plugin'))
import mouse_acceptance as m
try:
 m.wait_window()
 for _ in range(400):
  if (m.folder/'state.json').exists():break
  time.sleep(.1)
 time.sleep(2)
 mode=sys.argv[2];project=pathlib.Path(sys.argv[3]);doc=project/'daily.gmj.json'
 if mode=='first':
  m.button('Import MJCF');m.dialog_file(str(project/'fixtures/pendulum.xml'));m.click(m.item('hinge')['rect']);m.field('damping','0.2');m.button('Apply to physics');m.check(m.damping()==.2 and not m.state()['pending'],'real GUI import and edit damping')
  m.button('Save document');m.dialog_file(str(doc));m.check(doc.exists(),'real GUI saves design document')
  m.button('Save project model')
  for _ in range(100):
   text=m.state()['status']
   if text.startswith('Saved portable project model: '):break
   time.sleep(.1)
  resource=text.removeprefix('Saved portable project model: ');m.check(resource.startswith('res://') and (project/resource[6:]).exists(),'real GUI saves portable design resource')
  (m.folder.parent/'resource-path.txt').write_text(resource)
 else:
  m.button('Open document');m.dialog_file(str(doc));m.click(m.item('hinge')['rect']);m.check(m.damping()==(.2 if mode=='reopen' else .35),'independent GUI reopen verifies saved damping')
  if mode=='api':m.check(any(i['name']=='api_box' and i['kind']=='body' for i in m.state()['items']),'GUI sees API-added body')
 m.shot(mode+'-verified')
 if not all(x['passed'] for x in m.checks):raise SystemExit(1)
finally:
 (m.folder/'results.json').write_text(json.dumps(m.checks,indent=2));m.request(quit=True)
