#include "mj_physics_server.h"
#include <algorithm>
#include <cmath>
#include <limits>

namespace godot {
namespace {
bool rigid(const Transform3D &t) {
 return t.is_finite() && t.basis.is_orthogonal() && t.basis.get_scale().is_equal_approx(Vector3(1,1,1)) && t.basis.determinant()>0;
}
bool supported(const MjShape *s) {
 return s && (s->type==PhysicsServer3D::SHAPE_BOX || s->type==PhysicsServer3D::SHAPE_SPHERE || s->type==PhysicsServer3D::SHAPE_CYLINDER);
}
} // namespace
// Same isolated MuJoCo primitive narrowphase as overlap stage 1. No live
// model, qpos, contacts or solver forces are read or written by this scratch pair.
struct MjAreaScratch {
 std::unique_ptr<mjSpec,decltype(&mj_deleteSpec)> spec{mj_makeSpec(),mj_deleteSpec};
 std::unique_ptr<mjModel,decltype(&mj_deleteModel)> model{nullptr,mj_deleteModel};
 std::unique_ptr<mjData,decltype(&mj_deleteData)> data{nullptr,mj_deleteData};
 MjAreaScratch() {
  for(int i=0;i<2;++i){auto*g=mjs_addGeom(mjs_findBody(spec.get(),"world"),nullptr);g->type=mjGEOM_SPHERE;g->size[0]=1;}
  model.reset(mj_compile(spec.get(),nullptr));if(model)data.reset(mj_makeData(model.get()));
 }
 void set(int index,const MjShape &s,const Transform3D &pose) {
  mjtNum *size=model->geom_size+index*3;mju_zero3(size);
  if(s.type==PhysicsServer3D::SHAPE_BOX){Vector3 v=s.data;model->geom_type[index]=mjGEOM_BOX;size[0]=v.x;size[1]=v.z;size[2]=v.y;}
  else if(s.type==PhysicsServer3D::SHAPE_SPHERE){model->geom_type[index]=mjGEOM_SPHERE;size[0]=double(s.data);}
  else {Dictionary d=s.data;model->geom_type[index]=mjGEOM_CYLINDER;size[0]=double(d["radius"]);size[1]=double(d["height"])*.5;}
  model->geom_rbound[index]=s.type==PhysicsServer3D::SHAPE_SPHERE?size[0]:mju_norm3(size);
  Vector3 p=godot_to_mj(pose.origin);Basis b=godot_to_mj(pose.basis);
  for(int i=0;i<3;++i){data->geom_xpos[index*3+i]=p[i];for(int j=0;j<3;++j)data->geom_xmat[index*9+i*3+j]=b[i][j];}
 }
 bool overlap(const MjShape &a,const Transform3D &ta,const MjShape &b,const Transform3D &tb) {
  if(!data||!rigid(ta)||!rigid(tb))return false;set(0,a,ta);set(1,b,tb);
  for(int i=0;i<6;++i)if(!std::isfinite(model->geom_size[i])||model->geom_size[i]>std::numeric_limits<real_t>::max())return false;
  if(ta.origin.distance_to(tb.origin)>model->geom_rbound[0]+model->geom_rbound[1])return false;
  int first=model->geom_type[0]>model->geom_type[1]?1:0,second=1-first;
  auto fn=mjCOLLISIONFUNC[model->geom_type[first]][model->geom_type[second]];if(!fn)return false;
  mjPreContact contacts[mjMAXCONPAIR]{};int count=fn(model.get(),data.get(),contacts,first,second,0);
  if(!count&&(model->geom_type[0]==mjGEOM_CYLINDER||model->geom_type[1]==mjGEOM_CYLINDER)){
   model->opt.disableflags|=mjDSBL_NATIVECCD;count=fn(model.get(),data.get(),contacts,first,second,0);model->opt.disableflags&=~mjDSBL_NATIVECCD;
  }
  for(int i=0;i<count;++i)if(std::isfinite(contacts[i].dist)&&contacts[i].dist<=0)return true;
  return false;
 }
};
MjArea *MjPhysicsServer3D::area(const RID &r) const {auto i=areas.find(r.get_id());return i==areas.end()?nullptr:i->second.get();}
// All Area mutations requested during callbacks take effect after the entire
// notification batch. Values/RIDs are captured, never pointers into maps.
#define DEFER_AREA(call) if(flushing){area_commands.push_back([=]{call;});return;}
RID MjPhysicsServer3D::_area_create(){RID r=handles.make_rid(0);auto a=std::make_unique<MjArea>();a->rid=r;
 a->params[AREA_PARAM_GRAVITY_OVERRIDE_MODE]=AREA_SPACE_OVERRIDE_DISABLED;a->params[AREA_PARAM_LINEAR_DAMP_OVERRIDE_MODE]=AREA_SPACE_OVERRIDE_DISABLED;a->params[AREA_PARAM_ANGULAR_DAMP_OVERRIDE_MODE]=AREA_SPACE_OVERRIDE_DISABLED;
 a->params[AREA_PARAM_GRAVITY]=9.8;a->params[AREA_PARAM_GRAVITY_VECTOR]=Vector3(0,-1,0);a->params[AREA_PARAM_GRAVITY_IS_POINT]=false;a->params[AREA_PARAM_GRAVITY_POINT_UNIT_DISTANCE]=0.0;
 a->params[AREA_PARAM_LINEAR_DAMP]=0.1;a->params[AREA_PARAM_ANGULAR_DAMP]=1.0;a->params[AREA_PARAM_PRIORITY]=0.0;
 areas.emplace(r.get_id(),std::move(a));return r;}
void MjPhysicsServer3D::_area_set_space(const RID&r,const RID&s){DEFER_AREA(_area_set_space(r,s));auto*a=area(r);if(!a)return;ERR_FAIL_COND(s.is_valid()&&!space(s));if(a->space==s)return;a->space=s;retire_area_pairs(r);}
RID MjPhysicsServer3D::_area_get_space(const RID&r) const {auto*a=area(r);return a?a->space:RID();}
void MjPhysicsServer3D::_area_add_shape(const RID&r,const RID&s,const Transform3D&t,bool disabled){DEFER_AREA(_area_add_shape(r,s,t,disabled));auto*a=area(r);if(!a)return;ERR_FAIL_COND_MSG(!supported(shape(s)),"Area monitoring supports native box, sphere and cylinder only");ERR_FAIL_COND(!rigid(t));a->shapes.push_back({s,t,disabled});}
void MjPhysicsServer3D::_area_set_shape(const RID&r,int32_t i,const RID&s){DEFER_AREA(_area_set_shape(r,i,s));auto*a=area(r);if(!a)return;ERR_FAIL_INDEX(i,int(a->shapes.size()));ERR_FAIL_COND(!supported(shape(s)));a->shapes[i].shape=s;}
void MjPhysicsServer3D::_area_set_shape_transform(const RID&r,int32_t i,const Transform3D&t){DEFER_AREA(_area_set_shape_transform(r,i,t));auto*a=area(r);if(!a)return;ERR_FAIL_INDEX(i,int(a->shapes.size()));ERR_FAIL_COND(!rigid(t));a->shapes[i].transform=t;}
void MjPhysicsServer3D::_area_set_shape_disabled(const RID&r,int32_t i,bool value){DEFER_AREA(_area_set_shape_disabled(r,i,value));auto*a=area(r);if(!a)return;ERR_FAIL_INDEX(i,int(a->shapes.size()));a->shapes[i].disabled=value;}
int32_t MjPhysicsServer3D::_area_get_shape_count(const RID&r) const {auto*a=area(r);return a?a->shapes.size():0;}
RID MjPhysicsServer3D::_area_get_shape(const RID&r,int32_t i) const {auto*a=area(r);return a&&i>=0&&i<int(a->shapes.size())?a->shapes[i].shape:RID();}
Transform3D MjPhysicsServer3D::_area_get_shape_transform(const RID&r,int32_t i) const {auto*a=area(r);return a&&i>=0&&i<int(a->shapes.size())?a->shapes[i].transform:Transform3D();}
void MjPhysicsServer3D::_area_remove_shape(const RID&r,int32_t i){DEFER_AREA(_area_remove_shape(r,i));auto*a=area(r);if(!a)return;ERR_FAIL_INDEX(i,int(a->shapes.size()));a->shapes.erase(a->shapes.begin()+i);retire_area_pairs(r,i);}
void MjPhysicsServer3D::_area_clear_shapes(const RID&r){DEFER_AREA(_area_clear_shapes(r));if(auto*a=area(r)){a->shapes.clear();retire_area_pairs(r);}}
void MjPhysicsServer3D::_area_attach_object_instance_id(const RID&r,uint64_t id){DEFER_AREA(_area_attach_object_instance_id(r,id));if(auto*a=area(r))a->object_id=id;}
uint64_t MjPhysicsServer3D::_area_get_object_instance_id(const RID&r) const {auto*a=area(r);return a?a->object_id:0;}
void MjPhysicsServer3D::_area_set_transform(const RID&r,const Transform3D&t){DEFER_AREA(_area_set_transform(r,t));auto*a=area(r);if(!a)return;ERR_FAIL_COND(!rigid(t));a->transform=t;}
Transform3D MjPhysicsServer3D::_area_get_transform(const RID&r) const {auto*a=area(r);return a?a->transform:Transform3D();}
void MjPhysicsServer3D::_area_set_collision_layer(const RID&r,uint32_t value){DEFER_AREA(_area_set_collision_layer(r,value));if(auto*a=area(r))a->layer=value;}
uint32_t MjPhysicsServer3D::_area_get_collision_layer(const RID&r) const {auto*a=area(r);return a?a->layer:0;}
void MjPhysicsServer3D::_area_set_collision_mask(const RID&r,uint32_t value){DEFER_AREA(_area_set_collision_mask(r,value));if(auto*a=area(r))a->mask=value;}
uint32_t MjPhysicsServer3D::_area_get_collision_mask(const RID&r) const {auto*a=area(r);return a?a->mask:0;}
void MjPhysicsServer3D::_area_set_monitorable(const RID&r,bool value){DEFER_AREA(_area_set_monitorable(r,value));if(auto*a=area(r))a->monitorable=value;}
void MjPhysicsServer3D::_area_set_ray_pickable(const RID&r,bool value){DEFER_AREA(_area_set_ray_pickable(r,value));if(auto*a=area(r))a->ray_pickable=value;}
void MjPhysicsServer3D::_area_set_monitor_callback(const RID&r,const Callable&cb){DEFER_AREA(_area_set_monitor_callback(r,cb));if(auto*a=area(r)){if(a->body_callback==cb)return;a->body_callback=cb;for(auto i=a->reported.begin();i!=a->reported.end();)if(!i->area)i=a->reported.erase(i);else ++i;}}
void MjPhysicsServer3D::_area_set_area_monitor_callback(const RID&r,const Callable&cb){DEFER_AREA(_area_set_area_monitor_callback(r,cb));if(auto*a=area(r)){if(a->area_callback==cb)return;a->area_callback=cb;for(auto i=a->reported.begin();i!=a->reported.end();)if(i->area)i=a->reported.erase(i);else ++i;}}
#undef DEFER_AREA
// Detach notifications must retire Godot's tree-entered subscriptions before
// a node is reparented into another World in the same frame. Waiting for the
// next physics tick would synthesize an enter/exit in the wrong World.
void MjPhysicsServer3D::retire_area_pairs(const RID &rid,int from_shape){
 struct Removal {RID receiver;Callable callback;MjAreaPair pair;};std::vector<Removal> removals;
 for(auto &entry:areas){auto &a=*entry.second;
  for(auto it=a.reported.begin();it!=a.reported.end();){
   if((a.rid==rid&&it->self_shape>=from_shape)||(it->rid==rid&&it->other_shape>=from_shape)){removals.push_back({a.rid,it->area?a.area_callback:a.body_callback,*it});it=a.reported.erase(it);}else ++it;
  }
 }
 bool was_flushing=flushing;flushing=true;
 for(const auto &event:removals)if(!pending_free.count(event.receiver.get_id())&&event.callback.is_valid())event.callback.call(AREA_BODY_REMOVED,event.pair.rid,event.pair.object_id,event.pair.other_shape,event.pair.self_shape);
 flushing=was_flushing;
 if(!flushing)drain_area_commands();
}
void MjPhysicsServer3D::drain_area_commands(){
 // A command may emit exit callbacks, which append more commands. Never drain
 // recursively: those new requests must remain behind the original batch.
 if(draining_area_commands)return;
 draining_area_commands=true;
 while(!area_commands.empty()){auto command=std::move(area_commands.front());area_commands.pop_front();command();}
 draining_area_commands=false;
}
void MjPhysicsServer3D::flush_area_queries(){
 if(areas.empty())return;
 if(!area_scratch)area_scratch=std::make_shared<MjAreaScratch>();
 auto &scratch=*area_scratch;
 struct Event {RID receiver, other;Callable callback;MjAreaPair pair;int status;};
 std::vector<Event> events;
 for(auto &entry:areas){auto &a=*entry.second;std::set<MjAreaPair> current;
  auto*s=space(a.space);
  if(active&&s&&s->active&&!pending_free.count(a.rid.get_id())&&!pending_free.count(a.space.get_id())){
   auto compare=[&](const RID &r,uint64_t id,const Transform3D &pose,const std::vector<MjShapeInstance> &instances,bool is_area){
    if(pending_free.count(r.get_id()))return;
    for(int i=0;i<int(a.shapes.size());++i){const auto &local=a.shapes[i];auto*ls=shape(local.shape);if(local.disabled||!supported(ls)||pending_free.count(local.shape.get_id()))continue;
     for(int j=0;j<int(instances.size());++j){const auto &other=instances[j];auto*os=shape(other.shape);if(other.disabled||!supported(os)||pending_free.count(other.shape.get_id()))continue;
      if(scratch.overlap(*ls,a.transform*local.transform,*os,pose*other.transform))current.insert({r,id,j,i,is_area});
     }
    }
   };
   if(a.body_callback.is_valid())for(auto &b:bodies)if(b.second->space==a.space&&!b.second->heightfield&&(a.mask&b.second->layer))compare(b.second->rid,b.second->object_id,b.second->transform,b.second->shapes,false);
   if(a.area_callback.is_valid())for(auto &b:areas)if(b.first!=entry.first&&b.second->space==a.space&&b.second->monitorable&&(a.mask&b.second->layer))compare(b.second->rid,b.second->object_id,b.second->transform,b.second->shapes,true);
  }
  auto event=[&](const MjAreaPair &p,int status){Callable cb=p.area?a.area_callback:a.body_callback;if(cb.is_valid())events.push_back({a.rid,p.rid,cb,p,status});};
  for(const auto &p:a.reported)if(!current.count(p))event(p,AREA_BODY_REMOVED);
  for(const auto &p:current)if(!a.reported.count(p))event(p,AREA_BODY_ADDED);
  a.reported=std::move(current);
 }
 // Finish pair diffs before invoking user code. Mutation is queued and free is
 // deferred by the server. Stops delivery to receivers freed by an earlier event.
 for(const auto &event:events){if(!area(event.receiver)||pending_free.count(event.receiver.get_id()))continue;
  if(event.status==AREA_BODY_ADDED&&pending_free.count(event.other.get_id())){area(event.receiver)->reported.erase(event.pair);continue;}
  event.callback.call(event.status,event.other,event.pair.object_id,event.pair.other_shape,event.pair.self_shape);
 }
}
}
