#include "mj_physics_server.h"
namespace godot {
// Unsupported extension entry points fail explicitly, once per feature.
RID MjPhysicsServer3D::_separation_ray_shape_create() { mj_unsupported("_separation_ray_shape_create"); return {}; }
RID MjPhysicsServer3D::_convex_polygon_shape_create() { mj_unsupported("_convex_polygon_shape_create"); return {}; }
RID MjPhysicsServer3D::_concave_polygon_shape_create() { mj_unsupported("_concave_polygon_shape_create"); return {}; }
RID MjPhysicsServer3D::_heightmap_shape_create() { mj_unsupported("_heightmap_shape_create"); return {}; }
RID MjPhysicsServer3D::_custom_shape_create() { mj_unsupported("_custom_shape_create"); return {}; }
void MjPhysicsServer3D::_space_set_param(const RID &p_space, PhysicsServer3D::SpaceParameter p_param, float p_value) { mj_unsupported("_space_set_param"); }
float MjPhysicsServer3D::_space_get_param(const RID &p_space, PhysicsServer3D::SpaceParameter p_param) const { mj_unsupported("_space_get_param"); return {}; }
void MjPhysicsServer3D::_body_set_user_flags(const RID &p_body, uint32_t p_flags) { mj_unsupported("_body_set_user_flags"); }
uint32_t MjPhysicsServer3D::_body_get_user_flags(const RID &p_body) const { mj_unsupported("_body_get_user_flags"); return {}; }
void MjPhysicsServer3D::_body_set_contacts_reported_depth_threshold(const RID &p_body, float p_threshold) { mj_unsupported("_body_set_contacts_reported_depth_threshold"); }
float MjPhysicsServer3D::_body_get_contacts_reported_depth_threshold(const RID &p_body) const { mj_unsupported("_body_get_contacts_reported_depth_threshold"); return {}; }
bool MjPhysicsServer3D::_body_test_motion(const RID &p_body, const Transform3D &p_from, const Vector3 &p_motion, float p_margin, int32_t p_max_collisions, bool p_collide_separation_ray, bool p_recovery_as_collision, PhysicsServer3DExtensionMotionResult *p_result) const { mj_unsupported("_body_test_motion"); return {}; }
RID MjPhysicsServer3D::_soft_body_create() { mj_unsupported("_soft_body_create"); return {}; }
void MjPhysicsServer3D::_soft_body_update_rendering_server(const RID &p_body, PhysicsServer3DRenderingServerHandler *p_rendering_server_handler) { mj_unsupported("_soft_body_update_rendering_server"); }
void MjPhysicsServer3D::_soft_body_set_space(const RID &p_body, const RID &p_space) { mj_unsupported("_soft_body_set_space"); }
RID MjPhysicsServer3D::_soft_body_get_space(const RID &p_body) const { mj_unsupported("_soft_body_get_space"); return {}; }
void MjPhysicsServer3D::_soft_body_set_ray_pickable(const RID &p_body, bool p_enable) { mj_unsupported("_soft_body_set_ray_pickable"); }
void MjPhysicsServer3D::_soft_body_set_collision_layer(const RID &p_body, uint32_t p_layer) { mj_unsupported("_soft_body_set_collision_layer"); }
uint32_t MjPhysicsServer3D::_soft_body_get_collision_layer(const RID &p_body) const { mj_unsupported("_soft_body_get_collision_layer"); return {}; }
void MjPhysicsServer3D::_soft_body_set_collision_mask(const RID &p_body, uint32_t p_mask) { mj_unsupported("_soft_body_set_collision_mask"); }
uint32_t MjPhysicsServer3D::_soft_body_get_collision_mask(const RID &p_body) const { mj_unsupported("_soft_body_get_collision_mask"); return {}; }
void MjPhysicsServer3D::_soft_body_add_collision_exception(const RID &p_body, const RID &p_body_b) { mj_unsupported("_soft_body_add_collision_exception"); }
void MjPhysicsServer3D::_soft_body_remove_collision_exception(const RID &p_body, const RID &p_body_b) { mj_unsupported("_soft_body_remove_collision_exception"); }
TypedArray<RID> MjPhysicsServer3D::_soft_body_get_collision_exceptions(const RID &p_body) const { mj_unsupported("_soft_body_get_collision_exceptions"); return {}; }
void MjPhysicsServer3D::_soft_body_set_state(const RID &p_body, PhysicsServer3D::BodyState p_state, const Variant &p_variant) { mj_unsupported("_soft_body_set_state"); }
Variant MjPhysicsServer3D::_soft_body_get_state(const RID &p_body, PhysicsServer3D::BodyState p_state) const { mj_unsupported("_soft_body_get_state"); return {}; }
void MjPhysicsServer3D::_soft_body_set_transform(const RID &p_body, const Transform3D &p_transform) { mj_unsupported("_soft_body_set_transform"); }
void MjPhysicsServer3D::_soft_body_set_simulation_precision(const RID &p_body, int32_t p_simulation_precision) { mj_unsupported("_soft_body_set_simulation_precision"); }
int32_t MjPhysicsServer3D::_soft_body_get_simulation_precision(const RID &p_body) const { mj_unsupported("_soft_body_get_simulation_precision"); return {}; }
void MjPhysicsServer3D::_soft_body_set_total_mass(const RID &p_body, float p_total_mass) { mj_unsupported("_soft_body_set_total_mass"); }
float MjPhysicsServer3D::_soft_body_get_total_mass(const RID &p_body) const { mj_unsupported("_soft_body_get_total_mass"); return {}; }
void MjPhysicsServer3D::_soft_body_set_linear_stiffness(const RID &p_body, float p_linear_stiffness) { mj_unsupported("_soft_body_set_linear_stiffness"); }
float MjPhysicsServer3D::_soft_body_get_linear_stiffness(const RID &p_body) const { mj_unsupported("_soft_body_get_linear_stiffness"); return {}; }
void MjPhysicsServer3D::_soft_body_set_shrinking_factor(const RID &p_body, float p_shrinking_factor) { mj_unsupported("_soft_body_set_shrinking_factor"); }
float MjPhysicsServer3D::_soft_body_get_shrinking_factor(const RID &p_body) const { mj_unsupported("_soft_body_get_shrinking_factor"); return {}; }
void MjPhysicsServer3D::_soft_body_set_pressure_coefficient(const RID &p_body, float p_pressure_coefficient) { mj_unsupported("_soft_body_set_pressure_coefficient"); }
float MjPhysicsServer3D::_soft_body_get_pressure_coefficient(const RID &p_body) const { mj_unsupported("_soft_body_get_pressure_coefficient"); return {}; }
void MjPhysicsServer3D::_soft_body_set_damping_coefficient(const RID &p_body, float p_damping_coefficient) { mj_unsupported("_soft_body_set_damping_coefficient"); }
float MjPhysicsServer3D::_soft_body_get_damping_coefficient(const RID &p_body) const { mj_unsupported("_soft_body_get_damping_coefficient"); return {}; }
void MjPhysicsServer3D::_soft_body_set_drag_coefficient(const RID &p_body, float p_drag_coefficient) { mj_unsupported("_soft_body_set_drag_coefficient"); }
float MjPhysicsServer3D::_soft_body_get_drag_coefficient(const RID &p_body) const { mj_unsupported("_soft_body_get_drag_coefficient"); return {}; }
void MjPhysicsServer3D::_soft_body_set_mesh(const RID &p_body, const RID &p_mesh) { mj_unsupported("_soft_body_set_mesh"); }
AABB MjPhysicsServer3D::_soft_body_get_bounds(const RID &p_body) const { mj_unsupported("_soft_body_get_bounds"); return {}; }
void MjPhysicsServer3D::_soft_body_move_point(const RID &p_body, int32_t p_point_index, const Vector3 &p_global_position) { mj_unsupported("_soft_body_move_point"); }
Vector3 MjPhysicsServer3D::_soft_body_get_point_global_position(const RID &p_body, int32_t p_point_index) const { mj_unsupported("_soft_body_get_point_global_position"); return {}; }
void MjPhysicsServer3D::_soft_body_remove_all_pinned_points(const RID &p_body) { mj_unsupported("_soft_body_remove_all_pinned_points"); }
void MjPhysicsServer3D::_soft_body_pin_point(const RID &p_body, int32_t p_point_index, bool p_pin) { mj_unsupported("_soft_body_pin_point"); }
bool MjPhysicsServer3D::_soft_body_is_point_pinned(const RID &p_body, int32_t p_point_index) const { mj_unsupported("_soft_body_is_point_pinned"); return {}; }
void MjPhysicsServer3D::_soft_body_apply_point_impulse(const RID &p_body, int32_t p_point_index, const Vector3 &p_impulse) { mj_unsupported("_soft_body_apply_point_impulse"); }
void MjPhysicsServer3D::_soft_body_apply_point_force(const RID &p_body, int32_t p_point_index, const Vector3 &p_force) { mj_unsupported("_soft_body_apply_point_force"); }
void MjPhysicsServer3D::_soft_body_apply_central_impulse(const RID &p_body, const Vector3 &p_impulse) { mj_unsupported("_soft_body_apply_central_impulse"); }
void MjPhysicsServer3D::_soft_body_apply_central_force(const RID &p_body, const Vector3 &p_force) { mj_unsupported("_soft_body_apply_central_force"); }
RID MjPhysicsServer3D::_joint_create() { mj_unsupported("_joint_create"); return {}; }
void MjPhysicsServer3D::_joint_clear(const RID &p_joint) { mj_unsupported("_joint_clear"); }
void MjPhysicsServer3D::_joint_make_pin(const RID &p_joint, const RID &p_body_A, const Vector3 &p_local_A, const RID &p_body_B, const Vector3 &p_local_B) { mj_unsupported("_joint_make_pin"); }
void MjPhysicsServer3D::_pin_joint_set_param(const RID &p_joint, PhysicsServer3D::PinJointParam p_param, float p_value) { mj_unsupported("_pin_joint_set_param"); }
float MjPhysicsServer3D::_pin_joint_get_param(const RID &p_joint, PhysicsServer3D::PinJointParam p_param) const { mj_unsupported("_pin_joint_get_param"); return {}; }
void MjPhysicsServer3D::_pin_joint_set_local_a(const RID &p_joint, const Vector3 &p_local_A) { mj_unsupported("_pin_joint_set_local_a"); }
Vector3 MjPhysicsServer3D::_pin_joint_get_local_a(const RID &p_joint) const { mj_unsupported("_pin_joint_get_local_a"); return {}; }
void MjPhysicsServer3D::_pin_joint_set_local_b(const RID &p_joint, const Vector3 &p_local_B) { mj_unsupported("_pin_joint_set_local_b"); }
Vector3 MjPhysicsServer3D::_pin_joint_get_local_b(const RID &p_joint) const { mj_unsupported("_pin_joint_get_local_b"); return {}; }
void MjPhysicsServer3D::_joint_make_hinge(const RID &p_joint, const RID &p_body_A, const Transform3D &p_hinge_A, const RID &p_body_B, const Transform3D &p_hinge_B) { mj_unsupported("_joint_make_hinge"); }
void MjPhysicsServer3D::_joint_make_hinge_simple(const RID &p_joint, const RID &p_body_A, const Vector3 &p_pivot_A, const Vector3 &p_axis_A, const RID &p_body_B, const Vector3 &p_pivot_B, const Vector3 &p_axis_B) { mj_unsupported("_joint_make_hinge_simple"); }
void MjPhysicsServer3D::_hinge_joint_set_param(const RID &p_joint, PhysicsServer3D::HingeJointParam p_param, float p_value) { mj_unsupported("_hinge_joint_set_param"); }
float MjPhysicsServer3D::_hinge_joint_get_param(const RID &p_joint, PhysicsServer3D::HingeJointParam p_param) const { mj_unsupported("_hinge_joint_get_param"); return {}; }
void MjPhysicsServer3D::_hinge_joint_set_flag(const RID &p_joint, PhysicsServer3D::HingeJointFlag p_flag, bool p_enabled) { mj_unsupported("_hinge_joint_set_flag"); }
bool MjPhysicsServer3D::_hinge_joint_get_flag(const RID &p_joint, PhysicsServer3D::HingeJointFlag p_flag) const { mj_unsupported("_hinge_joint_get_flag"); return {}; }
void MjPhysicsServer3D::_joint_make_slider(const RID &p_joint, const RID &p_body_A, const Transform3D &p_local_ref_A, const RID &p_body_B, const Transform3D &p_local_ref_B) { mj_unsupported("_joint_make_slider"); }
void MjPhysicsServer3D::_slider_joint_set_param(const RID &p_joint, PhysicsServer3D::SliderJointParam p_param, float p_value) { mj_unsupported("_slider_joint_set_param"); }
float MjPhysicsServer3D::_slider_joint_get_param(const RID &p_joint, PhysicsServer3D::SliderJointParam p_param) const { mj_unsupported("_slider_joint_get_param"); return {}; }
void MjPhysicsServer3D::_joint_make_cone_twist(const RID &p_joint, const RID &p_body_A, const Transform3D &p_local_ref_A, const RID &p_body_B, const Transform3D &p_local_ref_B) { mj_unsupported("_joint_make_cone_twist"); }
void MjPhysicsServer3D::_cone_twist_joint_set_param(const RID &p_joint, PhysicsServer3D::ConeTwistJointParam p_param, float p_value) { mj_unsupported("_cone_twist_joint_set_param"); }
float MjPhysicsServer3D::_cone_twist_joint_get_param(const RID &p_joint, PhysicsServer3D::ConeTwistJointParam p_param) const { mj_unsupported("_cone_twist_joint_get_param"); return {}; }
void MjPhysicsServer3D::_joint_make_generic_6dof(const RID &p_joint, const RID &p_body_A, const Transform3D &p_local_ref_A, const RID &p_body_B, const Transform3D &p_local_ref_B) { mj_unsupported("_joint_make_generic_6dof"); }
void MjPhysicsServer3D::_generic_6dof_joint_set_param(const RID &p_joint, Vector3::Axis p_axis, PhysicsServer3D::G6DOFJointAxisParam p_param, float p_value) { mj_unsupported("_generic_6dof_joint_set_param"); }
float MjPhysicsServer3D::_generic_6dof_joint_get_param(const RID &p_joint, Vector3::Axis p_axis, PhysicsServer3D::G6DOFJointAxisParam p_param) const { mj_unsupported("_generic_6dof_joint_get_param"); return {}; }
void MjPhysicsServer3D::_generic_6dof_joint_set_flag(const RID &p_joint, Vector3::Axis p_axis, PhysicsServer3D::G6DOFJointAxisFlag p_flag, bool p_enable) { mj_unsupported("_generic_6dof_joint_set_flag"); }
bool MjPhysicsServer3D::_generic_6dof_joint_get_flag(const RID &p_joint, Vector3::Axis p_axis, PhysicsServer3D::G6DOFJointAxisFlag p_flag) const { mj_unsupported("_generic_6dof_joint_get_flag"); return {}; }
PhysicsServer3D::JointType MjPhysicsServer3D::_joint_get_type(const RID &p_joint) const { mj_unsupported("_joint_get_type"); return {}; }
void MjPhysicsServer3D::_joint_set_solver_priority(const RID &p_joint, int32_t p_priority) { mj_unsupported("_joint_set_solver_priority"); }
int32_t MjPhysicsServer3D::_joint_get_solver_priority(const RID &p_joint) const { mj_unsupported("_joint_get_solver_priority"); return {}; }
void MjPhysicsServer3D::_joint_disable_collisions_between_bodies(const RID &p_joint, bool p_disable) { mj_unsupported("_joint_disable_collisions_between_bodies"); }
bool MjPhysicsServer3D::_joint_is_disabled_collisions_between_bodies(const RID &p_joint) const { mj_unsupported("_joint_is_disabled_collisions_between_bodies"); return {}; }
}
