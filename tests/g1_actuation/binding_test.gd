extends SceneTree

# Run from the runner's staged project with --script res://tests/g1_actuation/binding_test.gd.
# The fixture contains only 29 one-DoF hinge joints, so joint IDs are qpos/qvel offsets.
const ASSET_DIR := "res://assets/robots/unitree_g1/g1_29dof_mode_18/"
const JOINT_COUNT := 29
const STEPS := 4000
const STEP_CHUNK := 100
const OFFSET := 0.02
const TOLERANCE := 0.002

var _world
var _inventory: Array = []
var _joint_ids: Array[int] = []
var _actuator_ids: Array[int] = []
var _base_qpos := PackedFloat64Array()
var _base_ctrl := PackedFloat64Array()
var _lower := PackedFloat64Array()
var _upper := PackedFloat64Array()
var _failure := ""
var _max_error := 0.0
var _trials := 0
var _steps := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var started := Time.get_ticks_msec()
	var passed := _test()
	print("G1_BINDING_RESULT ", JSON.stringify({
		"binding": "gdscript", "passed": passed, "joint_count": _joint_ids.size(),
		"trials": _trials, "steps": _steps, "max_position_error_rad": _max_error,
		"position_tolerance_rad": TOLERANCE, "elapsed_ms": Time.get_ticks_msec() - started,
		"failure": _failure,
	}))
	print("G1 GDSCRIPT ", "PASS" if passed else "FAIL")
	quit(0 if passed else 1)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_failure = message
		push_error("G1 GDSCRIPT: " + message)
	return condition


func _test() -> bool:
	if not _check(ClassDB.class_exists("MjWorld"), "MjWorld extension is not registered"):
		return false
	_world = ClassDB.instantiate("MjWorld")
	root.add_child(_world)
	_world.set_auto_step(false)
	if not _check(_world.get_mujoco_version() == "3.16.0", "expected MuJoCo 3.16.0; got " + _world.get_mujoco_version()):
		return false
	var model_path := OS.get_environment("G1_MODEL_PATH")
	if model_path.is_empty():
		model_path = ASSET_DIR + "actuation-test.xml"
	if not _check(_world.load_model(model_path), "load_model failed: " + _world.get_last_error()):
		return false
	if not _check(_world.is_ready(), "model is not ready after loading"):
		return false
	for dimension in ["get_nq", "get_nv", "get_nu", "get_njnt"]:
		if not _check(_world.call(dimension) == JOINT_COUNT, dimension + " must be 29"):
			return false
	if not _check(absf(_world.get_timestep() - 0.001) < 1e-12, "fixture timestep must be 0.001"):
		return false
	var inventory_path := OS.get_environment("G1_INVENTORY_PATH")
	if inventory_path.is_empty():
		inventory_path = model_path.get_base_dir().path_join("joint-inventory.json")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(inventory_path))
	if not _check(parsed is Array and parsed.size() == JOINT_COUNT, "inventory must list 29 joints"):
		return false
	_inventory = parsed
	_base_qpos.resize(JOINT_COUNT)
	_base_ctrl.resize(JOINT_COUNT)
	_lower.resize(JOINT_COUNT)
	_upper.resize(JOINT_COUNT)
	var seen_names := {}
	var seen_joints := {}
	var seen_actuators := {}
	for entry in _inventory:
		if not _check(entry is Dictionary and entry.has_all(["name", "lower", "upper"]), "invalid inventory entry"):
			return false
		var joint_name: String = entry["name"]
		var low: float = entry["lower"]
		var high: float = entry["upper"]
		if not _check(not seen_names.has(joint_name), "duplicate inventory joint " + joint_name):
			return false
		if not _check(is_finite(low) and is_finite(high) and high - low > 0.06, "invalid limits for " + joint_name):
			return false
		var joint: int = _world.joint_id(joint_name)
		var actuator_name := joint_name + "_position"
		var actuator: int = _world.actuator_id(actuator_name)
		if not _check(joint >= 0 and joint < JOINT_COUNT and not seen_joints.has(joint), "missing/duplicate joint " + joint_name):
			return false
		if not _check(actuator >= 0 and actuator < JOINT_COUNT and not seen_actuators.has(actuator), "missing/duplicate actuator " + actuator_name):
			return false
		if not _check(_world.joint_name(joint) == joint_name and _world.actuator_name(actuator) == actuator_name, "name round-trip failed for " + joint_name):
			return false
		seen_names[joint_name] = true
		seen_joints[joint] = true
		seen_actuators[actuator] = true
		_joint_ids.append(joint)
		_actuator_ids.append(actuator)
		var base := clampf(0.0, low + 0.03, high - 0.03)
		_base_qpos[joint] = base
		_base_ctrl[actuator] = base
		_lower[joint] = low
		_upper[joint] = high
	for entry_index in range(JOINT_COUNT):
		for sign_value in [1.0, -1.0]:
			var target_qpos := _base_qpos.duplicate()
			var target_ctrl := _base_ctrl.duplicate()
			target_qpos[_joint_ids[entry_index]] += sign_value * OFFSET
			target_ctrl[_actuator_ids[entry_index]] += sign_value * OFFSET
			var label: String = "%s %+.2f scalar" % [_inventory[entry_index]["name"], sign_value * OFFSET]
			if not _reset_trial(label):
				return false
			if not _check(_world.set_ctrl(_actuator_ids[entry_index], target_ctrl[_actuator_ids[entry_index]]), label + ": scalar write failed"):
				return false
			if not _check(absf(_world.get_ctrl(_actuator_ids[entry_index]) - target_ctrl[_actuator_ids[entry_index]]) < 1e-12, label + ": scalar read mismatch"):
				return false
			if not _settle(target_qpos, target_ctrl, label):
				return false
	for sign_value in [1.0, -1.0]:
		var target_qpos := _base_qpos.duplicate()
		var target_ctrl := _base_ctrl.duplicate()
		for entry_index in range(JOINT_COUNT):
			var delta: float = sign_value * OFFSET * (1.0 if entry_index % 2 == 0 else -1.0)
			target_qpos[_joint_ids[entry_index]] += delta
			target_ctrl[_actuator_ids[entry_index]] += delta
		var label := "combined alternating %+.0f batch" % sign_value
		if not _reset_trial(label):
			return false
		if not _check(_world.set_ctrl_array(target_ctrl), label + ": batch write failed"):
			return false
		if not _settle(target_qpos, target_ctrl, label):
			return false
	return _check(_trials == JOINT_COUNT * 2 + 2, "not all bounded trials ran")


func _reset_trial(label: String) -> bool:
	_world.reset()
	var zero_velocity := PackedFloat64Array()
	zero_velocity.resize(JOINT_COUNT)
	if not _check(_world.set_qpos(_base_qpos), label + ": set_qpos failed"):
		return false
	if not _check(_world.set_qvel(zero_velocity), label + ": set_qvel failed"):
		return false
	if not _check(_world.set_ctrl_array(_base_ctrl), label + ": base batch controls failed"):
		return false
	_world.forward()
	if not _check(absf(_world.get_time()) < 1e-12, label + ": reset did not reset clock"):
		return false
	return _check_state(label)


func _check_controls(expected: PackedFloat64Array, label: String) -> bool:
	var actual: PackedFloat64Array = _world.get_ctrl_array()
	if not _check(actual.size() == JOINT_COUNT, label + ": wrong control array size"):
		return false
	for index in range(JOINT_COUNT):
		if not _check(is_finite(actual[index]) and absf(actual[index] - expected[index]) < 1e-12, "%s: control mismatch at %d" % [label, index]):
			return false
	return true


func _check_state(label: String) -> bool:
	var qpos: PackedFloat64Array = _world.get_qpos()
	var qvel: PackedFloat64Array = _world.get_qvel()
	if not _check(qpos.size() == JOINT_COUNT and qvel.size() == JOINT_COUNT, label + ": wrong state dimensions"):
		return false
	for index in range(JOINT_COUNT):
		if not _check(is_finite(qpos[index]) and is_finite(qvel[index]), "%s: nonfinite state at %d" % [label, index]):
			return false
		if not _check(qpos[index] >= _lower[index] - 1e-6 and qpos[index] <= _upper[index] + 1e-6, "%s: joint %d left its limits" % [label, index]):
			return false
	if not _check(is_finite(_world.get_time()), label + ": nonfinite clock"):
		return false
	if not _check(not _world.has_warnings() and _world.get_warnings().is_empty(), label + ": MuJoCo warnings: " + str(_world.get_warnings())):
		return false
	return _check(_world.get_ncon() == 0, label + ": contact-free fixture produced contacts")


func _settle(target_qpos: PackedFloat64Array, target_ctrl: PackedFloat64Array, label: String) -> bool:
	if not _check_controls(target_ctrl, label):
		return false
	for unused in range(STEPS / STEP_CHUNK):
		if not _check(_world.step(STEP_CHUNK), label + ": step failed"):
			return false
		_steps += STEP_CHUNK
		if not _check_state(label):
			return false
	_world.forward()
	if not _check_state(label) or not _check_controls(target_ctrl, label):
		return false
	if not _check(absf(_world.get_time() - STEPS * _world.get_timestep()) < 1e-8, label + ": simulated time mismatch"):
		return false
	var actual: PackedFloat64Array = _world.get_qpos()
	for index in range(JOINT_COUNT):
		var error := absf(actual[index] - target_qpos[index])
		_max_error = maxf(_max_error, error)
		if not _check(error <= TOLERANCE, "%s: joint %d error %.9f exceeds %.3f" % [label, index, error, TOLERANCE]):
			return false
	_trials += 1
	return true
