extends RefCounted
const SavedScene = preload("res://addons/godot_mujoco/model/saved_scene_loader.gd")
const Author = preload("res://addons/godot_mujoco/model/author_resource.gd")

static func run(check: Callable) -> void:
	var base := "res://saved_reload_probe/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base))
	var external := base+"model.tres"
	var nested := base+"environment.tscn"
	var outer := base+"game.tscn"
	ResourceSaver.save(Author.from_xml('<mujoco model="external_before"><worldbody/></mujoco>').design,external)
	write_scene(nested,nested_scene(external,"inline_before",1.0))
	write_scene(outer,'[gd_scene load_steps=2 format=3]\n[ext_resource type="PackedScene" path="'+nested+'" id="1"]\n[node name="Game" type="Node3D"]\n[node name="Runtime" parent="." instance=ExtResource("1")]\n')
	var cached: PackedScene=ResourceLoader.load(outer)
	var old: Node=cached.instantiate()
	var old_world: Node=old.get_node("Runtime")
	var old_design: Resource=old_world.get_node("Model").design
	var script: Script=old_world.get_script()
	var extensions := ResourceLoader.get_recognized_extensions_for_type("Script")
	ResourceSaver.save(Author.from_xml('<mujoco model="external_after"><worldbody/></mujoco>').design,external)
	write_scene(nested,nested_scene(external,"inline_after",4.0))
	var fresh := SavedScene.load_scene(outer)
	check.call(fresh!=null and fresh!=cached,"saved reload produces a private fresh scene")
	if fresh:
		var current: Node=fresh.instantiate()
		var world: Node3D=current.get_node("Runtime")
		check.call(world.position.is_equal_approx(Vector3(4,2,3)),"saved reload reads updated nested scene transforms")
		check.call(world.world_design.tree.attrs.model=="inline_after","saved reload reads updated nested inline author data")
		check.call(world.get_node("Model").design.tree.attrs.model=="external_after","saved reload reads updated external author data")
		check.call(world.get_script()==script and ResourceLoader.get_cached_ref(script.resource_path)==script,"saved reload preserves executing Script identity")
		check.call(world.get_node("Model").design!=old_design,"saved reload never mutates the previous world's author resource")
		current.free()
	check.call(old_world.position.is_equal_approx(Vector3(1,2,3)) and old_world.world_design.tree.attrs.model=="inline_before" and old_design.tree.attrs.model=="external_before","saved reload leaves previous nested scene and author data intact")
	check.call(ResourceLoader.get_recognized_extensions_for_type("Script")==extensions,"saved reload removes its scoped script loader after success")
	check.call(SavedScene.load_scene(external)==null,"saved reload rejects a non-scene resource")
	check.call(ResourceLoader.get_recognized_extensions_for_type("Script")==extensions,"saved reload removes its scoped script loader after rejection")
	old.free()

static func write_scene(path: String,text: String) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(text)

static func nested_scene(external: String,label: String,x: float) -> String:
	return '''[gd_scene load_steps=6 format=3]
[ext_resource type="Script" path="res://addons/godot_mujoco/model/runtime_world.gd" id="1"]
[ext_resource type="Script" path="res://addons/godot_mujoco/model/author_resource.gd" id="2"]
[ext_resource type="Script" path="res://addons/godot_mujoco/model/model_instance.gd" id="3"]
[ext_resource type="Resource" path="%s" id="4"]
[sub_resource type="Resource" id="Inline"]
script = ExtResource("2")
tree = {"tag":"mujoco","attrs":{"model":"%s"},"children":[]}
[node name="Runtime" type="Node3D"]
script = ExtResource("1")
position = Vector3(%s,2,3)
world_design = SubResource("Inline")
[node name="Model" type="Node3D" parent="."]
script = ExtResource("3")
design = ExtResource("4")
''' % [external,label,x]
