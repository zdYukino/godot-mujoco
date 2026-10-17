#include "mj_physics_server.h"
#include <godot_cpp/variant/utility_functions.hpp>
#include <algorithm>
#include <cmath>
#include <sstream>
#include <iomanip>
#include <locale>
namespace godot {
static bool valid_rigid_transform(const Transform3D &t) {
 if(!t.origin.is_finite()||!t.basis.is_finite()) { UtilityFunctions::push_error("MuJoCo backend requires finite transforms"); return false; }
 if(!t.basis.is_orthogonal()||!t.basis.get_scale().is_equal_approx(Vector3(1,1,1))||t.basis.determinant()<0) {
  UtilityFunctions::push_error("MuJoCo minimal backend requires unscaled rigid transforms; set shape dimensions instead"); return false;
 }
 return true;
}

MjSpace::~MjSpace() { if(data) mj_deleteData(data); if(model) mj_deleteModel(model); if(direct) memdelete(direct); }
MjBody *MjPhysicsServer3D::body(const RID &r) const { auto i=bodies.find(r.get_id()); return i==bodies.end()?nullptr:i->second.get(); }
MjSpace *MjPhysicsServer3D::space(const RID &r) const { auto i=spaces.find(r.get_id()); return i==spaces.end()?nullptr:i->second.get(); }
MjShape *MjPhysicsServer3D::shape(const RID &r) const { auto i=shapes.find(r.get_id()); return i==shapes.end()?nullptr:i->second.get(); }
void MjPhysicsServer3D::dirty(const RID &r) { if(auto *s=space(r)) s->dirty=true; }
MjPhysicsServer3D::~MjPhysicsServer3D() { _finish(); }
void MjPhysicsServer3D::_finish() { while(!bodies.empty()) _free_rid(bodies.begin()->second->rid); while(!spaces.empty()) _free_rid(spaces.begin()->second->rid); while(!shapes.empty()) _free_rid(shapes.begin()->second->rid); }
RID MjPhysicsServer3D::make_shape(ShapeType type,const Variant &data) { RID r=handles.make_rid(0); auto s=std::make_unique<MjShape>(); s->rid=r;s->type=type;s->data=data; shapes.emplace(r.get_id(),std::move(s)); return r; }
RID MjPhysicsServer3D::_box_shape_create() { return make_shape(SHAPE_BOX,Vector3(0.5,0.5,0.5)); }
RID MjPhysicsServer3D::_sphere_shape_create() { return make_shape(SHAPE_SPHERE,0.5); }
RID MjPhysicsServer3D::_world_boundary_shape_create() { return make_shape(SHAPE_WORLD_BOUNDARY,Plane(Vector3(0,1,0),0)); }
void MjPhysicsServer3D::_shape_set_data(const RID&r,const Variant&v) { auto*s=shape(r); ERR_FAIL_NULL(s); if(s->type==SHAPE_BOX) { ERR_FAIL_COND(v.get_type()!=Variant::VECTOR3); Vector3 z=v; ERR_FAIL_COND(!z.is_finite()||z.x<=0||z.y<=0||z.z<=0); } else if(s->type==SHAPE_SPHERE) { ERR_FAIL_COND(!std::isfinite(double(v))||double(v)<=0); } else { ERR_FAIL_COND(v.get_type()!=Variant::PLANE); Plane plane=v; ERR_FAIL_COND(!plane.normal.is_finite()||plane.normal.length_squared()<1e-12||!std::isfinite(plane.d)); } s->data=v; for(auto &b:bodies) for(auto &i:b.second->shapes) if(i.shape==r) dirty(b.second->space); }
Variant MjPhysicsServer3D::_shape_get_data(const RID&r) const { auto*s=shape(r);return s?s->data:Variant(); }
PhysicsServer3D::ShapeType MjPhysicsServer3D::_shape_get_type(const RID&r) const { auto*s=shape(r);return s?s->type:SHAPE_CUSTOM; }
void MjPhysicsServer3D::_shape_set_margin(const RID&r,float v) { if(auto*s=shape(r)) s->margin=v; }
float MjPhysicsServer3D::_shape_get_margin(const RID&r) const { auto*s=shape(r);return s?s->margin:0; }
void MjPhysicsServer3D::_shape_set_custom_solver_bias(const RID&,float v) { if(v!=0) mj_unsupported("custom solver bias"); }
float MjPhysicsServer3D::_shape_get_custom_solver_bias(const RID&) const { return 0; }
RID MjPhysicsServer3D::_space_create() { RID r=handles.make_rid(0); auto s=std::make_unique<MjSpace>();s->rid=r;s->direct=memnew(MjDirectSpaceState);s->direct->server=this;s->direct->rid=r; spaces.emplace(r.get_id(),std::move(s));return r; }
void MjPhysicsServer3D::_space_set_active(const RID&r,bool v) { if(auto*s=space(r))s->active=v; }
bool MjPhysicsServer3D::_space_is_active(const RID&r) const {auto*s=space(r);return s&&s->active;}
PhysicsDirectSpaceState3D *MjPhysicsServer3D::_space_get_direct_state(const RID&r) {auto*s=space(r);return s?s->direct:nullptr;}
void MjPhysicsServer3D::_space_set_debug_contacts(const RID&,int32_t n) { if(n>0)mj_unsupported("debug contact collection"); }
PackedVector3Array MjPhysicsServer3D::_space_get_contacts(const RID&) const{return {};}
int32_t MjPhysicsServer3D::_space_get_contact_count(const RID&) const{return 0;}
// Godot addresses the world's default environment using its space RID, not an Area RID.
void MjPhysicsServer3D::_area_set_param(const RID&r,AreaParameter p,const Variant&v) {
 auto*s=space(r); if(!s){mj_unsupported("Area3D parameters");return;} s->params[p]=v;
 switch(p){case AREA_PARAM_GRAVITY:s->gravity=double(v);break;case AREA_PARAM_GRAVITY_VECTOR:s->gravity_direction=v;break;case AREA_PARAM_LINEAR_DAMP:s->linear_damp=double(v);break;case AREA_PARAM_ANGULAR_DAMP:s->angular_damp=double(v);break;default:break;} dirty(r);
}
Variant MjPhysicsServer3D::_area_get_param(const RID&r,AreaParameter p) const {auto*s=space(r);if(!s)return {};auto i=s->params.find(p);return i==s->params.end()?Variant():i->second;}
RID MjPhysicsServer3D::_body_create(){RID r=handles.make_rid(0);auto b=std::make_unique<MjBody>();b->rid=r;b->direct=memnew(MjDirectBodyState);b->direct->server=this;b->direct->rid=r;bodies.emplace(r.get_id(),std::move(b));return r;}
void MjPhysicsServer3D::_body_set_space(const RID&r,const RID&s){auto*b=body(r);ERR_FAIL_NULL(b);ERR_FAIL_COND(s.is_valid()&&!space(s));dirty(b->space);b->space=s;b->mj_body=-1;dirty(s);}
RID MjPhysicsServer3D::_body_get_space(const RID&r) const {auto*b=body(r);return b?b->space:RID();}
void MjPhysicsServer3D::_body_set_mode(const RID&r,BodyMode m){auto*b=body(r);ERR_FAIL_NULL(b);if(m!=BODY_MODE_STATIC&&m!=BODY_MODE_RIGID){mj_unsupported("kinematic/rigid-linear body modes");return;}b->mode=m;dirty(b->space);}
PhysicsServer3D::BodyMode MjPhysicsServer3D::_body_get_mode(const RID&r) const {auto*b=body(r);return b?b->mode:BODY_MODE_STATIC;}
void MjPhysicsServer3D::_body_add_shape(const RID&r,const RID&s,const Transform3D&t,bool d){auto*b=body(r);ERR_FAIL_NULL(b);ERR_FAIL_NULL(shape(s));if(!valid_rigid_transform(t))return;b->shapes.push_back({s,t,d});dirty(b->space);}
void MjPhysicsServer3D::_body_set_shape(const RID&r,int32_t i,const RID&s){auto*b=body(r);ERR_FAIL_NULL(b);ERR_FAIL_INDEX(i,b->shapes.size());ERR_FAIL_NULL(shape(s));b->shapes[i].shape=s;dirty(b->space);}
void MjPhysicsServer3D::_body_set_shape_transform(const RID&r,int32_t i,const Transform3D&t){auto*b=body(r);ERR_FAIL_NULL(b);ERR_FAIL_INDEX(i,b->shapes.size());if(!valid_rigid_transform(t))return;b->shapes[i].transform=t;dirty(b->space);}
void MjPhysicsServer3D::_body_set_shape_disabled(const RID&r,int32_t i,bool d){auto*b=body(r);ERR_FAIL_NULL(b);ERR_FAIL_INDEX(i,b->shapes.size());b->shapes[i].disabled=d;dirty(b->space);}
int32_t MjPhysicsServer3D::_body_get_shape_count(const RID&r) const {auto*b=body(r);return b?b->shapes.size():0;}
RID MjPhysicsServer3D::_body_get_shape(const RID&r,int32_t i) const {auto*b=body(r);ERR_FAIL_NULL_V(b,RID());ERR_FAIL_INDEX_V(i,b->shapes.size(),RID());return b->shapes[i].shape;}
Transform3D MjPhysicsServer3D::_body_get_shape_transform(const RID&r,int32_t i) const {auto*b=body(r);ERR_FAIL_NULL_V(b,Transform3D());ERR_FAIL_INDEX_V(i,b->shapes.size(),Transform3D());return b->shapes[i].transform;}
void MjPhysicsServer3D::_body_remove_shape(const RID&r,int32_t i){auto*b=body(r);ERR_FAIL_NULL(b);ERR_FAIL_INDEX(i,b->shapes.size());b->shapes.erase(b->shapes.begin()+i);dirty(b->space);}
void MjPhysicsServer3D::_body_clear_shapes(const RID&r){auto*b=body(r);ERR_FAIL_NULL(b);b->shapes.clear();dirty(b->space);}
void MjPhysicsServer3D::_body_attach_object_instance_id(const RID&r,uint64_t id){if(auto*b=body(r))b->object_id=id;}
uint64_t MjPhysicsServer3D::_body_get_object_instance_id(const RID&r) const {auto*b=body(r);return b?b->object_id:0;}
void MjPhysicsServer3D::_body_set_collision_layer(const RID&r,uint32_t v){if(auto*b=body(r)){b->layer=v;dirty(b->space);}}
uint32_t MjPhysicsServer3D::_body_get_collision_layer(const RID&r) const{auto*b=body(r);return b?b->layer:0;}
void MjPhysicsServer3D::_body_set_collision_mask(const RID&r,uint32_t v){if(auto*b=body(r)){b->mask=v;dirty(b->space);}}
uint32_t MjPhysicsServer3D::_body_get_collision_mask(const RID&r) const{auto*b=body(r);return b?b->mask:0;}
void MjPhysicsServer3D::_body_set_ray_pickable(const RID&r,bool v){if(auto*b=body(r))b->ray_pickable=v;}
void MjPhysicsServer3D::_body_set_param(const RID&r,BodyParameter p,const Variant&v){auto*b=body(r);ERR_FAIL_NULL(b);if(p==BODY_PARAM_MASS){ERR_FAIL_COND(!std::isfinite(double(v))||double(v)<=0);b->mass=double(v);}else if(p==BODY_PARAM_GRAVITY_SCALE)b->gravity_scale=double(v);else if(p==BODY_PARAM_INERTIA){if(Vector3(v)!=Vector3())mj_unsupported("custom inertia");}else if(p==BODY_PARAM_CENTER_OF_MASS){if(Vector3(v)!=Vector3())mj_unsupported("custom center of mass");}else if(p==BODY_PARAM_BOUNCE&&double(v)!=0)mj_unsupported("nonzero bounce");b->params[p]=v;dirty(b->space);}
Variant MjPhysicsServer3D::_body_get_param(const RID&r,BodyParameter p) const{auto*b=body(r);if(!b)return {};if(p==BODY_PARAM_MASS)return b->mass;if(p==BODY_PARAM_GRAVITY_SCALE)return b->gravity_scale;auto i=b->params.find(p);if(i!=b->params.end())return i->second;if(p==BODY_PARAM_INERTIA||p==BODY_PARAM_CENTER_OF_MASS)return Vector3();return p==BODY_PARAM_FRICTION?Variant(1.0):Variant(0.0);}
void MjPhysicsServer3D::_body_reset_mass_properties(const RID&r){if(auto*b=body(r))dirty(b->space);}
void MjPhysicsServer3D::_body_set_state(const RID&r,BodyState p,const Variant&v){auto*b=body(r);ERR_FAIL_NULL(b);switch(p){case BODY_STATE_TRANSFORM:if(!valid_rigid_transform(Transform3D(v)))return;b->transform=v; if(b->mode==BODY_MODE_STATIC)dirty(b->space);break;case BODY_STATE_LINEAR_VELOCITY:b->linear_velocity=v;break;case BODY_STATE_ANGULAR_VELOCITY:b->angular_velocity=v;break;case BODY_STATE_SLEEPING:if(bool(v))mj_unsupported("sleeping (bodies remain simulated)");b->sleeping=false;break;case BODY_STATE_CAN_SLEEP:break;default:break;}write_body(*b);}
Variant MjPhysicsServer3D::_body_get_state(const RID&r,BodyState p) const{auto*b=body(r);if(!b)return {};switch(p){case BODY_STATE_TRANSFORM:return b->transform;case BODY_STATE_LINEAR_VELOCITY:return b->linear_velocity;case BODY_STATE_ANGULAR_VELOCITY:return b->angular_velocity;case BODY_STATE_SLEEPING:return false;case BODY_STATE_CAN_SLEEP:return false;default:return {};}}
void MjPhysicsServer3D::_body_set_state_sync_callback(const RID&r,const Callable&c){if(auto*b=body(r))b->sync_callback=c;}
void MjPhysicsServer3D::_body_set_force_integration_callback(const RID&r,const Callable&c,const Variant&u){if(auto*b=body(r)){b->integration_callback=c;b->integration_userdata=u;}}
PhysicsDirectBodyState3D *MjPhysicsServer3D::_body_get_direct_state(const RID&r){auto*b=body(r);return b?b->direct:nullptr;}
void MjPhysicsServer3D::_body_set_omit_force_integration(const RID&r,bool v){if(auto*b=body(r))b->omit_integration=v;}
bool MjPhysicsServer3D::_body_is_omitting_force_integration(const RID&r) const {auto*b=body(r);return b&&b->omit_integration;}
void MjPhysicsServer3D::_body_set_enable_continuous_collision_detection(const RID&,bool v){if(v)mj_unsupported("continuous collision detection");}
bool MjPhysicsServer3D::_body_is_continuous_collision_detection_enabled(const RID&) const{return false;}
void MjPhysicsServer3D::_body_set_max_contacts_reported(const RID&,int32_t n){if(n>0)mj_unsupported("Godot contact reporting");}
int32_t MjPhysicsServer3D::_body_get_max_contacts_reported(const RID&) const{return 0;}
void MjPhysicsServer3D::_body_set_axis_lock(const RID&,BodyAxis,bool v){if(v)mj_unsupported("body axis locks");}
bool MjPhysicsServer3D::_body_is_axis_locked(const RID&,BodyAxis) const{return false;}
void MjPhysicsServer3D::_body_set_collision_priority(const RID&,float v){if(v!=1)mj_unsupported("collision priority");}
float MjPhysicsServer3D::_body_get_collision_priority(const RID&) const{return 1;}
void MjPhysicsServer3D::_body_add_collision_exception(const RID&r,const RID&e){if(auto*b=body(r)){b->exceptions.insert(e.get_id());dirty(b->space);}}
void MjPhysicsServer3D::_body_remove_collision_exception(const RID&r,const RID&e){if(auto*b=body(r)){b->exceptions.erase(e.get_id());dirty(b->space);}}
TypedArray<RID> MjPhysicsServer3D::_body_get_collision_exceptions(const RID&r) const{TypedArray<RID>a;if(auto*b=body(r))for(auto id:b->exceptions){auto i=bodies.find(id);if(i!=bodies.end())a.push_back(i->second->rid);}return a;}
void MjPhysicsServer3D::_free_rid(const RID&source_rid){
 const RID r=source_rid; // Owners may erase the object that supplied this RID reference.
 if(flushing){pending_free.insert(r.get_id());return;}
 if(auto*b=body(r)){dirty(b->space);if(b->direct)memdelete(b->direct);bodies.erase(r.get_id());}
 else if(space(r)){for(auto &b:bodies)if(b.second->space==r){b.second->space=RID();b.second->mj_body=-1;}spaces.erase(r.get_id());}
 else if(shape(r)){for(auto &b:bodies){auto &s=b.second->shapes;auto n=s.size();s.erase(std::remove_if(s.begin(),s.end(),[&](auto&i){return i.shape==r;}),s.end());if(s.size()!=n)dirty(b.second->space);}shapes.erase(r.get_id());}
 else return;
 handles.free(r);
}
static void vector_xml(std::ostream&o,const Vector3&v){o<<v.x<<' '<<v.y<<' '<<v.z;}
static void pose_xml(std::ostream&o,const Transform3D&t){o<<" pos=\"";vector_xml(o,godot_to_mj(t.origin));Quaternion q=godot_to_mj(t.basis.orthonormalized()).get_rotation_quaternion();o<<"\" quat=\""<<q.w<<' '<<q.x<<' '<<q.y<<' '<<q.z<<"\"";}
bool MjPhysicsServer3D::rebuild(MjSpace&s){
 if(!s.dirty)return s.model&&s.data;
 std::ostringstream xml;xml.imbue(std::locale::classic());xml<<std::setprecision(17)<<"<mujoco model=\"GodotPhysicsSpace\"><compiler angle=\"radian\" fusestatic=\"false\"/><option timestep=\"0.002\" gravity=\"";vector_xml(xml,godot_to_mj(s.gravity_direction*s.gravity));xml<<"\"/><worldbody>";
 std::vector<std::pair<RID,int>> owners;
 for(auto &entry:bodies){auto&b=*entry.second;if(b.space!=s.rid)continue;
 xml<<"<body name=\"b"<<b.rid.get_id()<<"\"";pose_xml(xml,b.transform);xml<<">";
 if(b.mode==BODY_MODE_RIGID)xml<<"<freejoint/>";
 int count=0;for(auto&i:b.shapes)if(!i.disabled&&shape(i.shape)&&shape(i.shape)->type!=SHAPE_WORLD_BOUNDARY)++count;
 if(b.mode==BODY_MODE_RIGID&&count==0)xml<<"<inertial pos=\"0 0 0\" mass=\""<<b.mass<<"\" diaginertia=\"0.001 0.001 0.001\"/>";
 for(int j=0;j<int(b.shapes.size());++j){auto&i=b.shapes[j];auto*sh=shape(i.shape);if(i.disabled||!sh)continue;if(sh->type==SHAPE_WORLD_BOUNDARY&&b.mode!=BODY_MODE_STATIC){mj_unsupported("WorldBoundaryShape3D on dynamic body");continue;}
 Transform3D t=i.transform;Vector3 scale=t.basis.get_scale().abs()*b.transform.basis.get_scale().abs();
 xml<<"<geom name=\"g"<<owners.size()<<"\" type=\"";
 if(sh->type==SHAPE_BOX){xml<<"box\" size=\"";Vector3 v=Vector3(sh->data)*scale;vector_xml(xml,Vector3(v.x,v.z,v.y));}
 else if(sh->type==SHAPE_SPHERE){if(!Math::is_equal_approx(scale.x,scale.y)||!Math::is_equal_approx(scale.x,scale.z))mj_unsupported("nonuniform sphere scale");xml<<"sphere\" size=\""<<double(sh->data)*scale.x;}
 else {Plane p=sh->data;Vector3 n=p.normal.normalized(); t.origin+=t.basis.xform(n*(p.d/p.normal.length())); t.basis=t.basis.orthonormalized()*Basis(Quaternion(Vector3(0,1,0),n)); xml<<"plane\" size=\"0 0 0.1";}
 xml<<"\"";pose_xml(xml,t);
 // A Godot +Y plane normal maps to the MuJoCo primitive's native +Z.
 xml<<" contype=\""<<int32_t(b.layer)<<"\" conaffinity=\""<<int32_t(b.mask)<<"\" friction=\""<<double(_body_get_param(b.rid,BODY_PARAM_FRICTION))<<" 0.005 0.0001\"";
 if(b.mode==BODY_MODE_RIGID)xml<<" mass=\""<<b.mass/std::max(count,1)<<"\"";
 xml<<"/>";owners.push_back({b.rid,j});}
 xml<<"</body>";}
 xml<<"</worldbody><contact>";std::set<std::pair<uint64_t,uint64_t>> exclusions;
 for(auto &entry:bodies){auto&b=*entry.second;if(b.space!=s.rid)continue;for(auto id:b.exceptions){auto i=bodies.find(id);if(i!=bodies.end()&&i->second->space==s.rid&&id!=b.rid.get_id())exclusions.emplace(std::min<uint64_t>(id,b.rid.get_id()),std::max<uint64_t>(id,b.rid.get_id()));}}
 for(auto p:exclusions)xml<<"<exclude body1=\"b"<<p.first<<"\" body2=\"b"<<p.second<<"\"/>";
 xml<<"</contact></mujoco>";
 char error[2048]={};mjSpec *spec=mj_parseXMLString(xml.str().c_str(),nullptr,error,sizeof(error));mjModel*model=spec?mj_compile(spec,nullptr):nullptr;
 if(!model){UtilityFunctions::push_error(String("MuJoCo backend model compile failed: ")+String::utf8(spec?mjs_getError(spec):error));if(spec)mj_deleteSpec(spec);return false;}
 mj_deleteSpec(spec);mjData*data=mj_makeData(model);if(!data){mj_deleteModel(model);return false;}
 double time=s.data?s.data->time:0;if(s.data)mj_deleteData(s.data);if(s.model)mj_deleteModel(s.model);s.model=model;s.data=data;s.data->time=time;s.geom_owners=std::move(owners);s.dirty=false;
 for(auto &entry:bodies){auto&b=*entry.second;if(b.space!=s.rid)continue;std::string name="b"+std::to_string(b.rid.get_id());b.mj_body=mj_name2id(model,mjOBJ_BODY,name.c_str());write_body(b);}
 mj_forward(model,data);return true;
}
void MjPhysicsServer3D::write_body(MjBody&b){auto*s=space(b.space);if(!s||s->dirty||!s->model||b.mj_body<1||b.mode!=BODY_MODE_RIGID)return;int j=s->model->body_jntadr[b.mj_body];if(j<0)return;int q=s->model->jnt_qposadr[j],v=s->model->jnt_dofadr[j];Vector3 p=godot_to_mj(b.transform.origin);Quaternion quat=godot_to_mj(b.transform.basis.orthonormalized()).get_rotation_quaternion();for(int k=0;k<3;++k)s->data->qpos[q+k]=p[k];s->data->qpos[q+3]=quat.w;s->data->qpos[q+4]=quat.x;s->data->qpos[q+5]=quat.y;s->data->qpos[q+6]=quat.z;Vector3 lv=godot_to_mj(b.linear_velocity),av=godot_to_mj(b.transform.basis.orthonormalized().transposed().xform(b.angular_velocity));for(int k=0;k<3;++k){s->data->qvel[v+k]=lv[k];s->data->qvel[v+3+k]=av[k];}mj_forward(s->model,s->data);}
void MjPhysicsServer3D::read_body(MjBody&b){auto*s=space(b.space);if(!s||!s->model||b.mj_body<1||b.mode!=BODY_MODE_RIGID)return;int j=s->model->body_jntadr[b.mj_body];if(j<0)return;int q=s->model->jnt_qposadr[j],v=s->model->jnt_dofadr[j];auto*d=s->data;b.transform.origin=mj_to_godot(Vector3(d->qpos[q],d->qpos[q+1],d->qpos[q+2]));Vector3 scale=b.transform.basis.get_scale();b.transform.basis=mj_to_godot(Basis(Quaternion(d->qpos[q+4],d->qpos[q+5],d->qpos[q+6],d->qpos[q+3])));b.linear_velocity=mj_to_godot(Vector3(d->qvel[v],d->qvel[v+1],d->qvel[v+2]));b.angular_velocity=b.transform.basis.xform(mj_to_godot(Vector3(d->qvel[v+3],d->qvel[v+4],d->qvel[v+5])));b.transform.basis.scale_local(scale);}
void MjPhysicsServer3D::_set_active(bool v){active=v;}
void MjPhysicsServer3D::_init(){}
void MjPhysicsServer3D::_sync(){}
void MjPhysicsServer3D::_end_sync(){}
bool MjPhysicsServer3D::_is_flushing_queries() const{return flushing;}
void MjPhysicsServer3D::_step(float dt){
 if(!active||dt<=0)return;last_step=dt;
 // Each Godot fixed tick advances each active space exactly dt. Subdivide, don't
 // accumulate another autonomous clock (MjWorld owns entirely separate models).
 for(auto &entry:spaces){auto&s=*entry.second;if(!s.active||!rebuild(s))continue;
 const int steps=std::max(1,int(std::ceil(double(dt)/0.002)));s.model->opt.timestep=double(dt)/steps;
 for(int n=0;n<steps;++n){
 for(auto &be:bodies){auto&b=*be.second;if(b.space!=s.rid||b.mode!=BODY_MODE_RIGID||b.mj_body<1)continue;
 Vector3 f=b.force+b.constant_force;f+=s.gravity_direction*s.gravity*b.mass*((b.omit_integration?0:b.gravity_scale)-1);Vector3 torque=b.torque+b.constant_torque;f=godot_to_mj(f);torque=godot_to_mj(torque);
 for(int k=0;k<3;++k){s.data->xfrc_applied[6*b.mj_body+k]=f[k];s.data->xfrc_applied[6*b.mj_body+3+k]=torque[k];}
 int j=s.model->body_jntadr[b.mj_body],v=s.model->jnt_dofadr[j];double ld=double(_body_get_param(b.rid,BODY_PARAM_LINEAR_DAMP)),ad=double(_body_get_param(b.rid,BODY_PARAM_ANGULAR_DAMP));if(int(_body_get_param(b.rid,BODY_PARAM_LINEAR_DAMP_MODE))==0)ld+=s.linear_damp;if(int(_body_get_param(b.rid,BODY_PARAM_ANGULAR_DAMP_MODE))==0)ad+=s.angular_damp;if(b.omit_integration)ld=ad=0;
 for(int k=0;k<3;++k){s.data->qvel[v+k]*=std::max(0.0,1-ld*s.model->opt.timestep);s.data->qvel[v+3+k]*=std::max(0.0,1-ad*s.model->opt.timestep);}}
 mj_step(s.model,s.data);}
 mj_forward(s.model,s.data);
 for(auto &be:bodies){auto&b=*be.second;if(b.space==s.rid){read_body(b);b.force=Vector3();b.torque=Vector3();}}
 }
}
void MjPhysicsServer3D::_flush_queries(){flushing=true;std::vector<RID> snapshot;for(auto&b:bodies)snapshot.push_back(b.second->rid);for(auto r:snapshot){auto*b=body(r);if(!b||pending_free.count(r.get_id())||!space(b->space)||!space(b->space)->active)continue;if(b->integration_callback.is_valid()){Callable c=b->integration_callback;Variant u=b->integration_userdata;auto*d=b->direct;if(u.get_type()==Variant::NIL)c.call(d);else c.call(d,u);}b=body(r);if(b&&!pending_free.count(r.get_id())&&b->sync_callback.is_valid()){Callable c=b->sync_callback;c.call(b->direct);}}flushing=false; auto pending=std::move(pending_free);pending_free.clear();for(auto id:pending){auto b=bodies.find(id);if(b!=bodies.end())_free_rid(b->second->rid);else {auto s=spaces.find(id);if(s!=spaces.end())_free_rid(s->second->rid);else {auto sh=shapes.find(id);if(sh!=shapes.end())_free_rid(sh->second->rid);}}}}
int32_t MjPhysicsServer3D::_get_process_info(ProcessInfo p){if(p==INFO_ACTIVE_OBJECTS)return bodies.size();if(p==INFO_ISLAND_COUNT)return spaces.size();if(p==INFO_COLLISION_PAIRS){int count=0;for(auto&s:spaces)if(s.second->data)count+=s.second->data->ncon;return count;}return 0;}
}
