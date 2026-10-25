@tool
extends RefCounted
# 仅观测 GUI 状态和定位可见控件；鼠标/键盘由外部 XTEST 驱动。
var plugin: EditorPlugin
var folder := ""
var seq := 0
var elapsed := 0.0
func run(p: EditorPlugin) -> void:
 plugin=p
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--probe-dir="): folder=arg.trim_prefix("--probe-dir=")
 DirAccess.make_dir_recursive_absolute(folder)
 plugin.panel.import_mjcf("res://fixtures/pendulum.xml")
 plugin.panel.add_primitive("sphere")
 plugin.reveal_scope(0)
 EditorInterface.set_main_screen_editor("3D")
 plugin.get_tree().process_frame.connect(tick)
func rect(c: Control) -> Array:
 var r=Rect2(c.get_screen_transform().origin,c.size)
 return [r.position.x,r.position.y,r.size.x,r.size.y]
func items(item: TreeItem, result: Array) -> void:
 if not item:return
 var d=item.get_metadata(0)
 if d is Dictionary:
  var r: Rect2=plugin.panel.tree.get_item_area_rect(item)
  r.position+=plugin.panel.tree.get_screen_transform().origin
  result.append({"kind":d.kind,"name":d.name,"selected":item.is_selected(0),"rect":[r.position.x,r.position.y,r.size.x,r.size.y]})
 for child in item.get_children():items(child,result)
func controls(n: Node, result: Array) -> void:
 if n is Button and n.is_visible_in_tree(): result.append({"text":n.text,"rect":rect(n)})
 if n is FileDialog and n.visible: result.append({"dialog":true,"file":rect(n.get_line_edit()),"ok":rect(n.get_ok_button())})
 for c in n.get_children():controls(c,result)
func tick() -> void:
 elapsed+=plugin.get_process_delta_time()
 if elapsed<0.1:return
 elapsed=0
 var panel=plugin.panel
 var req=folder.path_join("request.json")
 if FileAccess.file_exists(req):
  var d=JSON.parse_string(FileAccess.get_file_as_string(req));DirAccess.remove_absolute(req)
  if d is Dictionary:
   if d.get("quit",false):
    panel.pending=false;panel.state.dirty=false;plugin.get_tree().quit();return
   if d.has("scroll"):
    var target: Control=panel.inputs.get(d.scroll)
    if d.scroll=="__entities__": target=panel.tree
    if not target: target=find_button(panel,str(d.scroll))
    if target:
     var current:Node=target
     while current and current!=panel:
      var parent=current.get_parent()
      if parent and current.get_index()>0:
       var previous=parent.get_child(current.get_index()-1)
       if previous is Button and previous.toggle_mode:previous.button_pressed=true
      current=parent
     plugin.pages[0].ensure_control_visible(target)
 var rows: Array=[];items(panel.tree.get_root(),rows)
 var cs: Array=[];controls(plugin.get_tree().root,cs)
 var fields: Dictionary={}
 for k in panel.inputs:fields[k]={"text":panel.inputs[k].text,"rect":rect(panel.inputs[k]),"id":panel.inputs[k].get_instance_id()}
 var points={}
 for name in panel.meshes:
  var point=panel.camera.unproject_position(panel.meshes[name].global_position)+EditorInterface.get_editor_viewport_3d(0).get_parent().get_screen_transform().origin
  points[name]=[point.x,point.y,1,1]
 var data={"points":points,"seq":seq,"selected":panel.selected,"pending":panel.pending,"dirty":panel.state.dirty,"items":rows,"fields":fields,"controls":cs,"status":panel.status.text,"snapshot":panel.state.document.snapshot()}
 seq+=1
 var f=FileAccess.open(folder.path_join("state.tmp"),FileAccess.WRITE);f.store_string(JSON.stringify(data));f.close();DirAccess.rename_absolute(folder.path_join("state.tmp"),folder.path_join("state.json"))

func find_button(node: Node, title: String) -> Control:
 if node is Button and node.text==title:return node
 for child in node.get_children():
  var found:=find_button(child,title)
  if found:return found
 return null
