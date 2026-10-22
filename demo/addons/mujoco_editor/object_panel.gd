@tool
extends VBoxContainer
var plugin:EditorPlugin
var object_name:LineEdit
var shape_kind:OptionButton
var body_kind:OptionButton
var dimensions:LineEdit
var mass:LineEdit
var layer:LineEdit
var mask:LineEdit
var status:Label
func _ready():
 var title=Label.new();title.text="创建普通 Godot 场景对象（设计状态，不自动应用到已运行世界）";add_child(title)
 var row=HFlowContainer.new();add_child(row)
 object_name=_text(row,"名称","Body")
 shape_kind=OptionButton.new();for item in ["box","sphere","cylinder"]:shape_kind.add_item(item)
 row.add_child(shape_kind)
 body_kind=OptionButton.new();body_kind.add_item("静态");body_kind.add_item("刚体");row.add_child(body_kind)
 dimensions=_text(row,"尺寸 m","1 1 1");dimensions.tooltip_text="box: 完整 X Y Z；sphere: 半径；cylinder: 半径 完整高度"
 mass=_text(row,"质量 kg","1");layer=_text(row,"Layer","1");mask=_text(row,"Mask","1")
 var button=Button.new();button.text="在选中节点下创建";button.pressed.connect(create_from_fields);row.add_child(button)
 status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(status)
func _text(row:Control,title:String,value:String)->LineEdit:
 var label=Label.new();label.text=title;row.add_child(label)
 var edit=LineEdit.new();edit.text=value;edit.custom_minimum_size.x=95;row.add_child(edit);return edit
func create_from_fields()->bool:
 var selected=EditorInterface.get_selection().get_selected_nodes()
 if selected.size()!=1:status.text="请选择一个场景 Node3D 父节点";return false
 var values=dimensions.text.split(" ",false);var size_values=[]
 for value in values:
  if not value.is_valid_float():status.text="尺寸必须是数字";return false
  size_values.append(value.to_float())
 if not mass.text.is_valid_float() or not layer.text.is_valid_int() or not mask.text.is_valid_int():status.text="质量/碰撞值格式无效";return false
 return create_object(selected[0],{"name":object_name.text,"shape":shape_kind.get_item_text(shape_kind.selected),"rigid":body_kind.selected==1,"dimensions":size_values,"mass":mass.text.to_float(),"layer":layer.text.to_int(),"mask":mask.text.to_int()})
func create_object(parent:Node,config:Dictionary)->bool:
 var root=EditorInterface.get_edited_scene_root()
 if not root or not is_instance_valid(parent) or not parent is Node3D or not (parent==root or root.is_ancestor_of(parent)):
  status.text="父节点必须属于当前编辑场景";return false
 var ancestor:Node=parent
 while ancestor:
  if ancestor is CollisionObject3D:status.text="不在物理对象内嵌套物理对象";return false
  ancestor=ancestor.get_parent() if ancestor!=root else null
 var pose=parent.global_transform
 if not pose.is_finite() or not pose.basis.is_equal_approx(pose.basis.orthonormalized()) or pose.basis.determinant()<0:
  status.text="父节点必须为无缩放/镜像/剪切的刚性变换";return false
 var name_value=config.get("name","")
 if not name_value is String or name_value.is_empty() or name_value.validate_node_name()!=name_value or name_value in [".",".."] or parent.has_node(NodePath(name_value)):
  status.text="名称无效或已存在；重复点击不会重复创建";return false
 var kind=config.get("shape","");var values=config.get("dimensions",[])
 var count={"box":3,"sphere":1,"cylinder":2}.get(kind,0)
 if count==0 or not values is Array or values.size()!=count:status.text="尺寸数量错误";return false
 for value in values:
  if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(value) or value<=0 or not is_finite(PackedFloat32Array([value])[0]) or PackedFloat32Array([value])[0]<=0:status.text="尺寸必须有限且严格为正";return false
 # Validate derived float32 dimensions before allocating either resource or node.
 # SphereMesh uses diameter; native box/cylinder geometry uses half extents.
 var derived=[]
 match kind:
  "sphere":derived=[values[0]*2.0]
  "box":derived=[values[0]*.5,values[1]*.5,values[2]*.5]
  "cylinder":derived=[values[1]*.5]
 for value in derived:
  var stored=PackedFloat32Array([value])[0]
  if not is_finite(stored) or stored<=0:status.text="派生尺寸超出单精度有效范围";return false
 var weight=config.get("mass",0)
 if typeof(weight) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(weight) or weight<=0 or not is_finite(PackedFloat32Array([weight])[0]) or PackedFloat32Array([weight])[0]<=0:status.text="质量必须有限且为正";return false
 for key in ["layer","mask"]:
  var value=config.get(key,-1)
  if not value is int or value<0 or value>4294967295:status.text="碰撞位掩码必须是 uint32";return false
 if not config.get("rigid") is bool:status.text="请选择静态或刚体";return false
 var body:PhysicsBody3D=RigidBody3D.new() if config.rigid else StaticBody3D.new()
 body.name=name_value;body.collision_layer=config.layer;body.collision_mask=config.mask
 if body is RigidBody3D:body.mass=weight
 var collision=CollisionShape3D.new();collision.name="CollisionShape3D"
 var visual=MeshInstance3D.new();visual.name="MeshInstance3D"
 match kind:
  "box":
   var size_value=Vector3(values[0],values[1],values[2]);var shape=BoxShape3D.new();shape.size=size_value;collision.shape=shape
   var mesh=BoxMesh.new();mesh.size=size_value;visual.mesh=mesh
  "sphere":
   var shape=SphereShape3D.new();shape.radius=values[0];collision.shape=shape
   var mesh=SphereMesh.new();mesh.radius=values[0];mesh.height=values[0]*2;visual.mesh=mesh
  "cylinder":
   var shape=CylinderShape3D.new();shape.radius=values[0];shape.height=values[1];collision.shape=shape
   var mesh=CylinderMesh.new();mesh.top_radius=values[0];mesh.bottom_radius=values[0];mesh.height=values[1];visual.mesh=mesh
 body.add_child(collision);body.add_child(visual)
 var history=plugin.get_undo_redo();history.create_action("创建 MuJoCo 场景对象",UndoRedo.MERGE_DISABLE,parent)
 history.add_do_method(parent,"add_child",body,true)
 history.add_do_property(body,"owner",root);history.add_do_property(collision,"owner",root);history.add_do_property(visual,"owner",root)
 history.add_do_reference(body);history.add_undo_method(parent,"remove_child",body);history.commit_action()
 status.text="已创建场景设计："+str(body.get_path())+"；原生 Undo/Redo 与场景保存可用，运行场景需重新启动"
 return true
