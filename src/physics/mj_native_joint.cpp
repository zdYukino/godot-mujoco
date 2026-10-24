#include "mj_physics_server.h"
#include <cmath>
#include <algorithm>
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
void MjPhysicsServer3D::detach_native_joints(const RID&r){for(auto&e:native_joints)if(e.second.a==r||e.second.b==r){auto*a=body(e.second.a);if(a)dirty(a->space);e.second.pin=false;e.second.pending_limits=false;e.second.motor=false;e.second.use_limit=false;e.second.a=RID();e.second.b=RID();}}
bool MjPhysicsServer3D::commit_native_joint(const MjNativeJoint&candidate){
 auto it=native_joints.find(candidate.rid.get_id());if(it==native_joints.end()||pending_free.count(candidate.rid.get_id()))return false;
 auto*a=body(candidate.a);auto*b=body(candidate.b);auto*s=a?space(a->space):nullptr;
 if(!a||!s||a->heightfield||(a->mode!=BODY_MODE_STATIC&&a->mode!=BODY_MODE_RIGID)||(b&&b->mode!=BODY_MODE_STATIC&&b->mode!=BODY_MODE_RIGID)||pending_free.count(a->rid.get_id())||candidate.a==candidate.b||!candidate.anchor_a.is_finite()||!candidate.anchor_b.is_finite()||
    (candidate.b.is_valid()&&(!b||b->heightfield||b->space!=a->space||pending_free.count(b->rid.get_id())))||
    (a->mode!=BODY_MODE_RIGID&&(!b||b->mode!=BODY_MODE_RIGID))){ERR_PRINT("Native Pin requires finite anchors and native bodies in one space, with at least one rigid body");return false;}
 // Conservative forest boundary. Duplicate edges and closed loops are rejected
 // before editing either the accepted definition or collision filtering.
 auto vertex=[&](const RID &r)->uint64_t{auto*b=body(r);return b&&b->mode==BODY_MODE_RIGID?uint64_t(r.get_id()):0;};
 std::set<uint64_t> reached{vertex(candidate.a)};bool changed=true;
 while(changed){changed=false;for(auto&e:native_joints){auto&j=e.second;if(e.first==candidate.rid.get_id()||!native_joint_active(j,s->rid))continue;auto u=vertex(j.a),v=vertex(j.b);if(reached.count(u)&&!reached.count(v)){reached.insert(v);changed=true;}if(reached.count(v)&&!reached.count(u)){reached.insert(u);changed=true;}}}
 if(reached.count(vertex(candidate.b))){ERR_PRINT("Native Pin closed loops and duplicate edges are unsupported");return false;}
 if(!native_hinge_isolated(candidate)){ERR_PRINT("Native driven Hinge requires isolated rigid endpoints and aligned frame axes");return false;}
 auto previous=it->second;bool was_dirty=s->dirty;it->second=candidate;s->dirty=true;
 if(!rebuild(*s,Dictionary(),true)){it->second=previous;s->dirty=was_dirty;ERR_PRINT("Native Pin candidate rejected; previous model retained");return false;}
 // Moving a joint to another space also retires its old constraint.
 if(auto*old=body(previous.a))if(old->space!=a->space)dirty(old->space);
 return true;
}
RID MjPhysicsServer3D::_joint_create(){RID r=handles.make_rid(0);MjNativeJoint j;j.rid=r;native_joints.emplace(r.get_id(),j);return r;}
#define DEFER_JOINT(call) if(flushing){area_commands.push_back([=]{call;});return;}
void MjPhysicsServer3D::_joint_clear(const RID&r){DEFER_JOINT(_joint_clear(r));auto it=native_joints.find(r.get_id());if(it==native_joints.end())return;if(auto*b=body(it->second.a))dirty(b->space);it->second.pin=false;it->second.pending_limits=false;it->second.motor=false;it->second.use_limit=false;it->second.a=RID();it->second.b=RID();}
void MjPhysicsServer3D::_joint_make_pin(const RID&r,const RID&a,const Vector3&pa,const RID&b,const Vector3&pb){DEFER_JOINT(_joint_make_pin(r,a,pa,b,pb));auto it=native_joints.find(r.get_id());ERR_FAIL_COND(it==native_joints.end());auto j=it->second;j.a=a;j.b=b;j.anchor_a=pa;j.anchor_b=pb;j.pin=true;j.hinge=false;j.pending_limits=false;j.motor=false;j.use_limit=false;commit_native_joint(j);}
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
 make_native_hinge(r,a,fa.origin,fa.basis.get_column(2),b,fb.origin,fb.basis.get_column(2),fa.basis.get_column(0),fb.basis.get_column(0));
}
void MjPhysicsServer3D::_joint_make_hinge_simple(const RID&r,const RID&a,const Vector3&pa,const Vector3&aa,const RID&b,const Vector3&pb,const Vector3&ab){
 DEFER_JOINT(_joint_make_hinge_simple(r,a,pa,aa,b,pb,ab));
 make_native_hinge(r,a,pa,aa,b,pb,ab,Vector3(),Vector3());
}
void MjPhysicsServer3D::make_native_hinge(const RID&r,const RID&a,const Vector3&pa,const Vector3&aa,const RID&b,const Vector3&pb,const Vector3&ab,const Vector3&refa,const Vector3&refb){
 auto it=native_joints.find(r.get_id());ERR_FAIL_COND(it==native_joints.end());auto*ba=body(a);auto*bb=body(b);
 if(!ba||(b.is_valid()&&!bb)||!aa.is_finite()||!ab.is_finite()||!std::isfinite(aa.length())||!std::isfinite(ab.length())||aa.length()<1e-6||ab.length()<1e-6){ERR_PRINT("Native passive Hinge requires valid bodies and nonzero finite axes");return;}
 Vector3 axis_a=aa.normalized(),axis_b=ab.normalized();Vector3 wa=ba->transform.basis.xform(axis_a),wb=bb?bb->transform.basis.xform(axis_b):axis_b;
 if(std::abs(wa.dot(wb))<.9999){ERR_PRINT("Native passive Hinge initially misaligned world axes unsupported");return;}
 bool antiparallel=wa.dot(wb)<0;
 if(antiparallel)axis_b=-axis_b;
 // The one-metre auxiliary lever must survive Godot's float coordinate ABI.
 if(!pa.is_finite()||!pb.is_finite()||((pa+axis_a)-pa-axis_a).length()>1e-4||((pb+axis_b)-pb-axis_b).length()>1e-4){ERR_PRINT("Native passive Hinge auxiliary anchor not representable");return;}
 auto j=it->second;j.a=a;j.b=b;j.anchor_a=pa;j.anchor_b=pb;j.axis_a=axis_a;j.axis_b=axis_b;j.pin=true;j.hinge=true;j.antiparallel=antiparallel;
 // Like a freshly constructed Godot Hinge, a successful reconfiguration resets
 // type-specific parameters. Godot then replays all parameters before flags.
 j.use_limit=false;j.motor=false;j.pending_limits=false;
 j.lower=-Math_PI/2;j.upper=Math_PI/2;j.target_velocity=1;j.max_impulse=1;
 Vector3 world_ref=wa.cross(std::abs(wa.x)<.8?Vector3(1,0,0):Vector3(0,1,0)).normalized();
 j.reference_a=ba->transform.basis.transposed().xform(world_ref);
 j.reference_b=bb?bb->transform.basis.transposed().xform(world_ref):world_ref;
 if(refa.length_squared()>.5){j.reference_a=refa;j.reference_b=refb;}
 commit_native_joint(j);
}
static float hinge_default(PhysicsServer3D::HingeJointParam p){
 switch(p){case PhysicsServer3D::HINGE_JOINT_BIAS:return .3f;case PhysicsServer3D::HINGE_JOINT_LIMIT_UPPER:return float(Math_PI*.5);case PhysicsServer3D::HINGE_JOINT_LIMIT_LOWER:return float(-Math_PI*.5);case PhysicsServer3D::HINGE_JOINT_LIMIT_BIAS:return .3f;case PhysicsServer3D::HINGE_JOINT_LIMIT_SOFTNESS:return .9f;default:return 1.f;}
}
bool MjPhysicsServer3D::native_hinge_isolated(const MjNativeJoint&candidate)const{
 if(candidate.hinge&&(candidate.use_limit||candidate.motor)&&candidate.antiparallel)return false;
 auto dynamic=[&](const RID&r){auto*b=body(r);return b&&b->mode==BODY_MODE_RIGID;};
 for(auto&e:native_joints){auto&other=e.second;if(e.first==candidate.rid.get_id()||!other.pin)continue;
  if(!(candidate.hinge&&(candidate.use_limit||candidate.motor))&&!(other.hinge&&(other.use_limit||other.motor)))continue;
  for(auto r:{candidate.a,candidate.b})if(dynamic(r)&&(other.a==r||other.b==r))return false;
 }return true;
}
void MjPhysicsServer3D::_hinge_joint_set_param(const RID&r,HingeJointParam p,float v){
 DEFER_JOINT(_hinge_joint_set_param(r,p,v));auto it=native_joints.find(r.get_id());ERR_FAIL_COND(it==native_joints.end());
 if(p<HINGE_JOINT_BIAS||p>HINGE_JOINT_MOTOR_MAX_IMPULSE||!std::isfinite(v)){ERR_PRINT("Native Hinge invalid parameter");return;}
 auto j=it->second;
 switch(p){
 case HINGE_JOINT_LIMIT_LOWER:case HINGE_JOINT_LIMIT_UPPER:{
  if(v < -3 || v > 3){ERR_PRINT("Native Hinge invalid limit range");return;}
  double lower=j.pending_limits?j.pending_lower:j.lower,upper=j.pending_limits?j.pending_upper:j.upper;
  if(p==HINGE_JOINT_LIMIT_LOWER)lower=v;else upper=v;
  if(lower>upper){
   if(j.use_limit||j.motor){ERR_PRINT("Native Hinge invalid limit range");return;}
   // A disabled joint is loaded upper-first by Godot. Keep the accepted pair
   // unchanged until the other bound completes a valid pair (either order).
   j.pending_limits=true;j.pending_lower=lower;j.pending_upper=upper;
  }else{j.lower=lower;j.upper=upper;j.pending_limits=false;}
  break;
 }
 case HINGE_JOINT_MOTOR_TARGET_VELOCITY:if(std::abs(v)>100){ERR_PRINT("Native Hinge velocity outside supported range");return;}j.target_velocity=v;break;
 case HINGE_JOINT_MOTOR_MAX_IMPULSE:if(v<0||v>1000){ERR_PRINT("Native Hinge impulse outside supported range");return;}j.max_impulse=v;break;
 default:if(v!=hinge_default(p)){ERR_PRINT("Native Hinge custom solver response unsupported");return;}
 }
 it->second=j;
}
float MjPhysicsServer3D::_hinge_joint_get_param(const RID&r,HingeJointParam p)const{
 auto it=native_joints.find(r.get_id());if(it==native_joints.end())return 0;auto&j=it->second;
 switch(p){case HINGE_JOINT_LIMIT_LOWER:return j.lower;case HINGE_JOINT_LIMIT_UPPER:return j.upper;case HINGE_JOINT_MOTOR_TARGET_VELOCITY:return j.target_velocity;case HINGE_JOINT_MOTOR_MAX_IMPULSE:return j.max_impulse;default:return hinge_default(p);}
}
void MjPhysicsServer3D::_hinge_joint_set_flag(const RID&r,HingeJointFlag f,bool enabled){
 DEFER_JOINT(_hinge_joint_set_flag(r,f,enabled));auto it=native_joints.find(r.get_id());ERR_FAIL_COND(it==native_joints.end());auto j=it->second;
 if(f<HINGE_JOINT_FLAG_USE_LIMIT||f>HINGE_JOINT_FLAG_ENABLE_MOTOR){ERR_PRINT("Native Hinge invalid flag");return;}
 if(j.pending_limits){ERR_PRINT("Native Hinge incomplete or inverted limit pair; accepted limits retained");return;}
 if(f==HINGE_JOINT_FLAG_USE_LIMIT)j.use_limit=enabled;else j.motor=enabled;
 if(enabled&&(!j.pin||!j.hinge||!native_hinge_isolated(j))){ERR_PRINT("Native driven Hinge requires configured isolated rigid endpoints and aligned frame axes");return;}
 it->second=j;
}
bool MjPhysicsServer3D::_hinge_joint_get_flag(const RID&r,HingeJointFlag f)const{
 auto it=native_joints.find(r.get_id());if(it==native_joints.end())return false;
 return f==HINGE_JOINT_FLAG_USE_LIMIT?it->second.use_limit:f==HINGE_JOINT_FLAG_ENABLE_MOTOR?it->second.motor:false;
}

// Mass-weighted projection onto the five passive hinge velocity constraints.
// This includes anchor translation: a COM-offset hinge must use its orbital
// inertia, not just the unconstrained angular inverse inertia of each body.
bool MjPhysicsServer3D::apply_native_hinge_drives(MjSpace&s,double interval){
 bool any=false;for(auto&e:native_joints)if(native_joint_active(e.second,s.rid)&&e.second.hinge&&(e.second.motor||e.second.use_limit))any=true;
 if(!any)return true;
 auto*m=s.model;auto*d=s.data;const int nv=m->nv;const double dt=m->opt.timestep;
 mj_forward(m,d); // Current poses, Jacobians and factored mass after prior substep.
 std::vector<mjtNum> next(d->qvel,d->qvel+nv);
 for(auto&e:native_joints){auto&j=e.second;if(!native_joint_active(j,s.rid)||!j.hinge||(!j.motor&&!j.use_limit))continue;
  auto*a=body(j.a);auto*b=body(j.b);int ia=a->mj_body,ib=b?b->mj_body:0;
  auto rotate=[&](int id,const Vector3&v){Vector3 x=godot_to_mj(v);if(id==0)return x;const auto*R=d->xmat+9*id;return Vector3(R[0]*x.x+R[1]*x.y+R[2]*x.z,R[3]*x.x+R[4]*x.y+R[5]*x.z,R[6]*x.x+R[7]*x.y+R[8]*x.z);};
  Vector3 axis=rotate(ia,j.axis_a).normalized(),refa=rotate(ia,j.reference_a),refb=rotate(ib,j.reference_b);
  Vector3 transverse=refa-axis*refa.dot(axis);if(transverse.length_squared()<.5)return false;transverse.normalize();Vector3 other=axis.cross(transverse);
  double angle=std::atan2(axis.dot(refb.cross(refa)),refb.dot(refa));j.step_angle=angle;
  std::vector<mjtNum> rows(6*nv,0),inv(6*nv,0),pa(3*nv),pb(3*nv),ra(3*nv),rb(3*nv);
  auto point=[&](int id,Vector3 local,mjtNum*out){Vector3 v=rotate(id,local);for(int k=0;k<3;++k)out[k]=v[k]+(id?d->xpos[3*id+k]:0);};
  mjtNum xa[3],xb[3];point(ia,j.anchor_a,xa);point(ib,j.anchor_b,xb);
  mj_jac(m,d,pa.data(),ra.data(),xa,ia);mj_jac(m,d,pb.data(),rb.data(),xb,ib);
  for(int v=0;v<nv;++v){for(int k=0;k<3;++k)rows[k*nv+v]=pa[k*nv+v]-pb[k*nv+v];for(int k=0;k<3;++k){double r=ra[k*nv+v]-rb[k*nv+v];rows[3*nv+v]+=transverse[k]*r;rows[4*nv+v]+=other[k]*r;rows[5*nv+v]+=axis[k]*r;}}
  mj_solveM(m,d,inv.data(),rows.data(),6);
  double mat[5][5]{},rhs[5]{},L[5][5]{};
  for(int i=0;i<5;++i){rhs[i]=mju_dot(rows.data()+i*nv,inv.data()+5*nv,nv);for(int k=0;k<5;++k)mat[i][k]=mju_dot(rows.data()+i*nv,inv.data()+k*nv,nv);}
  for(int i=0;i<5;++i)for(int k=0;k<=i;++k){double value=mat[i][k];for(int t=0;t<k;++t)value-=L[i][t]*L[k][t];if(i==k){if(!std::isfinite(value)||value<=std::max(1e-12,mat[i][i]*1e-10))return false;L[i][k]=std::sqrt(value);}else L[i][k]=value/L[k][k];}
  double y[5]{},lambda[5]{};for(int i=0;i<5;++i){double v=rhs[i];for(int k=0;k<i;++k)v-=L[i][k]*y[k];y[i]=v/L[i][i];}
  for(int i=4;i>=0;--i){double v=y[i];for(int k=i+1;k<5;++k)v-=L[k][i]*lambda[k];lambda[i]=v/L[i][i];}
  std::vector<mjtNum> response(nv);for(int v=0;v<nv;++v){response[v]=inv[5*nv+v];for(int k=0;k<5;++k)response[v]-=inv[k*nv+v]*lambda[k];}
  double inverse_inertia=mju_dot(rows.data()+5*nv,response.data(),nv),velocity=mju_dot(rows.data()+5*nv,next.data(),nv);
  if(!std::isfinite(inverse_inertia)||inverse_inertia<1e-12||!std::isfinite(velocity))return false;
  if(std::abs(velocity)*dt>.25||dt>.02)return false;
  for(int k=0;k<5;++k)if(std::abs(mju_dot(rows.data()+k*nv,response.data(),nv))>1e-7*std::max(1.0,inverse_inertia))return false;
  double desired=velocity,impulse=0;
  if(j.motor){double budget=j.max_impulse*dt/interval;impulse=std::clamp((j.target_velocity-velocity)/inverse_inertia,-budget,budget);desired+=impulse*inverse_inertia;}
  if(j.use_limit){double lower=(j.lower-angle)/dt,upper=(j.upper-angle)/dt;
   // Outside the interval, use fixed .3 error reduction, without teleporting.
   if(angle<j.lower)lower=std::min(lower*.3,.2/dt);
   if(angle>j.upper)upper=std::max(upper*.3,-.2/dt);
   desired=std::clamp(desired,lower,upper);impulse=(desired-velocity)/inverse_inertia;
  }
  if(!std::isfinite(angle)||!std::isfinite(impulse)||!std::isfinite(desired)||std::abs(desired)*dt>.25)return false;
  for(int v=0;v<nv;++v){next[v]+=response[v]*impulse;if(!std::isfinite(next[v])||std::abs(next[v])>1e6)return false;}
  if(std::abs(mju_dot(rows.data()+5*nv,next.data(),nv))*dt>.25+1e-10)return false;
 }
 mju_copy(d->qvel,next.data(),nv);return true;
}

bool MjPhysicsServer3D::validate_native_hinge_step(MjSpace&s){
 auto*m=s.model;auto*d=s.data;mj_forward(m,d);
 for(int i=0;i<m->nv;++i)if(!std::isfinite(d->qvel[i])||!std::isfinite(d->qacc[i]))return false;
 for(int i=0;i<m->nq;++i)if(!std::isfinite(d->qpos[i]))return false;
 auto rotate=[&](int id,const Vector3&v){Vector3 x=godot_to_mj(v);if(!id)return x;const auto*R=d->xmat+9*id;return Vector3(R[0]*x.x+R[1]*x.y+R[2]*x.z,R[3]*x.x+R[4]*x.y+R[5]*x.z,R[6]*x.x+R[7]*x.y+R[8]*x.z);};
 for(auto&e:native_joints){auto&j=e.second;if(!native_joint_active(j,s.rid)||!j.hinge||(!j.motor&&!j.use_limit))continue;
  auto*a=body(j.a);auto*b=body(j.b);Vector3 axis=rotate(a->mj_body,j.axis_a).normalized(),ra=rotate(a->mj_body,j.reference_a),rb=rotate(b?b->mj_body:0,j.reference_b);
  double angle=std::atan2(axis.dot(rb.cross(ra)),rb.dot(ra)),delta=angle-j.step_angle;
  mjtNum va[6]{},vb[6]{};mj_objectVelocity(m,d,mjOBJ_BODY,a->mj_body,va,0);if(b)mj_objectVelocity(m,d,mjOBJ_BODY,b->mj_body,vb,0);
  double speed=0;for(int k=0;k<3;++k)speed+=axis[k]*(va[k]-vb[k]);
  // Wrapped orientations alone cannot detect an entire revolution from an
  // external torque in one step. Validate the post-step physical velocity too.
  if(!std::isfinite(speed)||std::abs(speed)*m->opt.timestep>.25+1e-6)return false;
  // Limited angles have a single branch. External force/contact must not wrap
  // an upper-limit violation into an apparent lower-limit violation.
  if(!std::isfinite(angle)||(j.use_limit&&std::abs(delta)>Math_PI)||std::abs(std::remainder(delta,2*Math_PI))>.25+1e-6)return false;
 }
 return true;
}

#undef DEFER_JOINT
}
