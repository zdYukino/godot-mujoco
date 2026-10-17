#include "mj_physics_server.h"
namespace godot {
static Vector3 total_gravity(MjPhysicsServer3D *server, const RID &rid) {
 auto *b=server->body(rid); if(!b) return {}; auto *s=server->space(b->space);
 return s?s->gravity_direction*s->gravity*b->gravity_scale:Vector3();
}
static float damping(MjPhysicsServer3D *server,const RID &rid,bool angular) {
 auto*b=server->body(rid);if(!b)return 0;auto*s=server->space(b->space);
 auto param=angular?PhysicsServer3D::BODY_PARAM_ANGULAR_DAMP:PhysicsServer3D::BODY_PARAM_LINEAR_DAMP;
 auto mode=angular?PhysicsServer3D::BODY_PARAM_ANGULAR_DAMP_MODE:PhysicsServer3D::BODY_PARAM_LINEAR_DAMP_MODE;
 double value=server->_body_get_param(rid,param);if(s&&int(server->_body_get_param(rid,mode))==0)value+=angular?s->angular_damp:s->linear_damp;return value;
}
Vector3 MjDirectBodyState::_get_total_gravity() const{return total_gravity(server,rid);}
float MjDirectBodyState::_get_total_linear_damp() const{return damping(server,rid,false);}
float MjDirectBodyState::_get_total_angular_damp() const{return damping(server,rid,true);}
Vector3 MjDirectBodyState::_get_center_of_mass_local() const {
 auto*b=server->body(rid);if(!b)return {};auto*s=server->space(b->space);if(!s||!server->rebuild(*s)||b->mj_body<1)return {};
 auto*p=s->model->body_ipos+3*b->mj_body;return mj_to_godot(Vector3(p[0],p[1],p[2]));
}
Vector3 MjDirectBodyState::_get_center_of_mass() const {return _get_transform().basis.xform(_get_center_of_mass_local());}
Basis MjDirectBodyState::_get_principal_inertia_axes() const {
 auto*b=server->body(rid);if(!b)return {};auto*s=server->space(b->space);if(!s||!server->rebuild(*s)||b->mj_body<1)return {};
 auto*q=s->model->body_iquat+4*b->mj_body;return mj_to_godot(Basis(Quaternion(q[1],q[2],q[3],q[0])));
}
float MjDirectBodyState::_get_inverse_mass() const {auto*b=server->body(rid);return b&&b->mode==PhysicsServer3D::BODY_MODE_RIGID?1.0/b->mass:0;}
Vector3 MjDirectBodyState::_get_inverse_inertia() const {
 auto*b=server->body(rid);if(!b||b->mode!=PhysicsServer3D::BODY_MODE_RIGID)return {};auto*s=server->space(b->space);if(!s||!server->rebuild(*s)||b->mj_body<1)return {};
 auto*i=s->model->body_inertia+3*b->mj_body;return Vector3(i[0]>0?1/i[0]:0,i[2]>0?1/i[2]:0,i[1]>0?1/i[1]:0);
}
Basis MjDirectBodyState::_get_inverse_inertia_tensor() const {Basis axes=_get_transform().basis.orthonormalized()*_get_principal_inertia_axes();Vector3 i=_get_inverse_inertia();Basis diagonal(Vector3(i.x,0,0),Vector3(0,i.y,0),Vector3(0,0,i.z));return axes*diagonal*axes.transposed();}
void MjDirectBodyState::_set_linear_velocity(const Vector3&v){server->_body_set_state(rid,PhysicsServer3D::BODY_STATE_LINEAR_VELOCITY,v);}
Vector3 MjDirectBodyState::_get_linear_velocity() const {return server->_body_get_state(rid,PhysicsServer3D::BODY_STATE_LINEAR_VELOCITY);}
void MjDirectBodyState::_set_angular_velocity(const Vector3&v){server->_body_set_state(rid,PhysicsServer3D::BODY_STATE_ANGULAR_VELOCITY,v);}
Vector3 MjDirectBodyState::_get_angular_velocity() const {return server->_body_get_state(rid,PhysicsServer3D::BODY_STATE_ANGULAR_VELOCITY);}
void MjDirectBodyState::_set_transform(const Transform3D&t){server->_body_set_state(rid,PhysicsServer3D::BODY_STATE_TRANSFORM,t);}
Transform3D MjDirectBodyState::_get_transform() const {return server->_body_get_state(rid,PhysicsServer3D::BODY_STATE_TRANSFORM);}
Vector3 MjDirectBodyState::_get_velocity_at_local_position(const Vector3&p) const {return _get_linear_velocity()+_get_angular_velocity().cross(p-_get_center_of_mass());}
void MjDirectBodyState::_set_sleep_state(bool v){server->_body_set_state(rid,PhysicsServer3D::BODY_STATE_SLEEPING,v);}
bool MjDirectBodyState::_is_sleeping() const{return false;}
void MjDirectBodyState::_set_collision_layer(uint32_t v){server->_body_set_collision_layer(rid,v);}
uint32_t MjDirectBodyState::_get_collision_layer() const{return server->_body_get_collision_layer(rid);}
void MjDirectBodyState::_set_collision_mask(uint32_t v){server->_body_set_collision_mask(rid,v);}
uint32_t MjDirectBodyState::_get_collision_mask() const{return server->_body_get_collision_mask(rid);}
int32_t MjDirectBodyState::_get_contact_count() const{return 0;}
float MjDirectBodyState::_get_step() const{return server->last_step;}
void MjDirectBodyState::_integrate_forces(){mj_unsupported("explicit direct-state integrate_forces; MuJoCo performs integration");}
PhysicsDirectSpaceState3D *MjDirectBodyState::_get_space_state(){auto*b=server->body(rid);return b?server->_space_get_direct_state(b->space):nullptr;}
void MjPhysicsServer3D::_body_apply_central_impulse(const RID&r,const Vector3&v){auto*b=body(r);if(!b||b->mode!=BODY_MODE_RIGID)return;b->linear_velocity+=v/b->mass;write_body(*b);}
void MjPhysicsServer3D::_body_apply_torque_impulse(const RID&r,const Vector3&v){auto*b=body(r);if(!b||b->mode!=BODY_MODE_RIGID)return;b->angular_velocity+=b->direct->_get_inverse_inertia_tensor().xform(v);write_body(*b);}
void MjPhysicsServer3D::_body_apply_impulse(const RID&r,const Vector3&v,const Vector3&p){auto*b=body(r);if(!b)return;_body_apply_central_impulse(r,v);_body_apply_torque_impulse(r,(p-b->direct->_get_center_of_mass()).cross(v));}
void MjPhysicsServer3D::_body_apply_central_force(const RID&r,const Vector3&v){if(auto*b=body(r))b->force+=v;}
void MjPhysicsServer3D::_body_apply_torque(const RID&r,const Vector3&v){if(auto*b=body(r))b->torque+=v;}
void MjPhysicsServer3D::_body_apply_force(const RID&r,const Vector3&v,const Vector3&p){auto*b=body(r);if(!b)return;b->force+=v;b->torque+=(p-b->direct->_get_center_of_mass()).cross(v);}
void MjPhysicsServer3D::_body_add_constant_central_force(const RID&r,const Vector3&v){if(auto*b=body(r))b->constant_force+=v;}
void MjPhysicsServer3D::_body_add_constant_torque(const RID&r,const Vector3&v){if(auto*b=body(r))b->constant_torque+=v;}
void MjPhysicsServer3D::_body_add_constant_force(const RID&r,const Vector3&v,const Vector3&p){auto*b=body(r);if(!b)return;b->constant_force+=v;b->constant_torque+=(p-b->direct->_get_center_of_mass()).cross(v);}
void MjPhysicsServer3D::_body_set_constant_force(const RID&r,const Vector3&v){if(auto*b=body(r))b->constant_force=v;}
Vector3 MjPhysicsServer3D::_body_get_constant_force(const RID&r) const {auto*b=body(r);return b?b->constant_force:Vector3();}
void MjPhysicsServer3D::_body_set_constant_torque(const RID&r,const Vector3&v){if(auto*b=body(r))b->constant_torque=v;}
Vector3 MjPhysicsServer3D::_body_get_constant_torque(const RID&r) const {auto*b=body(r);return b?b->constant_torque:Vector3();}
void MjPhysicsServer3D::_body_set_axis_velocity(const RID&r,const Vector3&v){auto*b=body(r);if(!b)return;Vector3 axis=v.normalized();b->linear_velocity-=axis*axis.dot(b->linear_velocity);b->linear_velocity+=v;write_body(*b);}
#define FORWARD_VECTOR(name) void MjDirectBodyState::_##name(const Vector3&v){server->_body_##name(rid,v);}
#define FORWARD_POSITION(name) void MjDirectBodyState::_##name(const Vector3&v,const Vector3&p){server->_body_##name(rid,v,p);}
FORWARD_VECTOR(apply_central_impulse)
FORWARD_VECTOR(apply_torque_impulse)
FORWARD_VECTOR(apply_central_force)
FORWARD_VECTOR(apply_torque)
FORWARD_VECTOR(add_constant_central_force)
FORWARD_VECTOR(add_constant_torque)
FORWARD_VECTOR(set_constant_force)
FORWARD_VECTOR(set_constant_torque)
FORWARD_POSITION(apply_impulse)
FORWARD_POSITION(apply_force)
FORWARD_POSITION(add_constant_force)
Vector3 MjDirectBodyState::_get_constant_force() const{return server->_body_get_constant_force(rid);}
Vector3 MjDirectBodyState::_get_constant_torque() const{return server->_body_get_constant_torque(rid);}
#undef FORWARD_VECTOR
#undef FORWARD_POSITION
}
