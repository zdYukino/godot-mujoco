#include "mj_physics_server.h"
#include <cmath>
namespace godot {
// Preserve free-body coordinates. A connect equality is a soft ball joint, not
// a change to the MuJoCo kinematic tree. Parameters are deliberately bounded.
bool MjPhysicsServer3D::native_joint_active(const MjNativeJoint &j,const RID &s) const {
 auto*a=body(j.a);auto*b=body(j.b);
 return j.pin&&a&&a->space==s&&!a->heightfield&&(!j.b.is_valid()||(b&&b->space==s&&!b->heightfield));
}
bool MjPhysicsServer3D::native_joint_collision_disabled(const RID&a,const RID&b) const {
 for(auto &e:native_joints){auto&j=e.second;if(j.pin&&j.disable_collisions&&((j.a==a&&j.b==b)||(j.a==b&&j.b==a)))return true;}return false;
}
void MjPhysicsServer3D::detach_native_joints(const RID&r){for(auto&e:native_joints)if(e.second.a==r||e.second.b==r){auto*a=body(e.second.a);if(a)dirty(a->space);e.second.pin=false;e.second.a=RID();e.second.b=RID();}}
bool MjPhysicsServer3D::commit_native_joint(const MjNativeJoint&candidate){
 auto it=native_joints.find(candidate.rid.get_id());if(it==native_joints.end()||pending_free.count(candidate.rid.get_id()))return false;
 auto*a=body(candidate.a);auto*b=body(candidate.b);auto*s=a?space(a->space):nullptr;
 if(!a||!s||a->heightfield||pending_free.count(a->rid.get_id())||candidate.a==candidate.b||!candidate.anchor_a.is_finite()||!candidate.anchor_b.is_finite()||
    (candidate.b.is_valid()&&(!b||b->heightfield||b->space!=a->space||pending_free.count(b->rid.get_id())))||
    (a->mode!=BODY_MODE_RIGID&&(!b||b->mode!=BODY_MODE_RIGID))){ERR_PRINT("Native Pin requires finite anchors and native bodies in one space, with at least one rigid body");return false;}
 // Conservative forest boundary. Duplicate edges and closed loops are rejected
 // before editing either the accepted definition or collision filtering.
 auto vertex=[&](const RID &r)->uint64_t{auto*b=body(r);return b&&b->mode==BODY_MODE_RIGID?uint64_t(r.get_id()):0;};
 std::set<uint64_t> reached{vertex(candidate.a)};bool changed=true;
 while(changed){changed=false;for(auto&e:native_joints){auto&j=e.second;if(e.first==candidate.rid.get_id()||!native_joint_active(j,s->rid))continue;auto u=vertex(j.a),v=vertex(j.b);if(reached.count(u)&&!reached.count(v)){reached.insert(v);changed=true;}if(reached.count(v)&&!reached.count(u)){reached.insert(u);changed=true;}}}
 if(reached.count(vertex(candidate.b))){ERR_PRINT("Native Pin closed loops and duplicate edges are unsupported");return false;}
 auto previous=it->second;bool was_dirty=s->dirty;it->second=candidate;s->dirty=true;
 if(!rebuild(*s,Dictionary(),true)){it->second=previous;s->dirty=was_dirty;ERR_PRINT("Native Pin candidate rejected; previous model retained");return false;}
 // Moving a joint to another space also retires its old constraint.
 if(auto*old=body(previous.a))if(old->space!=a->space)dirty(old->space);
 return true;
}
RID MjPhysicsServer3D::_joint_create(){RID r=handles.make_rid(0);MjNativeJoint j;j.rid=r;native_joints.emplace(r.get_id(),j);return r;}
#define DEFER_JOINT(call) if(flushing){area_commands.push_back([=]{call;});return;}
void MjPhysicsServer3D::_joint_clear(const RID&r){DEFER_JOINT(_joint_clear(r));auto it=native_joints.find(r.get_id());if(it==native_joints.end())return;if(auto*b=body(it->second.a))dirty(b->space);it->second.pin=false;it->second.a=RID();it->second.b=RID();}
void MjPhysicsServer3D::_joint_make_pin(const RID&r,const RID&a,const Vector3&pa,const RID&b,const Vector3&pb){DEFER_JOINT(_joint_make_pin(r,a,pa,b,pb));auto it=native_joints.find(r.get_id());ERR_FAIL_COND(it==native_joints.end());auto j=it->second;j.a=a;j.b=b;j.anchor_a=pa;j.anchor_b=pb;j.pin=true;j.hinge=false;commit_native_joint(j);}
void MjPhysicsServer3D::_pin_joint_set_local_a(const RID&r,const Vector3&p){DEFER_JOINT(_pin_joint_set_local_a(r,p));auto it=native_joints.find(r.get_id());ERR_FAIL_COND(it==native_joints.end()||!it->second.pin||it->second.hinge);auto j=it->second;j.anchor_a=p;commit_native_joint(j);}
void MjPhysicsServer3D::_pin_joint_set_local_b(const RID&r,const Vector3&p){DEFER_JOINT(_pin_joint_set_local_b(r,p));auto it=native_joints.find(r.get_id());ERR_FAIL_COND(it==native_joints.end()||!it->second.pin||it->second.hinge);auto j=it->second;j.anchor_b=p;commit_native_joint(j);}
Vector3 MjPhysicsServer3D::_pin_joint_get_local_a(const RID&r)const{auto i=native_joints.find(r.get_id());return i==native_joints.end()?Vector3():i->second.anchor_a;}
Vector3 MjPhysicsServer3D::_pin_joint_get_local_b(const RID&r)const{auto i=native_joints.find(r.get_id());return i==native_joints.end()?Vector3():i->second.anchor_b;}
float MjPhysicsServer3D::_pin_joint_get_param(const RID&r,PinJointParam p)const{if(!native_joints.count(r.get_id()))return 0;return p==PIN_JOINT_BIAS?.3f:p==PIN_JOINT_DAMPING?1.f:0.f;}
void MjPhysicsServer3D::_pin_joint_set_param(const RID&r,PinJointParam p,float v){ERR_FAIL_COND(!native_joints.count(r.get_id()));if(!std::isfinite(v)||p<PIN_JOINT_BIAS||p>PIN_JOINT_IMPULSE_CLAMP||v!=_pin_joint_get_param(r,p))ERR_PRINT("Native Pin uses fixed MuJoCo soft constraint response; custom Godot bias/damping/impulse clamp unsupported");}
PhysicsServer3D::JointType MjPhysicsServer3D::_joint_get_type(const RID&r)const{auto i=native_joints.find(r.get_id());return i!=native_joints.end()&&i->second.pin?(i->second.hinge?JOINT_TYPE_HINGE:JOINT_TYPE_PIN):JOINT_TYPE_MAX;}
void MjPhysicsServer3D::_joint_set_solver_priority(const RID&r,int32_t p){ERR_FAIL_COND(!native_joints.count(r.get_id()));if(p!=1)ERR_PRINT("Native joint custom solver priority unsupported");}
int32_t MjPhysicsServer3D::_joint_get_solver_priority(const RID&r)const{return native_joints.count(r.get_id())?1:0;}
void MjPhysicsServer3D::_joint_disable_collisions_between_bodies(const RID&r,bool d){DEFER_JOINT(_joint_disable_collisions_between_bodies(r,d));auto it=native_joints.find(r.get_id());ERR_FAIL_COND(it==native_joints.end());auto j=it->second;j.disable_collisions=d;if(j.pin)commit_native_joint(j);else it->second=j;}
bool MjPhysicsServer3D::_joint_is_disabled_collisions_between_bodies(const RID&r)const{auto i=native_joints.find(r.get_id());return i!=native_joints.end()&&i->second.disable_collisions;}

static bool joint_rigid_frame(const Transform3D&t){
 if(!t.is_finite()||std::abs(t.basis.determinant()-1)>1e-4)return false;
 for(int i=0;i<3;++i){if(std::abs(t.basis.get_column(i).length_squared()-1)>1e-4)return false;for(int k=0;k<i;++k)if(std::abs(t.basis.get_column(i).dot(t.basis.get_column(k)))>1e-4)return false;}return true;
}
void MjPhysicsServer3D::_joint_make_hinge(const RID&r,const RID&a,const Transform3D&fa,const RID&b,const Transform3D&fb){
 DEFER_JOINT(_joint_make_hinge(r,a,fa,b,fb));
 if(!joint_rigid_frame(fa)||!joint_rigid_frame(fb)){ERR_PRINT("Native passive Hinge requires finite rigid frames");return;}
 _joint_make_hinge_simple(r,a,fa.origin,fa.basis.get_column(2),b,fb.origin,fb.basis.get_column(2));
}
void MjPhysicsServer3D::_joint_make_hinge_simple(const RID&r,const RID&a,const Vector3&pa,const Vector3&aa,const RID&b,const Vector3&pb,const Vector3&ab){
 DEFER_JOINT(_joint_make_hinge_simple(r,a,pa,aa,b,pb,ab));
 auto it=native_joints.find(r.get_id());ERR_FAIL_COND(it==native_joints.end());auto*ba=body(a);auto*bb=body(b);
 if(!ba||(b.is_valid()&&!bb)||!aa.is_finite()||!ab.is_finite()||!std::isfinite(aa.length())||!std::isfinite(ab.length())||aa.length()<1e-6||ab.length()<1e-6){ERR_PRINT("Native passive Hinge requires valid bodies and nonzero finite axes");return;}
 Vector3 axis_a=aa.normalized(),axis_b=ab.normalized();Vector3 wa=ba->transform.basis.xform(axis_a),wb=bb?bb->transform.basis.xform(axis_b):axis_b;
 if(std::abs(wa.dot(wb))<.9999){ERR_PRINT("Native passive Hinge initially misaligned world axes unsupported");return;}
 if(wa.dot(wb)<0)axis_b=-axis_b;
 // The one-metre auxiliary lever must survive Godot's float coordinate ABI.
 if(!pa.is_finite()||!pb.is_finite()||((pa+axis_a)-pa-axis_a).length()>1e-4||((pb+axis_b)-pb-axis_b).length()>1e-4){ERR_PRINT("Native passive Hinge auxiliary anchor not representable");return;}
 auto j=it->second;j.a=a;j.b=b;j.anchor_a=pa;j.anchor_b=pb;j.axis_a=axis_a;j.axis_b=axis_b;j.pin=true;j.hinge=true;commit_native_joint(j);
}
static float hinge_default(PhysicsServer3D::HingeJointParam p){
 switch(p){case PhysicsServer3D::HINGE_JOINT_BIAS:return .3f;case PhysicsServer3D::HINGE_JOINT_LIMIT_UPPER:return float(Math_PI*.5);case PhysicsServer3D::HINGE_JOINT_LIMIT_LOWER:return float(-Math_PI*.5);case PhysicsServer3D::HINGE_JOINT_LIMIT_BIAS:return .3f;case PhysicsServer3D::HINGE_JOINT_LIMIT_SOFTNESS:return .9f;default:return 1.f;}
}
void MjPhysicsServer3D::_hinge_joint_set_param(const RID&r,HingeJointParam p,float v){ERR_FAIL_COND(!native_joints.count(r.get_id()));if(p<HINGE_JOINT_BIAS||p>HINGE_JOINT_MOTOR_MAX_IMPULSE||!std::isfinite(v)||v!=hinge_default(p))ERR_PRINT("Native passive Hinge custom response, limit and motor parameters unsupported");}
float MjPhysicsServer3D::_hinge_joint_get_param(const RID&r,HingeJointParam p)const{return native_joints.count(r.get_id())?hinge_default(p):0;}
void MjPhysicsServer3D::_hinge_joint_set_flag(const RID&r,HingeJointFlag f,bool enabled){ERR_FAIL_COND(!native_joints.count(r.get_id()));if(enabled||f<HINGE_JOINT_FLAG_USE_LIMIT||f>HINGE_JOINT_FLAG_ENABLE_MOTOR)ERR_PRINT("Native passive Hinge limits and motor enable unsupported");}
bool MjPhysicsServer3D::_hinge_joint_get_flag(const RID&,HingeJointFlag)const{return false;}

#undef DEFER_JOINT
}
