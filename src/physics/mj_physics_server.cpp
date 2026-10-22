#include "mj_state_transfer.h"
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
void MjPhysicsServer3D::dirty(const RID &r) { if(auto *s=space(r)) s->dirty=true; for(auto &entry:bodies)if(entry.second->space==r)entry.second->contacts.clear(); }
MjPhysicsServer3D::~MjPhysicsServer3D() { _finish(); }
void MjPhysicsServer3D::_finish() { area_commands.clear();area_scratch.reset(); while(!areas.empty()) _free_rid(areas.begin()->second->rid); while(!bodies.empty()) _free_rid(bodies.begin()->second->rid); while(!spaces.empty()) _free_rid(spaces.begin()->second->rid); while(!shapes.empty()) _free_rid(shapes.begin()->second->rid); }
RID MjPhysicsServer3D::make_shape(ShapeType type,const Variant &data) { RID r=handles.make_rid(0); auto s=std::make_unique<MjShape>(); s->rid=r;s->type=type;s->data=data; shapes.emplace(r.get_id(),std::move(s)); return r; }
RID MjPhysicsServer3D::_box_shape_create() { return make_shape(SHAPE_BOX,Vector3(0.5,0.5,0.5)); }
RID MjPhysicsServer3D::_sphere_shape_create() { return make_shape(SHAPE_SPHERE,0.5); }
RID MjPhysicsServer3D::_cylinder_shape_create() {
 Dictionary data; data["radius"]=0.5; data["height"]=2.0;
 return make_shape(SHAPE_CYLINDER,data);
}
RID MjPhysicsServer3D::_world_boundary_shape_create() { return make_shape(SHAPE_WORLD_BOUNDARY,Plane(Vector3(0,1,0),0)); }
void MjPhysicsServer3D::_shape_set_data(const RID&r,const Variant&v) { auto*s=shape(r); ERR_FAIL_NULL(s); if(s->type==SHAPE_BOX) { ERR_FAIL_COND(v.get_type()!=Variant::VECTOR3); Vector3 z=v; ERR_FAIL_COND(!z.is_finite()||z.x<=0||z.y<=0||z.z<=0); } else if(s->type==SHAPE_SPHERE) { ERR_FAIL_COND(!std::isfinite(double(v))||double(v)<=0); } else if(s->type==SHAPE_CYLINDER) {
 ERR_FAIL_COND_MSG(v.get_type()!=Variant::DICTIONARY,"Cylinder data requires radius and height");
 Dictionary data=v;
 for(const char *key:{"radius","height"}) {
  ERR_FAIL_COND_MSG(!data.has(key),"Cylinder data requires radius and height");
  Variant value=data[key];
  ERR_FAIL_COND_MSG(value.get_type()!=Variant::FLOAT&&value.get_type()!=Variant::INT,"Cylinder dimensions must be numeric");
  ERR_FAIL_COND_MSG(!std::isfinite(double(value))||double(value)<=0,"Cylinder dimensions must be finite and positive");
 }
 } else { ERR_FAIL_COND(v.get_type()!=Variant::PLANE); Plane plane=v; ERR_FAIL_COND(!plane.normal.is_finite()||plane.normal.length_squared()<1e-12||!std::isfinite(plane.d)); } s->data=s->type==SHAPE_CYLINDER?Variant(Dictionary(v).duplicate()):v; for(auto &b:bodies) for(auto &i:b.second->shapes) if(i.shape==r) dirty(b.second->space); }
Variant MjPhysicsServer3D::_shape_get_data(const RID&r) const { auto*s=shape(r);return s?(s->type==SHAPE_CYLINDER?Variant(Dictionary(s->data).duplicate()):s->data):Variant(); }
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
 if(auto*a=area(r)){
  if(flushing){area_commands.push_back([this,r,p,v]{_area_set_param(r,p,v);});return;}
  set_area_environment_param(*a,p,v);return;
 }
 auto*s=space(r); if(!s)return;
 if(s->authored_options&&(p==AREA_PARAM_GRAVITY||p==AREA_PARAM_GRAVITY_VECTOR)){s->last_error="Runtime world model owns gravity; Godot default-area override rejected";return;}
 if(p==AREA_PARAM_GRAVITY_VECTOR){ERR_FAIL_COND(v.get_type()!=Variant::VECTOR3||!Vector3(v).is_finite());}
 else if(p==AREA_PARAM_GRAVITY||p==AREA_PARAM_LINEAR_DAMP||p==AREA_PARAM_ANGULAR_DAMP){
  ERR_FAIL_COND((v.get_type()!=Variant::FLOAT&&v.get_type()!=Variant::INT)||!std::isfinite(double(v))||!std::isfinite(float(double(v))));
  ERR_FAIL_COND(p!=AREA_PARAM_GRAVITY&&double(v)<0);
 }
 Vector3 gravity_direction=p==AREA_PARAM_GRAVITY_VECTOR?Vector3(v):s->gravity_direction;
 double gravity=p==AREA_PARAM_GRAVITY?double(v):s->gravity;
 ERR_FAIL_COND(!(gravity_direction*gravity).is_finite());
 for(auto &entry:bodies){auto &b=*entry.second;if(b.space!=r)continue;
  ERR_FAIL_COND(!(gravity_direction*(gravity*b.gravity_scale)).is_finite());
  if(p==AREA_PARAM_LINEAR_DAMP||p==AREA_PARAM_ANGULAR_DAMP){
   bool angular=p==AREA_PARAM_ANGULAR_DAMP;
   auto mode=angular?BODY_PARAM_ANGULAR_DAMP_MODE:BODY_PARAM_LINEAR_DAMP_MODE;
   auto damp=angular?BODY_PARAM_ANGULAR_DAMP:BODY_PARAM_LINEAR_DAMP;
   ERR_FAIL_COND(int(_body_get_param(b.rid,mode))==0&&!std::isfinite(float(double(v)+double(_body_get_param(b.rid,damp)))));
  }
 }
 s->params[p]=v;
 switch(p){case AREA_PARAM_GRAVITY:s->gravity=double(v);break;case AREA_PARAM_GRAVITY_VECTOR:s->gravity_direction=v;break;case AREA_PARAM_LINEAR_DAMP:s->linear_damp=double(v);break;case AREA_PARAM_ANGULAR_DAMP:s->angular_damp=double(v);break;default:break;} dirty(r);
}
Variant MjPhysicsServer3D::_area_get_param(const RID&r,AreaParameter p) const {if(auto*a=area(r)){auto i=a->params.find(p);return i==a->params.end()?Variant():i->second;}auto*s=space(r);if(!s)return {};auto i=s->params.find(p);return i==s->params.end()?Variant():i->second;}
RID MjPhysicsServer3D::_body_create(){RID r=handles.make_rid(0);auto b=std::make_unique<MjBody>();b->rid=r;b->direct=memnew(MjDirectBodyState);b->direct->server=this;b->direct->rid=r;bodies.emplace(r.get_id(),std::move(b));return r;}
void MjPhysicsServer3D::_body_set_space(const RID&r,const RID&s){if(flushing){area_commands.push_back([this,r,s]{_body_set_space(r,s);});return;}auto*b=body(r);if(!b)return;if(b->space==s)return;ERR_FAIL_COND(s.is_valid()&&!space(s));if(auto*target=space(s)){ERR_FAIL_COND(!(target->gravity_direction*(target->gravity*b->gravity_scale)).is_finite());
 for(bool angular:{false,true}){auto mode=angular?BODY_PARAM_ANGULAR_DAMP_MODE:BODY_PARAM_LINEAR_DAMP_MODE;auto damp=angular?BODY_PARAM_ANGULAR_DAMP:BODY_PARAM_LINEAR_DAMP;
 ERR_FAIL_COND(int(_body_get_param(r,mode))==0&&!std::isfinite(float(double(_body_get_param(r,damp))+(angular?target->angular_damp:target->linear_damp))));}}dirty(b->space);b->space=s;b->mj_body=-1;b->callback_pending=false;b->sync_pending=false;b->environment_valid=false;dirty(s);retire_area_pairs(r);}
RID MjPhysicsServer3D::_body_get_space(const RID&r) const {auto*b=body(r);return b?b->space:RID();}
void MjPhysicsServer3D::_body_set_mode(const RID&r,BodyMode m){auto*b=body(r);ERR_FAIL_NULL(b);if(m!=BODY_MODE_STATIC&&m!=BODY_MODE_RIGID){mj_unsupported("kinematic/rigid-linear body modes");return;}b->mode=m;dirty(b->space);}
PhysicsServer3D::BodyMode MjPhysicsServer3D::_body_get_mode(const RID&r) const {auto*b=body(r);return b?b->mode:BODY_MODE_STATIC;}
// All shape-list mutations share one FIFO during callbacks. Validate indices
// when dequeued, against the result of preceding add/remove/clear operations.
#define DEFER_BODY_SHAPE(call) if(flushing){area_commands.push_back([=]{call;});return;}
void MjPhysicsServer3D::_body_add_shape(const RID&r,const RID&s,const Transform3D&t,bool d){DEFER_BODY_SHAPE(_body_add_shape(r,s,t,d));auto*b=body(r);ERR_FAIL_NULL(b);ERR_FAIL_NULL(shape(s));if(!valid_rigid_transform(t))return;b->shapes.push_back({s,t,d});dirty(b->space);}
void MjPhysicsServer3D::_body_set_shape(const RID&r,int32_t i,const RID&s){DEFER_BODY_SHAPE(_body_set_shape(r,i,s));auto*b=body(r);ERR_FAIL_NULL(b);ERR_FAIL_INDEX(i,b->shapes.size());ERR_FAIL_NULL(shape(s));b->shapes[i].shape=s;dirty(b->space);}
void MjPhysicsServer3D::_body_set_shape_transform(const RID&r,int32_t i,const Transform3D&t){DEFER_BODY_SHAPE(_body_set_shape_transform(r,i,t));auto*b=body(r);ERR_FAIL_NULL(b);ERR_FAIL_INDEX(i,b->shapes.size());if(!valid_rigid_transform(t))return;b->shapes[i].transform=t;dirty(b->space);}
void MjPhysicsServer3D::_body_set_shape_disabled(const RID&r,int32_t i,bool d){DEFER_BODY_SHAPE(_body_set_shape_disabled(r,i,d));auto*b=body(r);ERR_FAIL_NULL(b);ERR_FAIL_INDEX(i,b->shapes.size());b->shapes[i].disabled=d;dirty(b->space);}
int32_t MjPhysicsServer3D::_body_get_shape_count(const RID&r) const {auto*b=body(r);return b?b->shapes.size():0;}
RID MjPhysicsServer3D::_body_get_shape(const RID&r,int32_t i) const {auto*b=body(r);ERR_FAIL_NULL_V(b,RID());ERR_FAIL_INDEX_V(i,b->shapes.size(),RID());return b->shapes[i].shape;}
Transform3D MjPhysicsServer3D::_body_get_shape_transform(const RID&r,int32_t i) const {auto*b=body(r);ERR_FAIL_NULL_V(b,Transform3D());ERR_FAIL_INDEX_V(i,b->shapes.size(),Transform3D());return b->shapes[i].transform;}
void MjPhysicsServer3D::_body_remove_shape(const RID&r,int32_t i){DEFER_BODY_SHAPE(_body_remove_shape(r,i));auto*b=body(r);if(!b)return;ERR_FAIL_INDEX(i,b->shapes.size());b->shapes.erase(b->shapes.begin()+i);dirty(b->space);retire_area_pairs(r,i);}
void MjPhysicsServer3D::_body_clear_shapes(const RID&r){DEFER_BODY_SHAPE(_body_clear_shapes(r));auto*b=body(r);if(!b)return;b->shapes.clear();dirty(b->space);retire_area_pairs(r);}
#undef DEFER_BODY_SHAPE
void MjPhysicsServer3D::_body_attach_object_instance_id(const RID&r,uint64_t id){if(auto*b=body(r))b->object_id=id;}
uint64_t MjPhysicsServer3D::_body_get_object_instance_id(const RID&r) const {auto*b=body(r);return b?b->object_id:0;}
void MjPhysicsServer3D::_body_set_collision_layer(const RID&r,uint32_t v){if(auto*b=body(r)){b->layer=v;dirty(b->space);}}
uint32_t MjPhysicsServer3D::_body_get_collision_layer(const RID&r) const{auto*b=body(r);return b?b->layer:0;}
void MjPhysicsServer3D::_body_set_collision_mask(const RID&r,uint32_t v){if(auto*b=body(r)){b->mask=v;dirty(b->space);}}
uint32_t MjPhysicsServer3D::_body_get_collision_mask(const RID&r) const{auto*b=body(r);return b?b->mask:0;}
void MjPhysicsServer3D::_body_set_ray_pickable(const RID&r,bool v){if(auto*b=body(r))b->ray_pickable=v;}
void MjPhysicsServer3D::_body_set_param(const RID&r,BodyParameter p,const Variant&v){
 auto*b=body(r);ERR_FAIL_NULL(b);
 if(p==BODY_PARAM_INERTIA||p==BODY_PARAM_CENTER_OF_MASS){
  ERR_FAIL_COND(v.get_type()!=Variant::VECTOR3||!Vector3(v).is_finite());
  if(Vector3(v)!=Vector3()){mj_unsupported(p==BODY_PARAM_INERTIA?"custom inertia":"custom center of mass");return;}
 }else{
  ERR_FAIL_COND(v.get_type()!=Variant::FLOAT&&v.get_type()!=Variant::INT);
  double value=v;ERR_FAIL_COND(!std::isfinite(value)||!std::isfinite(float(value)));
  switch(p){
   case BODY_PARAM_MASS:ERR_FAIL_COND(value<=0);b->mass=value;break;
   case BODY_PARAM_GRAVITY_SCALE:if(auto*s=space(b->space)){ERR_FAIL_COND(!(s->gravity_direction*(s->gravity*value)).is_finite());}b->gravity_scale=value;break;
   case BODY_PARAM_FRICTION:break; // Negative means PhysicsMaterial.rough.
   case BODY_PARAM_LINEAR_DAMP:case BODY_PARAM_ANGULAR_DAMP:ERR_FAIL_COND(value<0);break;
   case BODY_PARAM_LINEAR_DAMP_MODE:case BODY_PARAM_ANGULAR_DAMP_MODE:ERR_FAIL_COND(value!=0&&value!=1);break;
   case BODY_PARAM_BOUNCE:if(value!=0){mj_unsupported("nonzero bounce");return;}break;
   default:mj_unsupported("body parameter");return;
  }
 }
 if(auto*s=space(b->space))for(bool angular:{false,true}){
  auto mode=angular?BODY_PARAM_ANGULAR_DAMP_MODE:BODY_PARAM_LINEAR_DAMP_MODE;
  auto damp=angular?BODY_PARAM_ANGULAR_DAMP:BODY_PARAM_LINEAR_DAMP;
  int selected=p==mode?int(v):int(_body_get_param(r,mode));
  double amount=p==damp?double(v):double(_body_get_param(r,damp));
  ERR_FAIL_COND(selected==0&&!std::isfinite(float(amount+(angular?s->angular_damp:s->linear_damp))));
 }
 b->params[p]=v;dirty(b->space);
}
Variant MjPhysicsServer3D::_body_get_param(const RID&r,BodyParameter p) const{auto*b=body(r);if(!b)return {};if(p==BODY_PARAM_MASS)return b->mass;if(p==BODY_PARAM_GRAVITY_SCALE)return b->gravity_scale;auto i=b->params.find(p);if(i!=b->params.end())return i->second;if(p==BODY_PARAM_INERTIA||p==BODY_PARAM_CENTER_OF_MASS)return Vector3();return p==BODY_PARAM_FRICTION?Variant(1.0):Variant(0.0);}
void MjPhysicsServer3D::_body_reset_mass_properties(const RID&r){if(auto*b=body(r))dirty(b->space);}
void MjPhysicsServer3D::_body_set_state(const RID&r,BodyState p,const Variant&v){auto*b=body(r);ERR_FAIL_NULL(b);switch(p){case BODY_STATE_TRANSFORM:if(!valid_rigid_transform(Transform3D(v)))return;b->transform=v; if(b->mode==BODY_MODE_STATIC)dirty(b->space);break;case BODY_STATE_LINEAR_VELOCITY:ERR_FAIL_COND(v.get_type()!=Variant::VECTOR3||!Vector3(v).is_finite());b->linear_velocity=v;break;case BODY_STATE_ANGULAR_VELOCITY:ERR_FAIL_COND(v.get_type()!=Variant::VECTOR3||!Vector3(v).is_finite());b->angular_velocity=v;break;case BODY_STATE_SLEEPING:if(bool(v))mj_unsupported("sleeping (bodies remain simulated)");b->sleeping=false;break;case BODY_STATE_CAN_SLEEP:break;default:break;}write_body(*b);}
Variant MjPhysicsServer3D::_body_get_state(const RID&r,BodyState p) const{auto*b=body(r);if(!b)return {};switch(p){case BODY_STATE_TRANSFORM:return b->transform;case BODY_STATE_LINEAR_VELOCITY:return b->linear_velocity;case BODY_STATE_ANGULAR_VELOCITY:return b->angular_velocity;case BODY_STATE_SLEEPING:return false;case BODY_STATE_CAN_SLEEP:return false;default:return {};}}
void MjPhysicsServer3D::_body_set_state_sync_callback(const RID&r,const Callable&c){if(auto*b=body(r))b->sync_callback=c;}
void MjPhysicsServer3D::_body_set_force_integration_callback(const RID&r,const Callable&c,const Variant&u){if(auto*b=body(r)){b->integration_callback=c;b->integration_userdata=u;}}
PhysicsDirectBodyState3D *MjPhysicsServer3D::_body_get_direct_state(const RID&r){auto*b=body(r);return b?b->direct:nullptr;}
void MjPhysicsServer3D::_body_set_omit_force_integration(const RID&r,bool v){if(auto*b=body(r))b->omit_integration=v;}
bool MjPhysicsServer3D::_body_is_omitting_force_integration(const RID&r) const {auto*b=body(r);return b&&b->omit_integration;}
void MjPhysicsServer3D::_body_set_enable_continuous_collision_detection(const RID&,bool v){if(v)mj_unsupported("continuous collision detection");}
bool MjPhysicsServer3D::_body_is_continuous_collision_detection_enabled(const RID&) const{return false;}
void MjPhysicsServer3D::_body_set_max_contacts_reported(const RID&r,int32_t n){ERR_FAIL_COND(n<0);if(auto*b=body(r)){b->max_contacts=n;if(b->contacts.size()>size_t(n))b->contacts.resize(n);}}
int32_t MjPhysicsServer3D::_body_get_max_contacts_reported(const RID&r) const{auto*b=body(r);return b?b->max_contacts:0;}
void MjPhysicsServer3D::_body_set_axis_lock(const RID&,BodyAxis,bool v){if(v)mj_unsupported("body axis locks");}
bool MjPhysicsServer3D::_body_is_axis_locked(const RID&,BodyAxis) const{return false;}
void MjPhysicsServer3D::_body_set_collision_priority(const RID&,float v){if(v!=1)mj_unsupported("collision priority");}
float MjPhysicsServer3D::_body_get_collision_priority(const RID&) const{return 1;}
void MjPhysicsServer3D::_body_add_collision_exception(const RID&r,const RID&e){if(auto*b=body(r)){b->exceptions.insert(e.get_id());dirty(b->space);}}
void MjPhysicsServer3D::_body_remove_collision_exception(const RID&r,const RID&e){if(auto*b=body(r)){b->exceptions.erase(e.get_id());dirty(b->space);}}
TypedArray<RID> MjPhysicsServer3D::_body_get_collision_exceptions(const RID&r) const{TypedArray<RID>a;if(auto*b=body(r))for(auto id:b->exceptions){auto i=bodies.find(id);if(i!=bodies.end())a.push_back(i->second->rid);}return a;}
void MjPhysicsServer3D::_free_rid(const RID&source_rid){
 const RID r=source_rid; // Owners may erase the object that supplied this RID reference.
 // Model-instance RIDs obey the same paused transaction contract even when
 // released through the generic server API. Do not erase a live spec first.
 for(auto &entry:spaces)if(entry.second->imported.count(r.get_id())){
  if(!(entry.second->imported.at(r.get_id())->whole_model?scene_release_model(entry.second->rid,r):scene_remove(entry.second->rid,r)))UtilityFunctions::push_error("MuJoCo model instance removal requires a paused space outside callbacks");
  return;
 }
 // Invalidate snapshots before deferred destruction as callbacks may query peers.
 // A shared shape RID can invalidate both owners and the peers reporting them.
 std::set<uint64_t> affected;
 if(shape(r))for(auto &entry:bodies)for(auto &instance:entry.second->shapes)
  if(instance.shape==r)affected.insert(entry.first);
 for(auto &entry:bodies){auto &b=*entry.second;
  if(b.rid==r||b.space==r||affected.count(b.rid.get_id()))b.contacts.clear();
  else b.contacts.erase(std::remove_if(b.contacts.begin(),b.contacts.end(),[&](const MjContact &c){return c.collider==r||affected.count(c.collider.get_id());}),b.contacts.end());
 }
 if(flushing){pending_free.insert(r.get_id());return;}
 if(auto*a=area(r)){a->body_callback=Callable();a->area_callback=Callable();}
 retire_area_pairs(r);
 if(auto*b=body(r)){RID terrain_shape=b->heightfield&&!b->shapes.empty()?b->shapes[0].shape:RID();dirty(b->space);if(b->direct)memdelete(b->direct);bodies.erase(r.get_id());heightfield_revisions.erase(r.get_id());if(terrain_shape.is_valid())_free_rid(terrain_shape);}
 else if(area(r)){areas.erase(r.get_id());}
 else if(space(r)){for(auto &a:areas)if(a.second->space==r)a.second->space=RID();for(auto &i:space(r)->imported)handles.free(i.second->rid);for(auto &b:bodies)if(b.second->space==r){b.second->space=RID();b.second->mj_body=-1;}spaces.erase(r.get_id());}
 else if(shape(r)){
  std::vector<std::pair<RID,int>> affected;
  for(auto &entry:areas){auto &a=*entry.second;auto &instances=a.shapes;
   auto first=std::find_if(instances.begin(),instances.end(),[&](const MjShapeInstance&i){return i.shape==r;});
   if(first!=instances.end())affected.push_back({a.rid,int(first-instances.begin())});
   instances.erase(std::remove_if(instances.begin(),instances.end(),[&](const MjShapeInstance&i){return i.shape==r;}),instances.end());
  }
  for(auto &entry:bodies){auto &b=*entry.second;auto &instances=b.shapes;
   auto first=std::find_if(instances.begin(),instances.end(),[&](const MjShapeInstance&i){return i.shape==r;});
   if(first!=instances.end()){affected.push_back({b.rid,int(first-instances.begin())});dirty(b.space);}
   instances.erase(std::remove_if(instances.begin(),instances.end(),[&](const MjShapeInstance&i){return i.shape==r;}),instances.end());
  }
  shapes.erase(r.get_id());for(const auto &entry:affected)retire_area_pairs(entry.first,entry.second);
 }
 else return;
 handles.free(r);
}
static void vector_xml(std::ostream&o,const Vector3&v){o<<v.x<<' '<<v.y<<' '<<v.z;}
static void pose_xml(std::ostream&o,const Transform3D&t){o<<" pos=\"";vector_xml(o,godot_to_mj(t.origin));Quaternion q=godot_to_mj(t.basis.orthonormalized()).get_rotation_quaternion();o<<"\" quat=\""<<q.w<<' '<<q.x<<' '<<q.y<<' '<<q.z<<"\"";}
static double shape_volume(const MjShape &shape){
 if(shape.type==PhysicsServer3D::SHAPE_BOX){Vector3 e=shape.data;return 8.0*e.x*e.y*e.z;}
 if(shape.type==PhysicsServer3D::SHAPE_SPHERE){double r=shape.data;return (4.0/3.0)*Math_PI*r*r*r;}
 if(shape.type==PhysicsServer3D::SHAPE_CYLINDER){Dictionary d=shape.data;double r=d["radius"];return Math_PI*r*r*double(d["height"]);}
 return 0;
}
// Godot exposes COM linear velocity; MuJoCo's free-joint translation is
// the body-frame origin. The difference matters for offset collision shapes.
static Vector3 native_com_offset(const mjModel *model,int body_id,const Transform3D &pose){
 const auto*p=model->body_ipos+3*body_id;
 return pose.basis.xform(mj_to_godot(Vector3(p[0],p[1],p[2])));
}
bool MjPhysicsServer3D::rebuild(MjSpace&s,const Dictionary&control_overrides,bool validate_dynamics){
 if(!s.dirty)return s.model&&s.data;
 std::ostringstream xml;xml.imbue(std::locale::classic());xml<<std::setprecision(17)<<"<mujoco model=\"GodotPhysicsSpace\"><compiler angle=\"radian\" fusestatic=\"false\"/><option timestep=\"0.002\" gravity=\"";vector_xml(xml,godot_to_mj(s.gravity_direction*s.gravity));xml<<"\"/><worldbody>";
 std::vector<std::pair<RID,int>> owners;
 for(auto &entry:bodies){auto&b=*entry.second;if(b.space!=s.rid)continue;
 if(b.heightfield){
 auto*sh=shape(b.shapes[0].shape);Dictionary grid=sh->data;PackedFloat32Array heights=grid["heights"];
 double low=heights[0];for(int k=1;k<heights.size();++k)low=std::min(low,double(heights[k]));
 Transform3D t=b.transform;t.origin+=t.basis.xform(Vector3(0,low,0));
 xml<<"<geom name=\"g"<<owners.size()<<"\" type=\"hfield\" hfield=\"h"<<b.rid.get_id()<<"\"";pose_xml(xml,t);
 xml<<" contype=\""<<int32_t(b.layer)<<"\" conaffinity=\""<<int32_t(b.mask)<<"\" friction=\"1 .005 .0001\"/>";
 owners.push_back({b.rid,0});continue;
 }
 xml<<"<body name=\"b"<<b.rid.get_id()<<"\"";pose_xml(xml,b.transform);xml<<">";
 if(b.mode==BODY_MODE_RIGID)xml<<"<freejoint name=\"native_joint_"<<b.rid.get_id()<<"\"/>";
 int count=0;double volume=0;for(auto&i:b.shapes)if(!i.disabled&&shape(i.shape)&&shape(i.shape)->type!=SHAPE_WORLD_BOUNDARY){++count;volume+=shape_volume(*shape(i.shape));}
 if(count&&(!std::isfinite(volume)||volume<=0)){s.last_error="Native shape volume is not finite and positive";return false;}
 if(b.mode==BODY_MODE_RIGID&&count==0)xml<<"<inertial pos=\"0 0 0\" mass=\""<<b.mass<<"\" diaginertia=\"0.001 0.001 0.001\"/>";
 for(int j=0;j<int(b.shapes.size());++j){auto&i=b.shapes[j];auto*sh=shape(i.shape);if(i.disabled||!sh)continue;if(sh->type==SHAPE_WORLD_BOUNDARY&&b.mode!=BODY_MODE_STATIC){mj_unsupported("WorldBoundaryShape3D on dynamic body");continue;}
 Transform3D t=i.transform;Vector3 scale=t.basis.get_scale().abs()*b.transform.basis.get_scale().abs();
 xml<<"<geom name=\"g"<<owners.size()<<"\" type=\"";
 if(sh->type==SHAPE_BOX){xml<<"box\" size=\"";Vector3 v=Vector3(sh->data)*scale;vector_xml(xml,Vector3(v.x,v.z,v.y));}
 else if(sh->type==SHAPE_SPHERE){if(!Math::is_equal_approx(scale.x,scale.y)||!Math::is_equal_approx(scale.x,scale.z))mj_unsupported("nonuniform sphere scale");xml<<"sphere\" size=\""<<double(sh->data)*scale.x;}
 else if(sh->type==SHAPE_CYLINDER){Dictionary d=sh->data;xml<<"cylinder\" size=\""<<double(d["radius"])<<' '<<double(d["height"])*0.5;}
 else {Plane p=sh->data;Vector3 n=p.normal.normalized(); t.origin+=t.basis.xform(n*(p.d/p.normal.length())); t.basis=t.basis.orthonormalized()*Basis(Quaternion(Vector3(0,1,0),n)); xml<<"plane\" size=\"0 0 0.1";}
 xml<<"\"";pose_xml(xml,t);
 // A Godot +Y plane normal maps to the MuJoCo primitive's native +Z.
 xml<<" contype=\""<<int32_t(b.layer)<<"\" conaffinity=\""<<int32_t(b.mask)<<"\" friction=\""<<std::abs(double(_body_get_param(b.rid,BODY_PARAM_FRICTION)))<<" 0.005 0.0001\"";
 if(b.mode==BODY_MODE_RIGID)xml<<" mass=\""<<b.mass*(shape_volume(*sh)/volume)<<"\"";
 xml<<"/>";owners.push_back({b.rid,j});}
 xml<<"</body>";}
 xml<<"</worldbody><contact>";std::set<std::pair<uint64_t,uint64_t>> exclusions;
 for(auto &entry:bodies){auto&b=*entry.second;if(b.space!=s.rid)continue;for(auto id:b.exceptions){auto i=bodies.find(id);if(i!=bodies.end()&&i->second->space==s.rid&&id!=b.rid.get_id())exclusions.emplace(std::min<uint64_t>(id,b.rid.get_id()),std::max<uint64_t>(id,b.rid.get_id()));}}
 for(auto p:exclusions)xml<<"<exclude body1=\"b"<<p.first<<"\" body2=\"b"<<p.second<<"\"/>";
 // Explicit native pairs use Godot's signed rough-material combination.
 // Imported MJCF contacts keep their authored MuJoCo combination semantics.
 for(size_t i=0;i<owners.size();++i)for(size_t j=i+1;j<owners.size();++j){
  auto*a=body(owners[i].first);auto*b=body(owners[j].first);
  if(a==b||(a->mode==BODY_MODE_STATIC&&b->mode==BODY_MODE_STATIC)||
     !((a->layer&b->mask)||(b->layer&a->mask))||a->exceptions.count(b->rid.get_id())||b->exceptions.count(a->rid.get_id()))continue;
  double friction=std::abs(std::min(double(_body_get_param(a->rid,BODY_PARAM_FRICTION)),double(_body_get_param(b->rid,BODY_PARAM_FRICTION))));
  xml<<"<pair geom1=\"g"<<i<<"\" geom2=\"g"<<j<<"\" condim=\"3\" friction=\""<<friction<<' '<<friction<<" 0 0 0\"/>";
 }
 xml<<"</contact><asset>";
 for(auto &entry:bodies){auto&b=*entry.second;if(b.space!=s.rid||!b.heightfield)continue;
 Dictionary grid=shape(b.shapes[0].shape)->data;PackedFloat32Array h=grid["heights"];int w=grid["width"],d=grid["depth"];
 double low=h[0],high=h[0];for(int k=1;k<h.size();++k){low=std::min(low,double(h[k]));high=std::max(high,double(h[k]));}
 xml<<"<hfield name=\"h"<<b.rid.get_id()<<"\" nrow=\""<<d<<"\" ncol=\""<<w<<"\" size=\""<<(w-1)*.5<<' '<<(d-1)*.5<<' '<<std::max(high-low,1e-6)<<" 1\" elevation=\"";
 for(int k=0;k<h.size();++k)xml<<h[k]<<' ';xml<<"\"/>";
 }
 xml<<"</asset></mujoco>";
 char error[2048]={};mjSpec *spec=mj_parseXMLString(xml.str().c_str(),nullptr,error,sizeof(error));
 if(!spec){s.last_error=String::utf8(error);return false;}
 mjs_setDeepCopy(spec,1);
 if(s.authored_options)spec->option=s.options;else if(!s.imported.empty())spec->option.integrator=mjINT_IMPLICITFAST;
 for(auto &entry:s.imported){
  auto &object=*entry.second;
  auto *frame=mjs_addFrame(mjs_findBody(spec,"world"),nullptr);
  Vector3 pos=godot_to_mj(object.pose.origin);
  Quaternion q=godot_to_mj(object.pose.basis).get_rotation_quaternion();
  for(int k=0;k<3;++k)frame->pos[k]=pos[k];
  frame->quat[0]=q.w;frame->quat[1]=q.x;frame->quat[2]=q.y;frame->quat[3]=q.z;
  auto *root=mjs_findBody(object.spec,"world");
  // A parsed fixed-base URDF may fuse pelvis geometry into its world body.
  // Attach that whole world once so assets and actuator references stay shared.
  // Our free box instead attaches its sole root body directly: a freejoint
  // must remain top-level in the combined model.
  bool free_root=false;
  for(auto *j=mjs_firstElement(object.spec,mjOBJ_JOINT);j;j=mjs_nextElement(object.spec,j))
   if(mjs_asJoint(j)->type==mjJNT_FREE)free_root=true;
  auto *child=(!object.whole_model&&free_root)?mjs_firstChild(root,mjOBJ_BODY,0):root->element;
  auto*attached=child?mjs_attach(frame->element,child,object.prefix.c_str(),""):nullptr;
  if(!attached){s.last_error=String::utf8(mjs_getError(spec));mj_deleteSpec(spec);return false;}
  if(object.whole_model){auto*wrapper=mjs_asBody(attached);if(!wrapper||!mjs_bodyToFrame(&wrapper)){s.last_error="Could not flatten attached model world";mj_deleteSpec(spec);return false;}}

 }
 // Compile entirely off to the side. Never mutate the active model on failure.
 mjModel *model=mj_compile(spec,nullptr);
 if(!model){s.last_error=String::utf8(mjs_getError(spec));mj_deleteSpec(spec);return false;}
 // Attachment must retain every named physical element; never silently drop
 // constraints or actuators when removing the artificial world wrapper.
 for(auto &entry:s.imported){auto&o=*entry.second;if(!o.whole_model)continue;Dictionary counts=o.initial["counts"];
  const mjtObj kinds[]={mjOBJ_GEOM,mjOBJ_JOINT,mjOBJ_ACTUATOR,mjOBJ_EQUALITY,mjOBJ_TENDON,mjOBJ_SENSOR};const char*keys[]={"geom","joint","actuator","equality","tendon","sensor"};const mjtSize sizes[]={model->ngeom,model->njnt,model->nu,model->neq,model->ntendon,model->nsensor};
  for(int k=0;k<6;++k){int found=0;for(int i=0;i<sizes[k];++i){const char*n=mj_id2name(model,kinds[k],i);if(n&&std::string(n).rfind(o.prefix,0)==0)++found;}if(found!=int(counts[keys[k]])){s.last_error="Composition changed model element count: "+String(keys[k]);mj_deleteModel(model);mj_deleteSpec(spec);return false;}}
 }
 mj_deleteSpec(spec);mjData *data=mj_makeData(model);
 if(!data){mj_deleteModel(model);s.last_error="Could not allocate candidate data";return false;}
 // Initialize new bounded joints inside their URDF limits, with matching targets.
 for(int j=0;j<model->njnt;++j)if(model->jnt_type[j]==mjJNT_HINGE && model->jnt_limited[j])
  data->qpos[model->jnt_qposadr[j]]=std::clamp(0.0,model->jnt_range[2*j]+0.001,model->jnt_range[2*j+1]-0.001);
 for(int a=0;a<model->nu;++a)if(model->actuator_trntype[a]==mjTRN_JOINT){int j=model->actuator_trnid[2*a];data->ctrl[a]=data->qpos[model->jnt_qposadr[j]];}
 gmj_transfer_state(s.model,s.data,model,data);
 // Initialize only newly inserted names. Existing instances retain live state.
 for(auto &entry:s.imported){auto&o=*entry.second;if(!o.whole_model)continue;Dictionary joints=o.initial["joints"],controls=o.initial["controls"],activation=o.initial["activation"];Basis rotation=godot_to_mj(o.pose.basis);Vector3 translation=godot_to_mj(o.pose.origin);
  Array names=joints.keys();for(int i=0;i<names.size();++i){String short_name=names[i];std::string full=o.prefix+short_name.utf8().get_data();int j=mj_name2id(model,mjOBJ_JOINT,full.c_str());if(j<0||(s.model&&mj_name2id(s.model,mjOBJ_JOINT,full.c_str())>=0))continue;Dictionary state=joints[short_name];Array q=state["qpos"],v=state["qvel"];int qa=model->jnt_qposadr[j],va=model->jnt_dofadr[j];for(int k=0;k<q.size();++k)data->qpos[qa+k]=double(q[k]);for(int k=0;k<v.size();++k)data->qvel[va+k]=double(v[k]);
   if(model->jnt_type[j]==mjJNT_FREE){Vector3 pos=rotation.xform(Vector3(double(q[0]),double(q[1]),double(q[2])))+translation;Quaternion quat=rotation.get_rotation_quaternion()*Quaternion(double(q[4]),double(q[5]),double(q[6]),double(q[3]));for(int k=0;k<3;++k)data->qpos[qa+k]=pos[k];data->qpos[qa+3]=quat.w;data->qpos[qa+4]=quat.x;data->qpos[qa+5]=quat.y;data->qpos[qa+6]=quat.z;Vector3 velocity=rotation.xform(Vector3(double(v[0]),double(v[1]),double(v[2])));for(int k=0;k<3;++k)data->qvel[va+k]=velocity[k];}
  }
  names=controls.keys();for(int i=0;i<names.size();++i){String n=names[i];std::string full=o.prefix+n.utf8().get_data();int a=mj_name2id(model,mjOBJ_ACTUATOR,full.c_str());if(a<0||(s.model&&mj_name2id(s.model,mjOBJ_ACTUATOR,full.c_str())>=0))continue;data->ctrl[a]=double(controls[n]);if(activation.has(n)){Array act=activation[n];for(int k=0;k<std::min(int(act.size()),model->actuator_actnum[a]);++k)data->act[model->actuator_actadr[a]+k]=double(act[k]);}}
 }
 auto reject_candidate=[&](const String &error){mj_deleteData(data);mj_deleteModel(model);s.last_error=error;return false;};
 // Complete the transaction on isolated combined data, including all live-state
 // migration and native body pose writes that commit will perform.
 if(validate_dynamics){
  for(auto &entry:bodies){auto&b=*entry.second;if(b.space!=s.rid||b.mode!=BODY_MODE_RIGID)continue;
   int body_id=mj_name2id(model,mjOBJ_BODY,("b"+std::to_string(b.rid.get_id())).c_str());if(body_id<1)continue;
   int joint=model->body_jntadr[body_id];if(joint<0)continue;int q=model->jnt_qposadr[joint],v=model->jnt_dofadr[joint];
   Vector3 pos=godot_to_mj(b.transform.origin);Quaternion quat=godot_to_mj(b.transform.basis).get_rotation_quaternion().normalized();
   for(int k=0;k<3;++k)data->qpos[q+k]=pos[k];data->qpos[q+3]=quat.w;data->qpos[q+4]=quat.x;data->qpos[q+5]=quat.y;data->qpos[q+6]=quat.z;
   Vector3 linear=godot_to_mj(b.linear_velocity-b.angular_velocity.cross(native_com_offset(model,body_id,b.transform))),angular=godot_to_mj(b.transform.basis.orthonormalized().transposed().xform(b.angular_velocity));
   for(int k=0;k<3;++k){data->qvel[v+k]=linear[k];data->qvel[v+3+k]=angular[k];}
  }
 }
 Array override_names=control_overrides.keys();
 for(int i=0;i<override_names.size();++i){String name=override_names[i];int a=mj_name2id(model,mjOBJ_ACTUATOR,name.utf8().get_data());
  if(a<0||!std::isfinite(double(control_overrides[name])))return reject_candidate("Invalid candidate control override");
  data->ctrl[a]=double(control_overrides[name]);
 }
 mj_normalizeQuat(model,data->qpos);
 int warnings_before[mjNWARNING];for(int i=0;i<mjNWARNING;++i)warnings_before[i]=data->warning[i].number;
 mj_forward(model,data);
 if(validate_dynamics){
  auto valid=[](const mjtNum*values,int count,bool bounded){for(int i=0;i<count;++i)if(!std::isfinite(values[i])||(bounded&&mju_isBad(values[i])))return false;return true;};
  if(!valid(data->qpos,model->nq,true)||!valid(data->qvel,model->nv,true)||!valid(data->qacc,model->nv,true)||!valid(data->qacc_smooth,model->nv,true)||
     !valid(data->ctrl,model->nu,false)||!valid(data->act,model->na,false)||!valid(data->act_dot,model->na,false)||!valid(data->actuator_force,model->nu,false)||
     !valid(data->qfrc_actuator,model->nv,false)||!valid(data->qfrc_constraint,model->nv,false)||!valid(data->qfrc_bias,model->nv,false))
   return reject_candidate("Unsafe migrated candidate dynamics; preset not committed");
  for(int i=0;i<mjNWARNING;++i)if(data->warning[i].number!=warnings_before[i])return reject_candidate("Candidate dynamics produced a warning; preset not committed");
 }

 for(int i=0;i<model->nq;++i)if(!std::isfinite(data->qpos[i])){mj_deleteData(data);mj_deleteModel(model);s.last_error="Nonfinite candidate state";return false;}
 std::vector<std::pair<RID,int>> mapped(model->ngeom);
 for(size_t i=0;i<owners.size();++i){int g=mj_name2id(model,mjOBJ_GEOM,("g"+std::to_string(i)).c_str());if(g>=0)mapped[g]=owners[i];}
 if(s.data)mj_deleteData(s.data);if(s.model)mj_deleteModel(s.model);
 s.model=model;s.data=data;s.geom_owners=std::move(mapped);s.dirty=false;s.last_error="";++s.revision;
 for(auto &entry:bodies)if(entry.second->space==s.rid)entry.second->contacts.clear();
 for(auto &entry:bodies){auto&b=*entry.second;if(b.space!=s.rid)continue;std::string name="b"+std::to_string(b.rid.get_id());b.mj_body=mj_name2id(model,mjOBJ_BODY,name.c_str());if(!validate_dynamics)write_body(b);}
 // Validated transactions commit exactly the data already checked above.
 if(!validate_dynamics)mj_forward(model,data);remember_initial_state(s);return true;
}
void MjPhysicsServer3D::write_body(MjBody&b){auto*s=space(b.space);if(!s||s->dirty||!s->model||b.mj_body<1||b.mode!=BODY_MODE_RIGID)return;int j=s->model->body_jntadr[b.mj_body];if(j<0)return;int q=s->model->jnt_qposadr[j],v=s->model->jnt_dofadr[j];Vector3 p=godot_to_mj(b.transform.origin);Quaternion quat=godot_to_mj(b.transform.basis.orthonormalized()).get_rotation_quaternion().normalized();for(int k=0;k<3;++k)s->data->qpos[q+k]=p[k];s->data->qpos[q+3]=quat.w;s->data->qpos[q+4]=quat.x;s->data->qpos[q+5]=quat.y;s->data->qpos[q+6]=quat.z;Vector3 lv=godot_to_mj(b.linear_velocity-b.angular_velocity.cross(native_com_offset(s->model,b.mj_body,b.transform))),av=godot_to_mj(b.transform.basis.orthonormalized().transposed().xform(b.angular_velocity));for(int k=0;k<3;++k){s->data->qvel[v+k]=lv[k];s->data->qvel[v+3+k]=av[k];}mj_forward(s->model,s->data);}
void MjPhysicsServer3D::read_body(MjBody &b) {
 auto *s=space(b.space);
 if(!s||!s->model||b.mj_body<1||b.mode!=BODY_MODE_RIGID)return;
 int j=s->model->body_jntadr[b.mj_body];
 if(j<0)return;
 int q=s->model->jnt_qposadr[j],v=s->model->jnt_dofadr[j];
 auto *d=s->data;
 b.transform.origin=mj_to_godot(Vector3(d->qpos[q],d->qpos[q+1],d->qpos[q+2]));
 // A free joint stores a rigid pose, never authored scale. Reapplying the
 // previous basis scale feeds floating-point norm errors into every frame.
 // Input transforms are still validated before write_body; do not normalize
 // user scale/shear here to make an unsupported transform appear supported.
 Quaternion orientation(d->qpos[q+4],d->qpos[q+5],d->qpos[q+6],d->qpos[q+3]);
 b.transform.basis=mj_to_godot(Basis(orientation.normalized()));
 b.linear_velocity=mj_to_godot(Vector3(d->qvel[v],d->qvel[v+1],d->qvel[v+2]));
 b.angular_velocity=b.transform.basis.xform(mj_to_godot(Vector3(d->qvel[v+3],d->qvel[v+4],d->qvel[v+5])));
 b.linear_velocity+=b.angular_velocity.cross(native_com_offset(s->model,b.mj_body,b.transform));
 b.sync_pending=true;
}
void MjPhysicsServer3D::_set_active(bool v){active=v;}
void MjPhysicsServer3D::_init(){}
void MjPhysicsServer3D::_sync(){}
void MjPhysicsServer3D::_end_sync(){}
bool MjPhysicsServer3D::_is_flushing_queries() const{return flushing;}
void MjPhysicsServer3D::_step(float dt){
 for(auto &entry:bodies)entry.second->contacts.clear();
 process_heightfields();
 process_model_edits();
 process_world_commands(); // Before stepping, including paused worlds: UI only enqueues snapshots.
 if(!active||dt<=0)return;last_step=dt;
 // Each Godot fixed tick advances each active space exactly dt. Subdivide, don't
 // accumulate another autonomous clock (MjWorld owns entirely separate models).
 for(auto &entry:spaces){auto&s=*entry.second;if(s.skip_tick){s.skip_tick=false;continue;}if(!s.active||(s.paused&&s.single_steps==0)||!rebuild(s))continue;
 int steps;
 if(s.single_steps>0){steps=s.single_steps;s.single_steps=0;s.model->opt.timestep=s.options.timestep;}
 else if(s.authored_options){s.accumulator+=dt;steps=int((s.accumulator+1e-12)/s.options.timestep);s.accumulator-=steps*s.options.timestep;s.model->opt.timestep=s.options.timestep;}
 else{steps=std::max(1,int(std::ceil(double(dt)/0.002)));s.model->opt.timestep=double(dt)/steps;}
 if(steps<=0)continue;
 const double span=steps*s.model->opt.timestep;
 // Godot damping is applied once per server integration interval, not once
 // per MuJoCo solver subdivision (which changes its numerical meaning).
 for(auto &be:bodies){auto&b=*be.second;if(b.space!=s.rid||b.mode!=BODY_MODE_RIGID||b.mj_body<1)continue;
  b.integration_step=span;b.callback_pending=true;
  MjEnvironment environment=body_environment(b);b.integration_environment=environment;b.environment_valid=true;
  if(b.omit_integration)continue;
  int j=s.model->body_jntadr[b.mj_body],v=s.model->jnt_dofadr[j];
  double ld=environment.linear_damp,ad=environment.angular_damp;
  Vector3 linear=b.linear_velocity*std::max(0.0,1-ld*span),angular=b.angular_velocity*std::max(0.0,1-ad*span);
  Vector3 lv=godot_to_mj(linear-angular.cross(native_com_offset(s.model,b.mj_body,b.transform)));
  Vector3 av=godot_to_mj(b.transform.basis.transposed().xform(angular));
  for(int k=0;k<3;++k){s.data->qvel[v+k]=lv[k];s.data->qvel[v+3+k]=av[k];}
 }
 for(int n=0;n<steps;++n){
 for(auto &be:bodies){auto&b=*be.second;if(b.space!=s.rid||b.mode!=BODY_MODE_RIGID||b.mj_body<1)continue;
 Vector3 force=godot_to_mj(b.force),constant=godot_to_mj(b.constant_force);
 Vector3 torque=godot_to_mj(b.torque),constant_torque=godot_to_mj(b.constant_torque);
 Vector3 gravity=godot_to_mj(b.integration_environment.gravity);
 for(int k=0;k<3;++k){
  s.data->xfrc_applied[6*b.mj_body+k]=(b.omit_integration?0:double(force[k])+constant[k])+b.mass*((b.omit_integration?0:double(gravity[k]))-s.model->opt.gravity[k]);
  s.data->xfrc_applied[6*b.mj_body+3+k]=b.omit_integration?0:double(torque[k])+constant_torque[k];
 }
 }
 mj_step(s.model,s.data);if(n==steps-1)collect_contacts(s);}
 mj_forward(s.model,s.data);
 for(auto &be:bodies){auto&b=*be.second;if(b.space==s.rid){read_body(b);b.force=Vector3();b.torque=Vector3();}}
 }
}
void MjPhysicsServer3D::_flush_queries(){flushing=true;flush_area_queries();std::vector<RID> snapshot;for(auto&b:bodies)snapshot.push_back(b.second->rid);for(auto r:snapshot){auto*b=body(r);if(!b||pending_free.count(r.get_id())||!space(b->space)||!space(b->space)->active||(!b->callback_pending&&!b->sync_pending))continue;bool integrated=b->callback_pending;bool sync=b->sync_pending;b->callback_pending=b->sync_pending=false;if(integrated&&b->integration_callback.is_valid()){Callable c=b->integration_callback;Variant u=b->integration_userdata;auto*d=b->direct;if(u.get_type()==Variant::NIL)c.call(d);else c.call(d,u);}b=body(r);if(sync&&b&&!pending_free.count(r.get_id())&&b->sync_callback.is_valid()){Callable c=b->sync_callback;c.call(b->direct);}}flushing=false;drain_area_commands(); auto pending=std::move(pending_free);pending_free.clear();for(auto id:pending){auto a=areas.find(id);if(a!=areas.end()){_free_rid(a->second->rid);continue;}auto b=bodies.find(id);if(b!=bodies.end())_free_rid(b->second->rid);else {auto s=spaces.find(id);if(s!=spaces.end())_free_rid(s->second->rid);else {auto sh=shapes.find(id);if(sh!=shapes.end())_free_rid(sh->second->rid);else {for(auto &entry:spaces){auto imported=entry.second->imported.find(id);if(imported!=entry.second->imported.end()){RID rid=imported->second->rid;_free_rid(rid);break;}}}}}}}
int32_t MjPhysicsServer3D::_get_process_info(ProcessInfo p){if(p==INFO_ACTIVE_OBJECTS)return bodies.size();if(p==INFO_ISLAND_COUNT)return spaces.size();if(p==INFO_COLLISION_PAIRS){int count=0;for(auto&s:spaces)if(s.second->data)count+=s.second->data->ncon;return count;}return 0;}
}
