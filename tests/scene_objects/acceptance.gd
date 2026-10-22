@tool
extends RefCounted
var passed:=0
var failed:=0
func check(ok:bool,label:String):
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;printerr("FAIL ",label)
func run(plugin:EditorPlugin):
 var root=Node3D.new();root.name="Objects";var parent=Node3D.new();parent.name="Other";root.add_child(parent);parent.owner=root
 var packed=PackedScene.new();packed.pack(root);ResourceSaver.save(packed,"res://Objects.tscn");root.free()
 EditorInterface.get_resource_filesystem().scan()
 for i in 8:await plugin.get_tree().process_frame
 EditorInterface.open_scene_from_path("res://Objects.tscn")
 for i in 8:await plugin.get_tree().process_frame
 root=EditorInterface.get_edited_scene_root();parent=root.get_node("Other")
 var panel=plugin.object_panel
 var config={"name":"Box","shape":"box","dimensions":[1.0,2.0,3.0],"rigid":true,"mass":2.0,"layer":3,"mask":5}
 check(panel.create_object(root,config),"create rigid box")
 var body=root.get_node("Box")
 check(body is RigidBody3D and body.mass==2 and body.collision_layer==3 and body.collision_mask==5,"mass and collision configuration")
 check(body.get_node("CollisionShape3D").shape.size==Vector3(1,2,3) and body.get_node("MeshInstance3D").mesh.size==Vector3(1,2,3),"box mesh collision dimensions")
 check(not panel.create_object(root,config) and root.get_child_count()==2,"repeat create rejects duplicate")
 var history=plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(root))
 history.undo();check(not root.has_node("Box"),"native undo removes created subtree")
 history.redo();check(root.get_node("Box")==body and body.owner==root and body.get_node("CollisionShape3D").owner==root,"redo ownership restored")
 config.name="Sphere";config.shape="sphere";config.dimensions=[.4];config.rigid=false
 check(panel.create_object(parent,config),"create static sphere under selected parent")
 check(not root.has_node("Sphere") and parent.get_node("Sphere") is StaticBody3D,"parent selection isolated")
 check(is_equal_approx(parent.get_node("Sphere/MeshInstance3D").mesh.height,.8),"sphere remains spherical")
 config.name="Cylinder";config.shape="cylinder";config.dimensions=[.5,1.6]
 check(panel.create_object(root,config),"create static cylinder")
 check(is_equal_approx(root.get_node("Cylinder/CollisionShape3D").shape.height,1.6),"full cylinder height")
 config.name="Invalid";config.dimensions=[0,1]
 check(not panel.create_object(root,config) and not root.has_node("Invalid"),"invalid dimensions no partial node")
 config.dimensions=[NAN,1];check(not panel.create_object(root,config),"nonfinite rejected")
 config.dimensions=[1e100,1];check(not panel.create_object(root,config),"float32 overflow rejected before node creation")
 config.dimensions=[1e-100,1];check(not panel.create_object(root,config),"float32 underflow rejected before node creation")
 config.dimensions=[.5,1];config.mass=-1;check(not panel.create_object(root,config),"invalid mass rejected")
 config.mass=1;config.layer=-1;check(not panel.create_object(root,config),"invalid layer rejected")
 config.layer=1;check(not panel.create_object(body,config),"nested physics body rejected")
 parent.scale=Vector3(2,1,1);check(not panel.create_object(parent,config),"scaled parent rejected");parent.scale=Vector3.ONE
 var node_count=root.get_child_count();var undo_version=history.get_version()
 config.shape="sphere";config.dimensions=[2e38]
 check(not panel.create_object(root,config) and root.get_child_count()==node_count and history.get_version()==undo_version,"sphere diameter overflow rejects before nodes and undo history")
 config.shape="box";config.dimensions=[1e-45,1,1]
 check(not panel.create_object(root,config) and root.get_child_count()==node_count and history.get_version()==undo_version,"box half extent underflow rejects without mutation")
 config.shape="cylinder";config.dimensions=[1,1e-45]
 check(not panel.create_object(root,config) and root.get_child_count()==node_count and history.get_version()==undo_version,"cylinder half height underflow rejects without mutation")
 EditorInterface.save_scene_as("res://Objects.tscn",false)
 var reopened=ResourceLoader.load("res://Objects.tscn","",ResourceLoader.CACHE_MODE_IGNORE).instantiate()
 check(reopened.get_node("Box").mass==2 and is_equal_approx(reopened.get_node("Other/Sphere/CollisionShape3D").shape.radius,.4) and is_equal_approx(reopened.get_node("Cylinder/CollisionShape3D").shape.height,1.6),"save reopen all shapes and properties");reopened.free()
 var result={"passed":passed,"failed":failed}
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--report="):var f=FileAccess.open(arg.trim_prefix("--report="),FileAccess.WRITE);f.store_string(JSON.stringify(result))
 print("OBJECT_RESULT ",JSON.stringify(result));plugin.get_tree().quit(0 if failed==0 else 1)
