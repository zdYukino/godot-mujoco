extends SceneTree
const Author = preload("res://addons/godot_mujoco/model/author_resource.gd")
const Commands = preload("res://addons/godot_mujoco/model/author_commands.gd")
const Xml = preload("res://addons/godot_mujoco/model/author_xml.gd")
const Model = preload("res://addons/godot_mujoco/model/model_instance.gd")
const Scene = preload("res://addons/godot_mujoco/model/author_scene.gd")
const Builder = preload("res://addons/godot_mujoco/model/author_builder.gd")

class CountedBody extends "res://addons/godot_mujoco/model/body_node.gd":
	var native_reads := 0
	func native_properties() -> Dictionary:
		native_reads += 1
		return super.native_properties()

class CountedJoint extends "res://addons/godot_mujoco/model/joint_node.gd":
	var native_reads := 0
	func native_properties() -> Dictionary:
		native_reads += 1
		return super.native_properties()

class CountedGeom extends "res://addons/godot_mujoco/model/geom_node.gd":
	var native_reads := 0
	func native_properties() -> Dictionary:
		native_reads += 1
		return super.native_properties()

var checks := 0
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		print("FAIL ", message)

func named(design: Resource, label: String) -> Dictionary:
	for entity in design.entities():
		if entity.name == label: return entity
	return {}

func _initialize() -> void:
	call_deferred("run")

func source_queries() -> void:
	var design: Resource = Author.from_xml('<mujoco><compiler angle="radian"/><default><joint damping=".2"/><default class="soft"><joint damping=".7"/><geom friction=".4 .01 .002"/></default></default><worldbody><frame pos="1 0 0" euler="0 0 .5"><body name="arm" childclass="soft"><joint name="hinge"/><geom name="ball" size=".1"/></body></frame><body name="target" pos="0 0 2"><geom name="target_ball" size=".1"/></body></worldbody><actuator><position name="drive" joint="hinge" kp="5" kv="2"/><velocity name="speed" joint="hinge" kv="3"/></actuator></mujoco>').design
	var arm := named(design, "arm")
	var hinge := named(design, "hinge")
	var ball := named(design, "ball")
	var target := named(design, "target")
	var original: Dictionary = design.author_snapshot()
	var first: Dictionary = design.entity_snapshot()
	check(first.is_read_only() and first.entities.is_read_only() and first.by_id[hinge.id].attrs.is_read_only(), "shared read stages are deeply immutable")
	check(first.by_id[arm.id].parent_id == "" and Xml.parent(design.tree, arm.id).tag == "frame", "projected body parents stay distinct from source frame parents")
	check(design.entity(hinge.id).attrs.damping == ".7", "projection preserves childclass inheritance")
	var public: Dictionary = design.entity(hinge.id)
	public.attrs.damping = "99"
	public.name = "corrupted"
	var public_list: Array = design.entities()
	public_list[0].attrs.name = "corrupted"
	public_list.clear()
	check(design.entity(hinge.id).attrs.damping == ".7" and design.entity(hinge.id).name == "hinge" and design.entity(arm.id).name == "arm", "public entity and list results cannot corrupt source or subsequent reads")
	var controls: Array = design.joint_actuators(hinge.id)
	controls[0].attrs.kp = "99"
	check(design.joint_actuators(hinge.id)[0].attrs.kp == "5", "actuator query results have independent ownership")
	# Direct Dictionary writes remain supported even without a revision change.
	var frame := Xml.parent(design.tree, arm.id)
	frame.attrs.pos = "3 0 0"
	var defaults := Xml.section(Xml.section(design.tree, "default"), "default")
	Xml.section(defaults, "joint").attrs.damping = ".9"
	check(design.entity(arm.id).transform.origin.is_equal_approx(Vector3(3, 0, 0)) and design.entity(hinge.id).attrs.damping == ".9", "same-revision frame and default alias writes invalidate effective reads")
	check(first.by_id[hinge.id].attrs.damping == ".7" and first.by_id[arm.id].transform == arm.transform, "an older read stage remains immutable after source mutation")
	var changed := original.duplicate(true)
	Xml.find(changed.tree, hinge.id).attrs.name = "renamed"
	Xml.find(changed.tree, ball.id).attrs.friction = ".6 .02 .003"
	check(design.restore_author(changed).is_empty() and design.revision == original.revision, "restore permits a different snapshot at the same serialized revision")
	check(design.entity(hinge.id).name == "renamed" and design.source_name(hinge.id) == "renamed" and design.entity(ball.id).attrs.friction == ".6 .02 .003", "same-revision restore refreshes attributes and stable-name lookup")
	var epoch: int = design.entity_snapshot().epoch
	var invalid := changed.duplicate(true)
	Xml.find(invalid.tree, ball.id).id = hinge.id
	check(not design.restore_author(invalid).is_empty(), "duplicate identity restore is rejected")
	check(design.entity_snapshot().epoch == epoch and design.entity(hinge.id).name == "renamed", "rejected restore preserves the published read stage")
	design.restore_author(original)
	var branch_one := Commands.execute(design, {"op":"set", "id":hinge.id, "values":{"damping":1.2}})
	design.restore_author(branch_one.after)
	check(design.entity(hinge.id).attrs.damping == "1.2", "first Undo branch publishes its source")
	design.restore_author(original)
	var branch_two := Commands.execute(design, {"op":"rename", "id":hinge.id, "name":"branch_joint"})
	design.restore_author(branch_two.after)
	check(branch_two.after.revision == branch_one.after.revision and design.entity(hinge.id).name == "branch_joint" and design.entity(hinge.id).attrs.damping == ".7", "a new Undo branch reusing revision cannot reuse previous branch data")
	design.restore_author(original)
	var fork: Resource = design.fork()
	fork.entity(hinge.id)
	Xml.find(fork.tree, hinge.id).attrs.damping = "4"
	check(fork.entity(hinge.id).attrs.damping == "4" and design.entity(hinge.id).attrs.damping == ".7", "fork invalidation and derived values remain resource-local")
	# A replacement tree and subsequent normalization both change effective pose.
	var replacement: Dictionary = design.tree.duplicate(true)
	var source_geom := Xml.find(replacement, ball.id)
	source_geom.attrs.type = "capsule"
	source_geom.attrs.fromto = "0 0 0 0 0 2"
	source_geom.attrs.size = ".1"
	design.tree = replacement
	check(not design.entity(ball.id).pose_editable, "whole-tree replacement is observed before normalization")
	design.normalize_geometries()
	check(design.entity(ball.id).pose_editable and is_equal_approx(Xml.numbers(design.entity(ball.id).attrs.size)[1], 1.0), "normalization invalidates a previously read source stage")
	design.restore_author(original)
	var pose: Transform3D = Commands.world_pose(design, arm.id)
	var reparented := Commands.execute(design, {"op":"reparent", "id":arm.id, "parent_id":target.id})
	check(reparented.error.is_empty(), "framed source reparent is accepted")
	design.restore_author(reparented.after)
	check(Commands.world_pose(design, arm.id).is_equal_approx(pose) and design.entity(arm.id).parent_id == target.id, "reparent uses source stages before and after its structural mutation")
	# The pose command queries world pose on both sides of its XML write.
	var floating: Resource = Author.from_xml('<mujoco><default><joint damping="8"/></default><worldbody><body name="floating" pos="0 0 1"><freejoint name="base"/><geom name="sphere" size=".1"/></body></worldbody></mujoco>').design
	var floating_body := named(floating, "floating")
	var free_joint := named(floating, "base")
	floating.initial_pose[free_joint.id] = [0.,0.,1.,1.,0.,0.,0.]
	var moved: Transform3D = floating_body.transform
	moved.origin += Vector3(2, 3, 0)
	var motion := Commands.execute(floating, {"op":"pose", "id":floating_body.id, "transform":moved})
	check(motion.error.is_empty(), "free-body pose command is accepted")
	floating.restore_author(motion.after)
	check(floating.entity(floating_body.id).transform.is_equal_approx(moved) and is_equal_approx(floating.initial_pose[free_joint.id][0], 2.0) and is_equal_approx(floating.initial_pose[free_joint.id][2], 4.0), "body motion migrates free-joint initial pose after the source write")
	check(not floating.entity(free_joint.id).attrs.has("damping"), "freejoint continues to ignore joint defaults")

func inspector_queries() -> void:
	var design: Resource = Author.from_xml('<mujoco><worldbody><body name="body"><joint name="joint" damping=".4"/><geom name="geom" size=".2" friction=".6 .02 .003"/></body><body name="explicit"><inertial mass="7" diaginertia="8 9 10" pos="1 2 3" quat="1 0 0 0"/><geom name="explicit_geom" size=".1"/></body></worldbody><actuator><position name="drive" joint="joint" kp="5" kv="2"/><velocity name="speed" joint="joint" kv="3"/></actuator></mujoco>').design
	var model := Model.new()
	model.design = design
	var body := CountedBody.new()
	body.entity_id = named(design, "body").id
	model.add_child(body)
	var explicit := CountedBody.new()
	explicit.entity_id = named(design, "explicit").id
	model.add_child(explicit)
	var joint := CountedJoint.new()
	joint.entity_id = named(design, "joint").id
	body.add_child(joint)
	var geom := CountedGeom.new()
	geom.entity_id = named(design, "geom").id
	body.add_child(geom)
	check(is_equal_approx(joint.get("mjcf/damping"), .4) and geom.get("mjcf/friction").is_equal_approx(Vector3(.6,.02,.003)), "source Inspector fields retain authored values")
	var joint_item: Dictionary = joint.item()
	var geom_item: Dictionary = geom.item()
	joint_item.attrs.damping = "99"
	geom_item.attrs.friction = "9 8 7"
	check(is_equal_approx(joint.get("mjcf/damping"), .4) and geom.get("mjcf/friction").is_equal_approx(Vector3(.6,.02,.003)) and joint.item().attrs.damping == ".4", "public node item results stay independently mutable when private getters share a read stage")
	check(joint.native_reads == 0 and geom.native_reads == 0, "joint and geom source getters do not request compiled fallback properties")
	check(body.get("mjcf/name") == "body" and body.native_reads == 0, "body name getter avoids native fallback lookup")
	check(joint.get("mjcf/actuators/drive/kp") == 5.0 and joint.get("mjcf/actuators/speed/kv") == 3.0 and joint.native_reads == 0, "actuator-bearing Inspector reads preserve relationships and stay source-only")
	var layout: Array = joint.get_property_list()
	check(layout.any(func(field): return field.name == "mjcf/actuators/drive/kp") and layout.any(func(field): return field.name == "mjcf/actuators/speed/kv"), "indexed actuator relationships retain dynamic field layout")
	var actuator: Dictionary = Xml.section(design.tree, "actuator").children[0]
	actuator.attrs.kp = "11"
	check(joint.get("mjcf/actuators/drive/kp") == 11.0, "direct same-revision actuator writes update Inspector")
	var renamed := Commands.execute(design, {"op":"rename", "id":joint.entity_id, "name":"renamed_joint"})
	design.restore_author(renamed.after)
	check(joint.joint_actuators().size() == 2 and joint.get("mjcf/actuators/drive/kp") == 11.0, "joint rename refreshes actuator-by-joint relationships")
	var manager := Scene.new()
	manager.host = model
	manager.nodes = {body.entity_id:body, explicit.entity_id:explicit, joint.entity_id:joint, geom.entity_id:geom}
	model.author_scene = manager
	var native_body := {"kind":"body", "name":"body", "properties":{"mass":2.0, "inertia":[3.0,4.0,5.0], "ipos":[0.0,0.0,0.0], "iquat":[1.0,0.0,0.0,0.0]}}
	var compiled := {"success":true, "author":design.author_snapshot(), "entities":[native_body], "geometry":[], "collision_geometry":[], "collision_stats":[], "snapshot":{}, "context":""}
	manager.apply_compiled(compiled)
	check(body.get("mjcf/mass") == 2.0 and body.get("mjcf/inertia") == Vector3(3,4,5), "compiled body fallback is visible after scene publication")
	var revision: int = design.revision
	compiled.entities[0].properties.mass = 4.0
	compiled.entities[0].properties.inertia = [5.0,6.0,7.0]
	manager.apply_compiled(compiled)
	check(design.revision == revision and body.get("mjcf/mass") == 4.0 and body.get("mjcf/inertia") == Vector3(5,6,7), "same-revision scene compiled replacement refreshes mass and inertia")
	compiled.entities[0].properties.mass = 6.0
	check(Builder.apply_result(design, compiled).is_empty() and design.revision == revision and body.get("mjcf/mass") == 6.0, "same-revision builder publication refreshes native fallback")
	design.cached_entities[0].properties.mass = 9.0
	check(body.get("mjcf/mass") == 9.0, "native fallback observes mutable compiled metadata without a source edit")
	check(explicit.get("mjcf/mass") == 7.0 and explicit.get("mjcf/inertia") == Vector3(8,9,10) and explicit.get("mjcf/center_of_mass").is_equal_approx(Xml.mj_vector(Vector3(1,2,3))) and explicit.get("mjcf/inertial_orientation").is_equal_approx(Quaternion.IDENTITY), "explicit inertial values retain precedence over native fallbacks")
	check(explicit.native_reads == 0, "explicit inertial fields do not request unused compiled fallbacks")
	model.free()

func run() -> void:
	source_queries()
	inspector_queries()
	print("NODE_QUERY_RESULT ", JSON.stringify({"checks":checks, "failed":failures.size(), "failures":failures}))
	quit(0 if failures.is_empty() else 1)
