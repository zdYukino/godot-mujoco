extends "res://passive_gui.gd"
var motor_enabled:=true
var limits_enabled:=true
var target_velocity:=1.5
func make_pin():
 super.make_pin()
 pin_node.set_param(HingeJoint3D.PARAM_LIMIT_LOWER,-.6)
 pin_node.set_param(HingeJoint3D.PARAM_LIMIT_UPPER,.6)
 pin_node.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY,target_velocity)
 pin_node.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE,.5)
 pin_node.set_flag(HingeJoint3D.FLAG_USE_LIMIT,limits_enabled)
 pin_node.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR,motor_enabled)
func _handle_input(event):
 if not event is InputEventKey or not event.pressed or event.echo:return
 match event.physical_keycode:
  KEY_M:
   motor_enabled=not motor_enabled
   if is_instance_valid(pin_node):pin_node.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR,motor_enabled)
  KEY_L:
   limits_enabled=not limits_enabled
   if is_instance_valid(pin_node):pin_node.set_flag(HingeJoint3D.FLAG_USE_LIMIT,limits_enabled)
  KEY_V:
   target_velocity=-target_velocity
   if is_instance_valid(pin_node):pin_node.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY,target_velocity)
  _:super._handle_input(event)
func _process(delta):
 super._process(delta)
 if is_instance_valid(status):
  status.text=status.text.replace("Passive native Hinge: Z-axis rotation; no motor or limits","Driven Hinge: bounded independent pair")
  status.text+="\nM motor: %s | L limits ±0.6rad: %s | V reverse target: %.2f rad/s\nActual speed %.3f rad/s"%[motor_enabled,limits_enabled,target_velocity,bob.angular_velocity.z]
 return false
