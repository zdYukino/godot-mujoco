#include "mj_load_trace.h"
#include "mj_physics_server.h"
#include "mj_options.h"
#include "mj_collision_options.h"
#include "../mj_editor_document.h"
#include <cmath>
#include <godot_cpp/core/object.hpp>
namespace godot {
extern thread_local bool gmj_background_worker;
namespace {
Array values(const mjtNum*p,int count){Array result;for(int i=0;i<count;++i)result.push_back(p[i]);return result;}
Dictionary initial_state(const mjModel*m,const mjData*d){gmj_load_trace::mark("load.initial_state_begin");Dictionary result,joints,controls,activation,counts;counts["geom"]=m->ngeom;counts["joint"]=m->njnt;counts["actuator"]=m->nu;counts["equality"]=m->neq;counts["tendon"]=m->ntendon;counts["sensor"]=m->nsensor;result["counts"]=counts;
 for(int j=0;j<m->njnt;++j){Dictionary state;int type=m->jnt_type[j];state["qpos"]=values(d->qpos+m->jnt_qposadr[j],type==mjJNT_FREE?7:type==mjJNT_BALL?4:1);state["qvel"]=values(d->qvel+m->jnt_dofadr[j],type==mjJNT_FREE?6:type==mjJNT_BALL?3:1);joints[String(mj_id2name(m,mjOBJ_JOINT,j))]=state;}
 for(int a=0;a<m->nu;++a){String name(mj_id2name(m,mjOBJ_ACTUATOR,a));controls[name]=d->ctrl[a];if(m->actuator_actnum[a])activation[name]=values(d->act+m->actuator_actadr[a],m->actuator_actnum[a]);}
 result["joints"]=joints;result["controls"]=controls;result["activation"]=activation;gmj_load_trace::mark("load.initial_state_end");return result;
}
}
bool MjPhysicsServer3D::scene_configure_world(const RID&r,const String&xml){
 auto*s=space(r);if(!s)return false;if(!s->paused||flushing){s->last_error="Pause outside callbacks before configuring a runtime world";return false;}
 char error[2048]={};auto*spec=mj_parseXMLString(xml.utf8().get_data(),nullptr,error,sizeof(error));
 if(!spec){s->last_error=String::utf8(error);return false;}
 if(mjs_firstElement(spec,mjOBJ_PLUGIN)){mj_deleteSpec(spec);s->last_error="Plugins are disabled";return false;}
 auto options=spec->option;mj_deleteSpec(spec);
 if(!std::isfinite(options.timestep)||options.timestep<0.0001||options.timestep>.1){s->last_error="Runtime world timestep must be .0001..0.1 s";return false;}
 if(!s->imported.empty()||s->authoring){s->last_error="Configure an ordinary world before loading instances";return false;}
 auto old=s->options;bool authored=s->authored_options;auto direction=s->gravity_direction;double gravity=s->gravity;
 s->options=options;s->authored_options=true;s->gravity_direction=mj_to_godot(Vector3(options.gravity[0],options.gravity[1],options.gravity[2]));s->gravity=s->gravity_direction.length();if(s->gravity>0)s->gravity_direction/=s->gravity;
 s->dirty=true;if(!rebuild(*s)){s->options=old;s->authored_options=authored;s->gravity_direction=direction;s->gravity=gravity;return false;}s->params[AREA_PARAM_GRAVITY]=s->gravity;s->params[AREA_PARAM_GRAVITY_VECTOR]=s->gravity_direction;s->accumulator=0;return true;
}
RID MjPhysicsServer3D::scene_load_xml(const RID&r,const String&xml,const Dictionary&initial,const Dictionary&mesh_options,const String&label,const Transform3D&pose){
 gmj_load_trace::Scope trace;
 auto*s=space(r);if(!s)return {};if(!s->paused||flushing||!s->authored_options||s->authoring){s->last_error="A configured, paused ordinary runtime world is required";return {};}
 Dictionary snapshot;snapshot["format"]=2;snapshot["xml"]=xml;snapshot["state"]=initial;snapshot["mesh_options"]=mesh_options;
 Ref<MjEditorDocument> doc;doc.instantiate();if(!doc->restore(snapshot)){s->last_error=doc->get_error();return {};}
 auto*m=doc->native_model();auto options=m->opt;gmj_inherit_collision_options(options,s->options);
 String conflict=gmj_option_conflict(s->options,options);
 if(!conflict.is_empty()){s->last_error="World/model option conflict: "+conflict;return {};}
 if(m->nuserdata||m->nmocap||m->nkey){s->last_error="Runtime composition does not support global userdata, mocap bodies or keyframes";return {};}
 Dictionary state=initial_state(m,doc->native_data());
 auto*spec=doc->take_spec();gmj_inherit_collision_options(spec->option,s->options);return scene_insert(*s,spec,label,pose,true,state);
}
bool MjPhysicsServer3D::scene_set_actuator(const RID&r,const RID&id,const String&name,double value){
 {std::lock_guard<std::mutex> lock(requests_mutex);for(const auto &pending:control_commits)if(pending.object==id)return false;}
 auto*s=space(r);if(!s||!s->model||!std::isfinite(value))return false;auto it=s->imported.find(id.get_id());if(it==s->imported.end())return false;
 int a=mj_name2id(s->model,mjOBJ_ACTUATOR,(it->second->prefix+name.utf8().get_data()).c_str());if(a<0)return false;
 if(s->model->actuator_ctrllimited[a]&&(value<s->model->actuator_ctrlrange[2*a]||value>s->model->actuator_ctrlrange[2*a+1]))return false;
 s->data->ctrl[a]=value;return true;
}
bool MjPhysicsServer3D::scene_set_query_owner(const RID&r,const RID&id,uint64_t object_id,bool pickable){
 auto*s=space(r);if(!s||pending_free.count(id.get_id()))return false;
 auto it=s->imported.find(id.get_id());if(it==s->imported.end())return false;
 if(object_id&&!ObjectDB::get_instance(object_id))return false;
 it->second->query_object_id=object_id;it->second->query_ray_pickable=pickable;
 for(auto&e:s->imported_query_owners)if(e.second->rid==id){e.second->object_id=object_id;e.second->ray_pickable=pickable;}
 return true;
}
bool MjPhysicsServer3D::scene_release_model(const RID&r,const RID&id){auto*s=space(r);if(!s||!s->imported.count(id.get_id()))return false;if(flushing){pending_free.insert(id.get_id());return true;}bool paused=s->paused;s->paused=true;bool ok=scene_remove(r,id);s->paused=paused;return ok;}
int64_t MjPhysicsServer3D::scene_request_control_commit(const RID&r,const RID&id,const Dictionary&p,int64_t revision){
 std::lock_guard<std::mutex> lock(requests_mutex);
 if(control_commits.size()>=64||control_results.size()>=256||revision<0)return 0;
 for(const auto &pending:control_commits)if(pending.object==id)return 0;
 int64_t request=next_request_id++;control_commits.push_back({request,revision,r,id,p.duplicate(true)});return request;
}
bool MjPhysicsServer3D::scene_cancel_control_commit(int64_t request){
 std::lock_guard<std::mutex> lock(requests_mutex);
 for(auto it=control_commits.begin();it!=control_commits.end();++it)if(it->request==request){
  Dictionary result;result["request"]=request;result["success"]=false;result["revision"]=it->expected_revision;result["error"]="Preset cancelled before commit";result["cancelled"]=true;
  control_commits.erase(it);control_results[request]=result;return true;
 }return false;
}
void MjPhysicsServer3D::scene_discard_control_commit(int64_t request){
 std::lock_guard<std::mutex> lock(requests_mutex);
 for(auto it=control_commits.begin();it!=control_commits.end();++it)if(it->request==request){control_commits.erase(it);break;}
 control_results.erase(request);
}
Dictionary MjPhysicsServer3D::scene_control_result(int64_t request){
 std::lock_guard<std::mutex> lock(requests_mutex);
 auto result=control_results.find(request);if(result==control_results.end())return {};
 Dictionary value=result->second;control_results.erase(result);return value;
}
void MjPhysicsServer3D::process_control_commits(){
 std::deque<ControlCommit> pending;
 {std::lock_guard<std::mutex> lock(requests_mutex);pending.swap(control_commits);}
 for(const auto &request:pending){
  Dictionary result;result["request"]=request.request;result["success"]=false;result["revision"]=request.expected_revision;
  auto apply=[&]()->String {
   auto*s=space(request.space);if(!s||!s->model)return "Runtime world was removed";
   auto found=s->imported.find(request.object.get_id());if(found==s->imported.end())return "Model instance was removed";
   auto &object=*found->second;result["revision"]=int64_t(object.property_revision);
   if(object.property_revision!=uint64_t(request.expected_revision))return "Stale property revision; refresh before retrying";
   if(s->dirty||s->design_blocked)return "Wait for the current design to compile before applying a preset";
   Dictionary drives=request.snapshot.get("drives",Dictionary()),kinds=request.snapshot.get("kinds",Dictionary());
   int count=0;for(int a=0;a<s->model->nu;++a){const char*n=mj_id2name(s->model,mjOBJ_ACTUATOR,a);if(n&&std::string(n).rfind(object.prefix,0)==0)++count;}
   if(count!=drives.size()||count!=kinds.size())return "Actuator set mismatch";
   mjModel*m=mj_copyModel(nullptr,s->model);if(!m)return "Cannot allocate preset candidate model";
   mjData*d=mj_makeData(m);if(!d){mj_deleteModel(m);return "Cannot allocate preset candidate data";}mj_copyData(d,m,s->data);
   auto fail=[&](const String&e){mj_deleteData(d);mj_deleteModel(m);return e;};
   for(auto key:drives.keys()){
    String label=key;int a=mj_name2id(m,mjOBJ_ACTUATOR,(object.prefix+label.utf8().get_data()).c_str());if(a<0||m->actuator_trntype[a]!=mjTRN_JOINT)return fail("Missing supported named actuator");
    Dictionary fields=drives[key];String kind=kinds.get(key,String());auto*g=m->actuator_gainprm+a*mjNGAIN;auto*b=m->actuator_biasprm+a*mjNBIAS;
    for(auto field:fields.keys()){Variant v=fields[field];if((v.get_type()!=Variant::FLOAT&&v.get_type()!=Variant::INT)||!std::isfinite(double(v)))return fail("Invalid numeric preset field");}
    double control=fields.get("control",NAN);if(!std::isfinite(control)||(m->actuator_ctrllimited[a]&&(control<m->actuator_ctrlrange[2*a]||control>m->actuator_ctrlrange[2*a+1])))return fail("Preset control out of range");
    if(kind=="position-compatible"){
     double kp=fields.get("kp",0.),kv=fields.get("kv",-1.);if(kp<=0||kv<0||fields.size()!=3)return fail("Invalid position gains");g[0]=kp;b[1]=-kp;b[2]=-kv;
    }else if(kind=="velocity-compatible"){
     double kv=fields.get("kv",0.);if(kv<=0||fields.size()!=2)return fail("Invalid velocity gain");g[0]=kv;b[2]=-kv;
    }else if(kind!="general/non-PD"||fields.size()!=1)return fail("Invalid actuator preset kind");
    d->ctrl[a]=control;
   }
   int warnings[mjNWARNING];for(int i=0;i<mjNWARNING;++i)warnings[i]=d->warning[i].number;
   mj_forward(m,d);
   auto valid=[](const mjtNum*p,int n,bool bounded){for(int i=0;i<n;++i)if(!std::isfinite(p[i])||(bounded&&mju_isBad(p[i])))return false;return true;};
   if(!valid(d->qpos,m->nq,true)||!valid(d->qvel,m->nv,true)||!valid(d->qacc,m->nv,true)||!valid(d->qacc_smooth,m->nv,true)||!valid(d->actuator_force,m->nu,false)||!valid(d->qfrc_actuator,m->nv,false)||!valid(d->qfrc_constraint,m->nv,false))return fail("Unsafe migrated candidate dynamics; preset not committed");
   for(int i=0;i<mjNWARNING;++i)if(d->warning[i].number!=warnings[i])return fail("Candidate dynamics produced a warning; preset not committed");
   auto*old_model=s->model;auto*old_data=s->data;s->query_sdf_fields.clear();s->model=m;s->data=d;object.runtime_drives=drives.duplicate(true);++object.property_revision;++s->revision;
   result["revision"]=int64_t(object.property_revision);result["success"]=true;result["state"]=scene_state(request.space,request.object);
   async_threads.emplace_back([old_model,old_data](){gmj_background_worker=true;mj_deleteData(old_data);mj_deleteModel(old_model);});return {};
  };result["error"]=apply();std::lock_guard<std::mutex> lock(requests_mutex);control_results[request.request]=result;
 }
}
} // namespace godot
