#pragma once
#include <godot_cpp/classes/physics_server3d_rendering_server_handler.hpp>
#include <godot_cpp/classes/physics_server3d_extension.hpp>
#include <godot_cpp/classes/physics_direct_body_state3d_extension.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d_extension.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/plane.hpp>
#include <godot_cpp/templates/rid_owner.hpp>
#include <mujoco/mujoco.h>
#include <map>
#include <memory>
#include <vector>
#include <set>
#include <mutex>
#include <deque>
#include <functional>
#include <tuple>
namespace godot {
class MjPhysicsServer3D;
class MjDirectBodyState;
class MjDirectSpaceState;
struct MjAreaScratch;
struct MjNativeJoint { RID rid,a,b; Vector3 anchor_a,anchor_b; bool pin=false,disable_collisions=true; };
struct MjShape { RID rid; PhysicsServer3D::ShapeType type; Variant data; float margin=0.04f; };
struct MjShapeInstance { RID shape; Transform3D transform; bool disabled=false; };
struct MjImported {
 RID rid; String label; Transform3D pose; mjSpec *spec=nullptr;
 bool whole_model=false; Dictionary initial; uint64_t property_revision=0;
 std::string prefix;
 ~MjImported() { if(spec) mj_deleteSpec(spec); }
};
// One solved manifold point in Godot world coordinates; impulse covers one substep.
struct MjContact {
 RID collider; uint64_t object_id=0; int local_shape=-1, collider_shape=-1;
 Vector3 position, normal, impulse, local_velocity, collider_velocity;
};
struct MjBody {
 int max_contacts=0; std::vector<MjContact> contacts;
 RID rid, space; bool heightfield=false; uint64_t object_id=0; PhysicsServer3D::BodyMode mode=PhysicsServer3D::BODY_MODE_RIGID;
 // Godot velocities are world-space; linear velocity is at the center of mass.
 Transform3D transform; Vector3 linear_velocity, angular_velocity, force, torque, constant_force, constant_torque;
 std::vector<MjShapeInstance> shapes; std::map<int, Variant> params;
 uint32_t layer=1, mask=1; bool ray_pickable=true, sleeping=false, omit_integration=false;
 bool callback_pending=false, sync_pending=false; double integration_step=0;
 Callable sync_callback, integration_callback; Variant integration_userdata;
 MjDirectBodyState *direct=nullptr; int mj_body=-1; double mass=1; double gravity_scale=1;
 std::set<uint64_t> exceptions;
};
// Value-only shape pair identity; never retain pointers across user callbacks.
struct MjAreaPair {
 RID rid; uint64_t object_id=0; int other_shape=0, self_shape=0; bool area=false;
 bool operator<(const MjAreaPair &b) const {return std::tie(area,rid,object_id,other_shape,self_shape)<std::tie(b.area,b.rid,b.object_id,b.other_shape,b.self_shape);}
};
struct MjArea {
 RID rid, space; uint64_t object_id=0; Transform3D transform;
 uint32_t layer=1, mask=1; bool monitorable=true, ray_pickable=true;
 std::vector<MjShapeInstance> shapes; std::map<int,Variant> params;
 Callable body_callback, area_callback; std::set<MjAreaPair> reported;
};
struct MjSpace {
 bool paused=false; uint64_t revision=0; String last_error;
 Dictionary born_state, checkpoint; int single_steps=0; bool skip_tick=false;
 bool authored_options=false; mjOption options{};
 std::map<uint64_t,std::unique_ptr<MjImported>> imported;
 RID rid; bool active=false, dirty=true; mjModel *model=nullptr; mjData *data=nullptr;
 MjDirectSpaceState *direct=nullptr; Vector3 gravity_direction=Vector3(0,-1,0); double gravity=9.8;
 double linear_damp=0.1, angular_damp=0.1, accumulator=0; std::map<int,Variant> params;
 std::vector<std::pair<RID,int>> geom_owners;
 ~MjSpace();
};
// One right-handed convention shared by poses, velocities, forces and queries.
// Godot Y-up -> MuJoCo Z-up: (x,y,z) -> (x,-z,y).
Vector3 mj_to_godot(const Vector3 &v);
Vector3 godot_to_mj(const Vector3 &v);
Basis mj_to_godot(const Basis &b);
Basis godot_to_mj(const Basis &b);
void mj_unsupported(const char *feature);
class MjPhysicsServer3D : public PhysicsServer3DExtension {
 GDCLASS(MjPhysicsServer3D, PhysicsServer3DExtension)
protected:
 static void _bind_methods();
public:
 bool scene_pause(const RID &space, bool paused);
 RID scene_import_g1(const RID &space, const String &path, const String &label, const Transform3D &pose);
 RID scene_add_box(const RID &space, const String &label, const Transform3D &pose, const Vector3 &size, double mass);
 bool scene_remove(const RID &space, const RID &object);
 Dictionary scene_info(const RID &space) const;
 Dictionary scene_state(const RID &space, const RID &object) const;
 Array scene_geometry(const RID &space, const RID &object) const;
 bool scene_set_control(const RID &space, const RID &object, const String &joint, double target);
 RID scene_insert(MjSpace &space, mjSpec *spec, const String &label, const Transform3D &pose, bool whole_model=false, const Dictionary &initial=Dictionary());
 bool scene_configure_model(const RID &space, const Dictionary &snapshot, const String &directory);
 RID scene_load_model(const RID &space, const Dictionary &snapshot, const String &directory, const String &label, const Transform3D &pose);
 bool scene_set_actuator(const RID &space, const RID &object, const String &name, double value);
 bool scene_release_model(const RID &space, const RID &object);
 int64_t scene_request_model_edit(const RID &space, const RID &object, const Dictionary &snapshot, const String &directory, int64_t expected_revision);
 int64_t scene_request_preset(const RID &space,const RID &object,const Dictionary &preset,int64_t revision);
 bool scene_cancel_preset(int64_t request);
 Dictionary scene_edit_result(int64_t request);
 void scene_cancel_model_edit(int64_t request);
 void process_model_edits();
 int64_t scene_request_world_command(const RID &space,const String &command,int count);
 Dictionary scene_world_command_result(int64_t request);
 void scene_cancel_world_command(int64_t request);
 void process_world_commands();
 int64_t scene_request_heightfield(const RID &space,const RID &body,const Dictionary &design,uint64_t owner,int64_t revision);
 Dictionary scene_heightfield_result(int64_t request);
 void scene_cancel_heightfield(int64_t request);
 void process_heightfields();
 struct HeightfieldEdit {int64_t request,revision; RID space,body; Dictionary design; uint64_t owner;};
 std::deque<HeightfieldEdit> heightfield_edits;
 std::map<int64_t,Dictionary> heightfield_results;
 std::map<uint64_t,int64_t> heightfield_revisions;
 void remember_initial_state(MjSpace &space);
 struct WorldCommand {int64_t request;RID space;String command;int count;};
 std::deque<WorldCommand> world_commands;
 std::map<int64_t,Dictionary> world_command_results;
 struct ModelEdit {int64_t request, expected_revision; RID space, object; Dictionary snapshot; String directory; bool preset=false;};
 std::mutex edits_mutex;
 std::deque<ModelEdit> model_edits;
 std::map<int64_t,Dictionary> edit_results;
 int64_t next_edit_request=1;

 std::shared_ptr<MjAreaScratch> area_scratch;
 std::map<uint64_t,std::unique_ptr<MjArea>> areas;
 std::deque<std::function<void()>> area_commands;
 bool draining_area_commands=false;
 MjArea *area(const RID &rid) const;
 void flush_area_queries();
 void retire_area_pairs(const RID &rid, int from_shape=-1);
 void drain_area_commands();
 std::map<uint64_t,MjNativeJoint> native_joints;
 bool native_joint_active(const MjNativeJoint &joint,const RID &space) const;
 bool native_joint_collision_disabled(const RID &a,const RID &b) const;
 void detach_native_joints(const RID &body);
 bool commit_native_joint(const MjNativeJoint &joint);
 std::set<uint64_t> pending_free;
 RID_Owner<int> handles;
 std::map<uint64_t,std::unique_ptr<MjShape>> shapes;
 std::map<uint64_t,std::unique_ptr<MjBody>> bodies;
 std::map<uint64_t,std::unique_ptr<MjSpace>> spaces;
 bool active=true, flushing=false; float last_step=1.0f/60;
 MjBody *body(const RID &rid) const;
 MjSpace *space(const RID &rid) const;
 MjShape *shape(const RID &rid) const;
 RID make_shape(ShapeType type, const Variant &data);
 void dirty(const RID &space);
 bool rebuild(MjSpace &space, const Dictionary &control_overrides=Dictionary(), bool validate_dynamics=false);
 void write_body(MjBody &body);
 void read_body(MjBody &body);
 void collect_contacts(MjSpace &space);
 ~MjPhysicsServer3D();
 RID _world_boundary_shape_create() override;
 RID _separation_ray_shape_create() override;
 RID _sphere_shape_create() override;
 RID _box_shape_create() override;
 RID _capsule_shape_create() override;
 RID _cylinder_shape_create() override;
 RID _convex_polygon_shape_create() override;
 RID _concave_polygon_shape_create() override;
 RID _heightmap_shape_create() override;
 RID _custom_shape_create() override;
 void _shape_set_data(const RID &p_shape, const Variant &p_data) override;
 void _shape_set_custom_solver_bias(const RID &p_shape, float p_bias) override;
 void _shape_set_margin(const RID &p_shape, float p_margin) override;
 float _shape_get_margin(const RID &p_shape) const override;
 PhysicsServer3D::ShapeType _shape_get_type(const RID &p_shape) const override;
 Variant _shape_get_data(const RID &p_shape) const override;
 float _shape_get_custom_solver_bias(const RID &p_shape) const override;
 RID _space_create() override;
 void _space_set_active(const RID &p_space, bool p_active) override;
 bool _space_is_active(const RID &p_space) const override;
 void _space_set_param(const RID &p_space, PhysicsServer3D::SpaceParameter p_param, float p_value) override;
 float _space_get_param(const RID &p_space, PhysicsServer3D::SpaceParameter p_param) const override;
 PhysicsDirectSpaceState3D *_space_get_direct_state(const RID &p_space) override;
 void _space_set_debug_contacts(const RID &p_space, int32_t p_max_contacts) override;
 PackedVector3Array _space_get_contacts(const RID &p_space) const override;
 int32_t _space_get_contact_count(const RID &p_space) const override;
 RID _area_create() override;
 void _area_set_space(const RID &p_area, const RID &p_space) override;
 RID _area_get_space(const RID &p_area) const override;
 void _area_add_shape(const RID &p_area, const RID &p_shape, const Transform3D &p_transform, bool p_disabled) override;
 void _area_set_shape(const RID &p_area, int32_t p_shape_idx, const RID &p_shape) override;
 void _area_set_shape_transform(const RID &p_area, int32_t p_shape_idx, const Transform3D &p_transform) override;
 void _area_set_shape_disabled(const RID &p_area, int32_t p_shape_idx, bool p_disabled) override;
 int32_t _area_get_shape_count(const RID &p_area) const override;
 RID _area_get_shape(const RID &p_area, int32_t p_shape_idx) const override;
 Transform3D _area_get_shape_transform(const RID &p_area, int32_t p_shape_idx) const override;
 void _area_remove_shape(const RID &p_area, int32_t p_shape_idx) override;
 void _area_clear_shapes(const RID &p_area) override;
 void _area_attach_object_instance_id(const RID &p_area, uint64_t p_id) override;
 uint64_t _area_get_object_instance_id(const RID &p_area) const override;
 void _area_set_param(const RID &p_area, PhysicsServer3D::AreaParameter p_param, const Variant &p_value) override;
 void _area_set_transform(const RID &p_area, const Transform3D &p_transform) override;
 Variant _area_get_param(const RID &p_area, PhysicsServer3D::AreaParameter p_param) const override;
 Transform3D _area_get_transform(const RID &p_area) const override;
 void _area_set_collision_layer(const RID &p_area, uint32_t p_layer) override;
 uint32_t _area_get_collision_layer(const RID &p_area) const override;
 void _area_set_collision_mask(const RID &p_area, uint32_t p_mask) override;
 uint32_t _area_get_collision_mask(const RID &p_area) const override;
 void _area_set_monitorable(const RID &p_area, bool p_monitorable) override;
 void _area_set_ray_pickable(const RID &p_area, bool p_enable) override;
 void _area_set_monitor_callback(const RID &p_area, const Callable &p_callback) override;
 void _area_set_area_monitor_callback(const RID &p_area, const Callable &p_callback) override;
 RID _body_create() override;
 void _body_set_space(const RID &p_body, const RID &p_space) override;
 RID _body_get_space(const RID &p_body) const override;
 void _body_set_mode(const RID &p_body, PhysicsServer3D::BodyMode p_mode) override;
 PhysicsServer3D::BodyMode _body_get_mode(const RID &p_body) const override;
 void _body_add_shape(const RID &p_body, const RID &p_shape, const Transform3D &p_transform, bool p_disabled) override;
 void _body_set_shape(const RID &p_body, int32_t p_shape_idx, const RID &p_shape) override;
 void _body_set_shape_transform(const RID &p_body, int32_t p_shape_idx, const Transform3D &p_transform) override;
 void _body_set_shape_disabled(const RID &p_body, int32_t p_shape_idx, bool p_disabled) override;
 int32_t _body_get_shape_count(const RID &p_body) const override;
 RID _body_get_shape(const RID &p_body, int32_t p_shape_idx) const override;
 Transform3D _body_get_shape_transform(const RID &p_body, int32_t p_shape_idx) const override;
 void _body_remove_shape(const RID &p_body, int32_t p_shape_idx) override;
 void _body_clear_shapes(const RID &p_body) override;
 void _body_attach_object_instance_id(const RID &p_body, uint64_t p_id) override;
 uint64_t _body_get_object_instance_id(const RID &p_body) const override;
 void _body_set_enable_continuous_collision_detection(const RID &p_body, bool p_enable) override;
 bool _body_is_continuous_collision_detection_enabled(const RID &p_body) const override;
 void _body_set_collision_layer(const RID &p_body, uint32_t p_layer) override;
 uint32_t _body_get_collision_layer(const RID &p_body) const override;
 void _body_set_collision_mask(const RID &p_body, uint32_t p_mask) override;
 uint32_t _body_get_collision_mask(const RID &p_body) const override;
 void _body_set_collision_priority(const RID &p_body, float p_priority) override;
 float _body_get_collision_priority(const RID &p_body) const override;
 void _body_set_user_flags(const RID &p_body, uint32_t p_flags) override;
 uint32_t _body_get_user_flags(const RID &p_body) const override;
 void _body_set_param(const RID &p_body, PhysicsServer3D::BodyParameter p_param, const Variant &p_value) override;
 Variant _body_get_param(const RID &p_body, PhysicsServer3D::BodyParameter p_param) const override;
 void _body_reset_mass_properties(const RID &p_body) override;
 void _body_set_state(const RID &p_body, PhysicsServer3D::BodyState p_state, const Variant &p_value) override;
 Variant _body_get_state(const RID &p_body, PhysicsServer3D::BodyState p_state) const override;
 void _body_apply_central_impulse(const RID &p_body, const Vector3 &p_impulse) override;
 void _body_apply_impulse(const RID &p_body, const Vector3 &p_impulse, const Vector3 &p_position) override;
 void _body_apply_torque_impulse(const RID &p_body, const Vector3 &p_impulse) override;
 void _body_apply_central_force(const RID &p_body, const Vector3 &p_force) override;
 void _body_apply_force(const RID &p_body, const Vector3 &p_force, const Vector3 &p_position) override;
 void _body_apply_torque(const RID &p_body, const Vector3 &p_torque) override;
 void _body_add_constant_central_force(const RID &p_body, const Vector3 &p_force) override;
 void _body_add_constant_force(const RID &p_body, const Vector3 &p_force, const Vector3 &p_position) override;
 void _body_add_constant_torque(const RID &p_body, const Vector3 &p_torque) override;
 void _body_set_constant_force(const RID &p_body, const Vector3 &p_force) override;
 Vector3 _body_get_constant_force(const RID &p_body) const override;
 void _body_set_constant_torque(const RID &p_body, const Vector3 &p_torque) override;
 Vector3 _body_get_constant_torque(const RID &p_body) const override;
 void _body_set_axis_velocity(const RID &p_body, const Vector3 &p_axis_velocity) override;
 void _body_set_axis_lock(const RID &p_body, PhysicsServer3D::BodyAxis p_axis, bool p_lock) override;
 bool _body_is_axis_locked(const RID &p_body, PhysicsServer3D::BodyAxis p_axis) const override;
 void _body_add_collision_exception(const RID &p_body, const RID &p_excepted_body) override;
 void _body_remove_collision_exception(const RID &p_body, const RID &p_excepted_body) override;
 TypedArray<RID> _body_get_collision_exceptions(const RID &p_body) const override;
 void _body_set_max_contacts_reported(const RID &p_body, int32_t p_amount) override;
 int32_t _body_get_max_contacts_reported(const RID &p_body) const override;
 void _body_set_contacts_reported_depth_threshold(const RID &p_body, float p_threshold) override;
 float _body_get_contacts_reported_depth_threshold(const RID &p_body) const override;
 void _body_set_omit_force_integration(const RID &p_body, bool p_enable) override;
 bool _body_is_omitting_force_integration(const RID &p_body) const override;
 void _body_set_state_sync_callback(const RID &p_body, const Callable &p_callable) override;
 void _body_set_force_integration_callback(const RID &p_body, const Callable &p_callable, const Variant &p_userdata) override;
 void _body_set_ray_pickable(const RID &p_body, bool p_enable) override;
 bool _body_test_motion(const RID &p_body, const Transform3D &p_from, const Vector3 &p_motion, float p_margin, int32_t p_max_collisions, bool p_collide_separation_ray, bool p_recovery_as_collision, PhysicsServer3DExtensionMotionResult *p_result) const override;
 PhysicsDirectBodyState3D *_body_get_direct_state(const RID &p_body) override;
 RID _soft_body_create() override;
 void _soft_body_update_rendering_server(const RID &p_body, PhysicsServer3DRenderingServerHandler *p_rendering_server_handler) override;
 void _soft_body_set_space(const RID &p_body, const RID &p_space) override;
 RID _soft_body_get_space(const RID &p_body) const override;
 void _soft_body_set_ray_pickable(const RID &p_body, bool p_enable) override;
 void _soft_body_set_collision_layer(const RID &p_body, uint32_t p_layer) override;
 uint32_t _soft_body_get_collision_layer(const RID &p_body) const override;
 void _soft_body_set_collision_mask(const RID &p_body, uint32_t p_mask) override;
 uint32_t _soft_body_get_collision_mask(const RID &p_body) const override;
 void _soft_body_add_collision_exception(const RID &p_body, const RID &p_body_b) override;
 void _soft_body_remove_collision_exception(const RID &p_body, const RID &p_body_b) override;
 TypedArray<RID> _soft_body_get_collision_exceptions(const RID &p_body) const override;
 void _soft_body_set_state(const RID &p_body, PhysicsServer3D::BodyState p_state, const Variant &p_variant) override;
 Variant _soft_body_get_state(const RID &p_body, PhysicsServer3D::BodyState p_state) const override;
 void _soft_body_set_transform(const RID &p_body, const Transform3D &p_transform) override;
 void _soft_body_set_simulation_precision(const RID &p_body, int32_t p_simulation_precision) override;
 int32_t _soft_body_get_simulation_precision(const RID &p_body) const override;
 void _soft_body_set_total_mass(const RID &p_body, float p_total_mass) override;
 float _soft_body_get_total_mass(const RID &p_body) const override;
 void _soft_body_set_linear_stiffness(const RID &p_body, float p_linear_stiffness) override;
 float _soft_body_get_linear_stiffness(const RID &p_body) const override;
 void _soft_body_set_shrinking_factor(const RID &p_body, float p_shrinking_factor) override;
 float _soft_body_get_shrinking_factor(const RID &p_body) const override;
 void _soft_body_set_pressure_coefficient(const RID &p_body, float p_pressure_coefficient) override;
 float _soft_body_get_pressure_coefficient(const RID &p_body) const override;
 void _soft_body_set_damping_coefficient(const RID &p_body, float p_damping_coefficient) override;
 float _soft_body_get_damping_coefficient(const RID &p_body) const override;
 void _soft_body_set_drag_coefficient(const RID &p_body, float p_drag_coefficient) override;
 float _soft_body_get_drag_coefficient(const RID &p_body) const override;
 void _soft_body_set_mesh(const RID &p_body, const RID &p_mesh) override;
 AABB _soft_body_get_bounds(const RID &p_body) const override;
 void _soft_body_move_point(const RID &p_body, int32_t p_point_index, const Vector3 &p_global_position) override;
 Vector3 _soft_body_get_point_global_position(const RID &p_body, int32_t p_point_index) const override;
 void _soft_body_remove_all_pinned_points(const RID &p_body) override;
 void _soft_body_pin_point(const RID &p_body, int32_t p_point_index, bool p_pin) override;
 bool _soft_body_is_point_pinned(const RID &p_body, int32_t p_point_index) const override;
 void _soft_body_apply_point_impulse(const RID &p_body, int32_t p_point_index, const Vector3 &p_impulse) override;
 void _soft_body_apply_point_force(const RID &p_body, int32_t p_point_index, const Vector3 &p_force) override;
 void _soft_body_apply_central_impulse(const RID &p_body, const Vector3 &p_impulse) override;
 void _soft_body_apply_central_force(const RID &p_body, const Vector3 &p_force) override;
 RID _joint_create() override;
 void _joint_clear(const RID &p_joint) override;
 void _joint_make_pin(const RID &p_joint, const RID &p_body_A, const Vector3 &p_local_A, const RID &p_body_B, const Vector3 &p_local_B) override;
 void _pin_joint_set_param(const RID &p_joint, PhysicsServer3D::PinJointParam p_param, float p_value) override;
 float _pin_joint_get_param(const RID &p_joint, PhysicsServer3D::PinJointParam p_param) const override;
 void _pin_joint_set_local_a(const RID &p_joint, const Vector3 &p_local_A) override;
 Vector3 _pin_joint_get_local_a(const RID &p_joint) const override;
 void _pin_joint_set_local_b(const RID &p_joint, const Vector3 &p_local_B) override;
 Vector3 _pin_joint_get_local_b(const RID &p_joint) const override;
 void _joint_make_hinge(const RID &p_joint, const RID &p_body_A, const Transform3D &p_hinge_A, const RID &p_body_B, const Transform3D &p_hinge_B) override;
 void _joint_make_hinge_simple(const RID &p_joint, const RID &p_body_A, const Vector3 &p_pivot_A, const Vector3 &p_axis_A, const RID &p_body_B, const Vector3 &p_pivot_B, const Vector3 &p_axis_B) override;
 void _hinge_joint_set_param(const RID &p_joint, PhysicsServer3D::HingeJointParam p_param, float p_value) override;
 float _hinge_joint_get_param(const RID &p_joint, PhysicsServer3D::HingeJointParam p_param) const override;
 void _hinge_joint_set_flag(const RID &p_joint, PhysicsServer3D::HingeJointFlag p_flag, bool p_enabled) override;
 bool _hinge_joint_get_flag(const RID &p_joint, PhysicsServer3D::HingeJointFlag p_flag) const override;
 void _joint_make_slider(const RID &p_joint, const RID &p_body_A, const Transform3D &p_local_ref_A, const RID &p_body_B, const Transform3D &p_local_ref_B) override;
 void _slider_joint_set_param(const RID &p_joint, PhysicsServer3D::SliderJointParam p_param, float p_value) override;
 float _slider_joint_get_param(const RID &p_joint, PhysicsServer3D::SliderJointParam p_param) const override;
 void _joint_make_cone_twist(const RID &p_joint, const RID &p_body_A, const Transform3D &p_local_ref_A, const RID &p_body_B, const Transform3D &p_local_ref_B) override;
 void _cone_twist_joint_set_param(const RID &p_joint, PhysicsServer3D::ConeTwistJointParam p_param, float p_value) override;
 float _cone_twist_joint_get_param(const RID &p_joint, PhysicsServer3D::ConeTwistJointParam p_param) const override;
 void _joint_make_generic_6dof(const RID &p_joint, const RID &p_body_A, const Transform3D &p_local_ref_A, const RID &p_body_B, const Transform3D &p_local_ref_B) override;
 void _generic_6dof_joint_set_param(const RID &p_joint, Vector3::Axis p_axis, PhysicsServer3D::G6DOFJointAxisParam p_param, float p_value) override;
 float _generic_6dof_joint_get_param(const RID &p_joint, Vector3::Axis p_axis, PhysicsServer3D::G6DOFJointAxisParam p_param) const override;
 void _generic_6dof_joint_set_flag(const RID &p_joint, Vector3::Axis p_axis, PhysicsServer3D::G6DOFJointAxisFlag p_flag, bool p_enable) override;
 bool _generic_6dof_joint_get_flag(const RID &p_joint, Vector3::Axis p_axis, PhysicsServer3D::G6DOFJointAxisFlag p_flag) const override;
 PhysicsServer3D::JointType _joint_get_type(const RID &p_joint) const override;
 void _joint_set_solver_priority(const RID &p_joint, int32_t p_priority) override;
 int32_t _joint_get_solver_priority(const RID &p_joint) const override;
 void _joint_disable_collisions_between_bodies(const RID &p_joint, bool p_disable) override;
 bool _joint_is_disabled_collisions_between_bodies(const RID &p_joint) const override;
 void _free_rid(const RID &p_rid) override;
 void _set_active(bool p_active) override;
 void _init() override;
 void _step(float p_step) override;
 void _sync() override;
 void _flush_queries() override;
 void _end_sync() override;
 void _finish() override;
 bool _is_flushing_queries() const override;
 int32_t _get_process_info(PhysicsServer3D::ProcessInfo p_process_info) override;
};
class MjDirectBodyState : public PhysicsDirectBodyState3DExtension {
 GDCLASS(MjDirectBodyState, PhysicsDirectBodyState3DExtension)
protected:
 static void _bind_methods() {}
public:
 MjPhysicsServer3D *server=nullptr; RID rid;
 Vector3 _get_total_gravity() const override;
 float _get_total_linear_damp() const override;
 float _get_total_angular_damp() const override;
 Vector3 _get_center_of_mass() const override;
 Vector3 _get_center_of_mass_local() const override;
 Basis _get_principal_inertia_axes() const override;
 float _get_inverse_mass() const override;
 Vector3 _get_inverse_inertia() const override;
 Basis _get_inverse_inertia_tensor() const override;
 void _set_linear_velocity(const Vector3 &p_velocity) override;
 Vector3 _get_linear_velocity() const override;
 void _set_angular_velocity(const Vector3 &p_velocity) override;
 Vector3 _get_angular_velocity() const override;
 void _set_transform(const Transform3D &p_transform) override;
 Transform3D _get_transform() const override;
 Vector3 _get_velocity_at_local_position(const Vector3 &p_local_position) const override;
 void _apply_central_impulse(const Vector3 &p_impulse) override;
 void _apply_impulse(const Vector3 &p_impulse, const Vector3 &p_position) override;
 void _apply_torque_impulse(const Vector3 &p_impulse) override;
 void _apply_central_force(const Vector3 &p_force) override;
 void _apply_force(const Vector3 &p_force, const Vector3 &p_position) override;
 void _apply_torque(const Vector3 &p_torque) override;
 void _add_constant_central_force(const Vector3 &p_force) override;
 void _add_constant_force(const Vector3 &p_force, const Vector3 &p_position) override;
 void _add_constant_torque(const Vector3 &p_torque) override;
 void _set_constant_force(const Vector3 &p_force) override;
 Vector3 _get_constant_force() const override;
 void _set_constant_torque(const Vector3 &p_torque) override;
 Vector3 _get_constant_torque() const override;
 void _set_sleep_state(bool p_enabled) override;
 bool _is_sleeping() const override;
 void _set_collision_layer(uint32_t p_layer) override;
 uint32_t _get_collision_layer() const override;
 void _set_collision_mask(uint32_t p_mask) override;
 uint32_t _get_collision_mask() const override;
 int32_t _get_contact_count() const override;
 Vector3 _get_contact_local_position(int32_t p_contact_idx) const override;
 Vector3 _get_contact_local_normal(int32_t p_contact_idx) const override;
 Vector3 _get_contact_impulse(int32_t p_contact_idx) const override;
 int32_t _get_contact_local_shape(int32_t p_contact_idx) const override;
 Vector3 _get_contact_local_velocity_at_position(int32_t p_contact_idx) const override;
 RID _get_contact_collider(int32_t p_contact_idx) const override;
 Vector3 _get_contact_collider_position(int32_t p_contact_idx) const override;
 uint64_t _get_contact_collider_id(int32_t p_contact_idx) const override;
 Object *_get_contact_collider_object(int32_t p_contact_idx) const override;
 int32_t _get_contact_collider_shape(int32_t p_contact_idx) const override;
 Vector3 _get_contact_collider_velocity_at_position(int32_t p_contact_idx) const override;
 float _get_step() const override;
 void _integrate_forces() override;
 PhysicsDirectSpaceState3D *_get_space_state() override;
};
class MjDirectSpaceState : public PhysicsDirectSpaceState3DExtension {
 GDCLASS(MjDirectSpaceState, PhysicsDirectSpaceState3DExtension)
protected:
 static void _bind_methods() {}
public:
 MjPhysicsServer3D *server=nullptr; RID rid;
 bool _intersect_ray(const Vector3 &p_from, const Vector3 &p_to, uint32_t p_collision_mask, bool p_collide_with_bodies, bool p_collide_with_areas, bool p_hit_from_inside, bool p_hit_back_faces, bool p_pick_ray, PhysicsServer3DExtensionRayResult *p_result) override;
 int32_t _intersect_point(const Vector3 &p_position, uint32_t p_collision_mask, bool p_collide_with_bodies, bool p_collide_with_areas, PhysicsServer3DExtensionShapeResult *p_results, int32_t p_max_results) override;
 int32_t _intersect_shape(const RID &p_shape_rid, const Transform3D &p_transform, const Vector3 &p_motion, float p_margin, uint32_t p_collision_mask, bool p_collide_with_bodies, bool p_collide_with_areas, PhysicsServer3DExtensionShapeResult *p_result_count, int32_t p_max_results) override;
 bool _cast_motion(const RID &p_shape_rid, const Transform3D &p_transform, const Vector3 &p_motion, float p_margin, uint32_t p_collision_mask, bool p_collide_with_bodies, bool p_collide_with_areas, float *p_closest_safe, float *p_closest_unsafe, PhysicsServer3DExtensionShapeRestInfo *p_info) override;
 bool _collide_shape(const RID &p_shape_rid, const Transform3D &p_transform, const Vector3 &p_motion, float p_margin, uint32_t p_collision_mask, bool p_collide_with_bodies, bool p_collide_with_areas, void *p_results, int32_t p_max_results, int32_t *p_result_count) override;
 bool _rest_info(const RID &p_shape_rid, const Transform3D &p_transform, const Vector3 &p_motion, float p_margin, uint32_t p_collision_mask, bool p_collide_with_bodies, bool p_collide_with_areas, PhysicsServer3DExtensionShapeRestInfo *p_rest_info) override;
 Vector3 _get_closest_point_to_object_volume(const RID &p_object, const Vector3 &p_point) const override;
};
} // namespace godot
