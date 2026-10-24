#include "mj_physics_server.h"
#include <godot_cpp/core/object.hpp>
#include <algorithm>
namespace godot {
Vector3 MjDirectBodyState::_get_total_gravity() const{auto*b=server->body(rid);return b?(b->environment_valid?b->integration_environment:server->body_environment(*b)).gravity:Vector3();}
float MjDirectBodyState::_get_total_linear_damp() const{auto*b=server->body(rid);return b?(b->environment_valid?b->integration_environment:server->body_environment(*b)).linear_damp:0;}
float MjDirectBodyState::_get_total_angular_damp() const{auto*b=server->body(rid);return b?(b->environment_valid?b->integration_environment:server->body_environment(*b)).angular_damp:0;}
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
// Snapshots contain values and RIDs only; never retain MuJoCo pointers.
void MjPhysicsServer3D::collect_contacts(MjSpace &s) {
 for(int i=0;i<s.data->ncon;++i){
  const auto &c=s.data->contact[i];if(c.efc_address<0)continue;
  if(c.geom[0]<0||c.geom[1]<0)continue; // flex contacts have no native rigid geom identity.
  const auto owners=std::make_pair(s.geom_owners[c.geom[0]],s.geom_owners[c.geom[1]]);
  auto wants_report=[](const MjBody *b){return b&&b->max_contacts>int(b->contacts.size());};
  if(!wants_report(body(owners.first.first))&&!wants_report(body(owners.second.first)))continue;
  // MuJoCo contact frame rows map normal/tangent force into world axes.
  mjtNum force[6];mj_contactForce(s.model,s.data,i,force);
  Vector3 normal=mj_to_godot(Vector3(c.frame[0],c.frame[1],c.frame[2]));
  Vector3 impulse;
  for(int axis=0;axis<3;++axis)impulse+=mj_to_godot(Vector3(c.frame[3*axis],c.frame[3*axis+1],c.frame[3*axis+2]))*force[axis]*s.model->opt.timestep;
  Vector3 position=mj_to_godot(Vector3(c.pos[0],c.pos[1],c.pos[2]));
  Vector3 velocities[2];
  for(int side=0;side<2;++side){
   // mjOBJ_BODY returns velocity at the inertial COM, in world axes.
   int id=s.model->geom_bodyid[c.geom[side]];mjtNum velocity[6];mj_objectVelocity(s.model,s.data,mjOBJ_BODY,id,velocity,0);
   Vector3 angular(velocity[0],velocity[1],velocity[2]),linear(velocity[3],velocity[4],velocity[5]);
   Vector3 center(s.data->xipos[3*id],s.data->xipos[3*id+1],s.data->xipos[3*id+2]);
   velocities[side]=mj_to_godot(linear+angular.cross(Vector3(c.pos[0],c.pos[1],c.pos[2])-center));
  }
  for(int side=0;side<2;++side){
   auto owner=side==0?owners.first:owners.second,other=side==0?owners.second:owners.first;
   auto*b=body(owner.first);if(!b||b->max_contacts<=int(b->contacts.size()))continue;
   auto*collider=body(other.first);MjContact report;
   report.local_shape=owner.second;report.position=position;report.normal=normal*(side==0?-1:1);report.impulse=impulse*(side==0?-1:1);
   report.local_velocity=velocities[side];report.collider_velocity=velocities[1-side];
   if(collider){report.collider=collider->rid;report.object_id=collider->object_id;report.collider_shape=other.second;}
   b->contacts.push_back(report);
  }
 }
}
static const MjContact *contact(MjPhysicsServer3D *server,const RID &rid,int index){
 auto*b=server->body(rid);if(!b||index<0||index>=int(b->contacts.size()))return nullptr;
 return &b->contacts[index];
}
int32_t MjDirectBodyState::_get_contact_count() const{auto*b=server->body(rid);return b?b->contacts.size():0;}
#define CONTACT_GET(type,name,field,fallback) type MjDirectBodyState::_get_contact_##name(int32_t i) const{auto*c=contact(server,rid,i);return c?c->field:fallback;}
CONTACT_GET(Vector3,local_position,position,Vector3())
CONTACT_GET(Vector3,collider_position,position,Vector3())
CONTACT_GET(Vector3,local_normal,normal,Vector3())
CONTACT_GET(Vector3,impulse,impulse,Vector3())
CONTACT_GET(Vector3,local_velocity_at_position,local_velocity,Vector3())
CONTACT_GET(Vector3,collider_velocity_at_position,collider_velocity,Vector3())
CONTACT_GET(int32_t,local_shape,local_shape,-1)
CONTACT_GET(int32_t,collider_shape,collider_shape,-1)
#undef CONTACT_GET
RID MjDirectBodyState::_get_contact_collider(int32_t i) const{auto*c=contact(server,rid,i);auto*b=server->body(rid);auto*other=c?server->body(c->collider):nullptr;return other&&b&&other->space==b->space&&!server->pending_free.count(other->rid.get_id())?other->rid:RID();}
uint64_t MjDirectBodyState::_get_contact_collider_id(int32_t i) const{auto*c=contact(server,rid,i);return c&&_get_contact_collider(i).is_valid()?c->object_id:0;}
Object *MjDirectBodyState::_get_contact_collider_object(int32_t i) const{auto id=_get_contact_collider_id(i);return id?ObjectDB::get_instance(id):nullptr;}
float MjDirectBodyState::_get_step() const{auto*b=server->body(rid);return b?b->integration_step:0;}
void MjDirectBodyState::_integrate_forces(){
 double step=_get_step();
 _set_linear_velocity((_get_linear_velocity()+_get_total_gravity()*step)*std::max(0.0,1-step*_get_total_linear_damp()));
 _set_angular_velocity(_get_angular_velocity()*std::max(0.0,1-step*_get_total_angular_damp()));
}
PhysicsDirectSpaceState3D *MjDirectBodyState::_get_space_state(){auto*b=server->body(rid);return b?server->_space_get_direct_state(b->space):nullptr;}
void MjPhysicsServer3D::_body_apply_central_impulse(const RID&r,const Vector3&v){
 auto*b=body(r);if(!b||b->mode!=BODY_MODE_RIGID)return;
 Vector3 result=b->linear_velocity+v/b->mass;ERR_FAIL_COND(!v.is_finite()||!result.is_finite());b->linear_velocity=result;write_body(*b);
}
void MjPhysicsServer3D::_body_apply_torque_impulse(const RID&r,const Vector3&v){
 auto*b=body(r);if(!b||b->mode!=BODY_MODE_RIGID)return;ERR_FAIL_COND(!v.is_finite());
 Vector3 result=b->angular_velocity+b->direct->_get_inverse_inertia_tensor().xform(v);ERR_FAIL_COND(!result.is_finite());b->angular_velocity=result;write_body(*b);
}
void MjPhysicsServer3D::_body_apply_impulse(const RID&r,const Vector3&v,const Vector3&p){
 auto*b=body(r);if(!b||b->mode!=BODY_MODE_RIGID)return;ERR_FAIL_COND(!v.is_finite()||!p.is_finite());
 Vector3 lv=b->linear_velocity+v/b->mass;
 Vector3 av=b->angular_velocity+b->direct->_get_inverse_inertia_tensor().xform((p-b->direct->_get_center_of_mass()).cross(v));
 ERR_FAIL_COND(!lv.is_finite()||!av.is_finite());b->linear_velocity=lv;b->angular_velocity=av;write_body(*b);
}
void MjPhysicsServer3D::_body_apply_central_force(const RID&r,const Vector3&v){if(auto*b=body(r)){Vector3 result=b->force+v;ERR_FAIL_COND(!v.is_finite()||!result.is_finite());b->force=result;}}
void MjPhysicsServer3D::_body_apply_torque(const RID&r,const Vector3&v){if(auto*b=body(r)){Vector3 result=b->torque+v;ERR_FAIL_COND(!v.is_finite()||!result.is_finite());b->torque=result;}}
void MjPhysicsServer3D::_body_apply_force(const RID&r,const Vector3&v,const Vector3&p){
 auto*b=body(r);if(!b)return;ERR_FAIL_COND(!v.is_finite()||!p.is_finite());
 Vector3 f=b->force+v,t=b->torque+(p-b->direct->_get_center_of_mass()).cross(v);
 ERR_FAIL_COND(!f.is_finite()||!t.is_finite());b->force=f;b->torque=t;
}
void MjPhysicsServer3D::_body_add_constant_central_force(const RID&r,const Vector3&v){if(auto*b=body(r)){Vector3 result=b->constant_force+v;ERR_FAIL_COND(!v.is_finite()||!result.is_finite());b->constant_force=result;}}
void MjPhysicsServer3D::_body_add_constant_torque(const RID&r,const Vector3&v){if(auto*b=body(r)){Vector3 result=b->constant_torque+v;ERR_FAIL_COND(!v.is_finite()||!result.is_finite());b->constant_torque=result;}}
void MjPhysicsServer3D::_body_add_constant_force(const RID&r,const Vector3&v,const Vector3&p){
 auto*b=body(r);if(!b)return;ERR_FAIL_COND(!v.is_finite()||!p.is_finite());
 Vector3 f=b->constant_force+v,t=b->constant_torque+(p-b->direct->_get_center_of_mass()).cross(v);
 ERR_FAIL_COND(!f.is_finite()||!t.is_finite());b->constant_force=f;b->constant_torque=t;
}
void MjPhysicsServer3D::_body_set_constant_force(const RID&r,const Vector3&v){ERR_FAIL_COND(!v.is_finite());if(auto*b=body(r))b->constant_force=v;}
Vector3 MjPhysicsServer3D::_body_get_constant_force(const RID&r) const {auto*b=body(r);return b?b->constant_force:Vector3();}
void MjPhysicsServer3D::_body_set_constant_torque(const RID&r,const Vector3&v){ERR_FAIL_COND(!v.is_finite());if(auto*b=body(r))b->constant_torque=v;}
Vector3 MjPhysicsServer3D::_body_get_constant_torque(const RID&r) const {auto*b=body(r);return b?b->constant_torque:Vector3();}
void MjPhysicsServer3D::_body_set_axis_velocity(const RID&r,const Vector3&v){
 auto*b=body(r);if(!b)return;ERR_FAIL_COND(!v.is_finite());
 Vector3 axis=v.normalized(),result=b->linear_velocity-axis*axis.dot(b->linear_velocity)+v;
 ERR_FAIL_COND(!result.is_finite());b->linear_velocity=result;write_body(*b);
}
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
