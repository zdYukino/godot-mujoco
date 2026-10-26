#include "mj_load_trace.h"
#include "mj_physics_server.h"
#include "mj_options.h"
#include "../mj_editor_document.h"
#include <cmath>
namespace godot {
namespace {
Array values(const mjtNum*p,int count){Array result;for(int i=0;i<count;++i)result.push_back(p[i]);return result;}
Dictionary initial_state(const mjModel*m,const mjData*d){gmj_load_trace::mark("load.initial_state_begin");Dictionary result,joints,controls,activation,counts;counts["geom"]=m->ngeom;counts["joint"]=m->njnt;counts["actuator"]=m->nu;counts["equality"]=m->neq;counts["tendon"]=m->ntendon;counts["sensor"]=m->nsensor;result["counts"]=counts;
 for(int j=0;j<m->njnt;++j){Dictionary state;int type=m->jnt_type[j];state["qpos"]=values(d->qpos+m->jnt_qposadr[j],type==mjJNT_FREE?7:type==mjJNT_BALL?4:1);state["qvel"]=values(d->qvel+m->jnt_dofadr[j],type==mjJNT_FREE?6:type==mjJNT_BALL?3:1);joints[String(mj_id2name(m,mjOBJ_JOINT,j))]=state;}
 for(int a=0;a<m->nu;++a){String name(mj_id2name(m,mjOBJ_ACTUATOR,a));controls[name]=d->ctrl[a];if(m->actuator_actnum[a])activation[name]=values(d->act+m->actuator_actadr[a],m->actuator_actnum[a]);}
 result["joints"]=joints;result["controls"]=controls;result["activation"]=activation;gmj_load_trace::mark("load.initial_state_end");return result;
}
}
bool MjPhysicsServer3D::scene_configure_model(const RID&r,const Dictionary&snapshot,const String&directory){
 auto*s=space(r);if(!s)return false;if(!s->paused||flushing){s->last_error="Pause outside callbacks before configuring a runtime world";return false;}
 Ref<MjEditorDocument> doc;doc.instantiate();if(!doc->restore_at(snapshot,directory)){s->last_error=doc->get_error();return false;}
 auto options=doc->native_model()->opt;
 if(options.timestep<0.0001){s->last_error="Runtime world timestep below 0.0001 s exceeds the synchronous step budget";return false;}
 if(!s->imported.empty()){s->last_error="Configure the world before loading model instances";return false;}
 auto old=s->options;bool authored=s->authored_options;auto direction=s->gravity_direction;double gravity=s->gravity;
 s->options=options;s->authored_options=true;s->gravity_direction=mj_to_godot(Vector3(options.gravity[0],options.gravity[1],options.gravity[2]));s->gravity=s->gravity_direction.length();if(s->gravity>0)s->gravity_direction/=s->gravity;
 s->dirty=true;if(!rebuild(*s)){s->options=old;s->authored_options=authored;s->gravity_direction=direction;s->gravity=gravity;return false;}s->params[AREA_PARAM_GRAVITY]=s->gravity;s->params[AREA_PARAM_GRAVITY_VECTOR]=s->gravity_direction;s->accumulator=0;return true;
}
RID MjPhysicsServer3D::scene_load_model(const RID&r,const Dictionary&snapshot,const String&directory,const String&label,const Transform3D&pose){
 gmj_load_trace::Scope trace;
 auto*s=space(r);if(!s)return {};if(!s->paused||flushing||!s->authored_options){s->last_error="A configured, paused runtime world is required";return {};}
 gmj_load_trace::mark("load.document_construct_begin");Ref<MjEditorDocument> doc;doc.instantiate();gmj_load_trace::mark("load.document_construct_end");gmj_load_trace::mark("load.restore_begin");if(!doc->restore_at(snapshot,directory)){s->last_error=doc->get_error();return {};}
 gmj_load_trace::mark("load.restore_end");auto*m=doc->native_model();String conflict=gmj_option_conflict(s->options,m->opt);
 if(!conflict.is_empty()){s->last_error="World/model option conflict: "+conflict;return {};}
 // Global userdata and mocap target semantics do not belong to a model instance.
 // Reject rather than silently dropping or sharing those mutable global arrays.
 if(m->nuserdata||m->nmocap||m->nkey){s->last_error="Runtime composition does not support global userdata, mocap bodies or keyframes";return {};}
 gmj_load_trace::mark("load.insert_arguments_begin");
 // Capture state before consuming the temporary document. scene_insert owns
 // the spec on every success/failure path, so no compiled mesh copy is needed.
 Dictionary initial=initial_state(m,doc->native_data());
 gmj_load_trace::mark("load.take_spec_begin");
 auto*spec=doc->take_spec();
 gmj_load_trace::mark("load.take_spec_end");
 RID result=scene_insert(*s,spec,label,pose,true,initial);
 gmj_load_trace::mark("load.insert_returned",result.is_valid());return result;
}
bool MjPhysicsServer3D::scene_set_actuator(const RID&r,const RID&id,const String&name,double value){
 {std::lock_guard<std::mutex> lock(edits_mutex);for(const auto &pending:model_edits)if(pending.object==id)return false;}
 auto*s=space(r);if(!s||!s->model||!std::isfinite(value))return false;auto it=s->imported.find(id.get_id());if(it==s->imported.end())return false;
 int a=mj_name2id(s->model,mjOBJ_ACTUATOR,(it->second->prefix+name.utf8().get_data()).c_str());if(a<0)return false;
 if(s->model->actuator_ctrllimited[a]&&(value<s->model->actuator_ctrlrange[2*a]||value>s->model->actuator_ctrlrange[2*a+1]))return false;
 s->data->ctrl[a]=value;return true;
}
bool MjPhysicsServer3D::scene_release_model(const RID&r,const RID&id){auto*s=space(r);if(!s||!s->imported.count(id.get_id()))return false;if(flushing){pending_free.insert(id.get_id());return true;}bool paused=s->paused;s->paused=true;bool ok=scene_remove(r,id);s->paused=paused;return ok;}
int64_t MjPhysicsServer3D::scene_request_model_edit(const RID&r,const RID&id,const Dictionary&snapshot,const String&directory,int64_t expected_revision){
 std::lock_guard<std::mutex> lock(edits_mutex);
 if(model_edits.size()>=64||edit_results.size()>=256||expected_revision<0)return 0;
 for(const auto &pending:model_edits)if(pending.object==id)return 0;
 int64_t request=next_edit_request++;
 model_edits.push_back({request,expected_revision,r,id,snapshot.duplicate(true),directory});
 return request;
}
int64_t MjPhysicsServer3D::scene_request_preset(const RID&r,const RID&id,const Dictionary&p,int64_t revision){
 std::lock_guard<std::mutex> lock(edits_mutex);
 if(model_edits.size()>=64||edit_results.size()>=256||revision<0)return 0;
 for(const auto &pending:model_edits)if(pending.object==id)return 0;
 int64_t request=next_edit_request++;model_edits.push_back({request,revision,r,id,p.duplicate(true),String(),true});return request;
}
bool MjPhysicsServer3D::scene_cancel_preset(int64_t request){
 std::lock_guard<std::mutex> lock(edits_mutex);
 for(auto it=model_edits.begin();it!=model_edits.end();++it)if(it->request==request&&it->preset){
  Dictionary result;result["request"]=request;result["success"]=false;result["revision"]=it->expected_revision;result["error"]="Preset cancelled before commit";result["cancelled"]=true;
  model_edits.erase(it);edit_results[request]=result;return true;
 }
 return false; // Already executing/committed: never pretend to undo a commit.
}
void MjPhysicsServer3D::scene_cancel_model_edit(int64_t request){
 std::lock_guard<std::mutex> lock(edits_mutex);
 for(auto it=model_edits.begin();it!=model_edits.end();++it)if(it->request==request){model_edits.erase(it);break;}
 edit_results.erase(request);
}
Dictionary MjPhysicsServer3D::scene_edit_result(int64_t request){
 std::lock_guard<std::mutex> lock(edits_mutex);
 auto result=edit_results.find(request);if(result==edit_results.end())return {};
 Dictionary value=result->second;edit_results.erase(result);return value;
}
void MjPhysicsServer3D::process_model_edits(){
 std::deque<ModelEdit> pending;
 {std::lock_guard<std::mutex> lock(edits_mutex);pending.swap(model_edits);}
 for(const auto &request:pending){
  Dictionary result;result["request"]=request.request;result["success"]=false;result["revision"]=request.expected_revision;
  auto apply=[&]()->String {
   auto*s=space(request.space);if(!s)return "Runtime world was removed";
   auto found=s->imported.find(request.object.get_id());if(found==s->imported.end()||!found->second->whole_model)return "Model instance was removed";
   auto &object=*found->second;
   result["revision"]=int64_t(object.property_revision);
   if(object.property_revision!=uint64_t(request.expected_revision))return "Stale property revision; refresh before retrying";
   // No active model/data writes occur before this native physics-step boundary.
   bool paused=s->paused;double accumulator=s->accumulator;s->paused=true;
   struct Resume {MjSpace*s;bool paused;double accumulator;~Resume(){s->paused=paused;s->accumulator=accumulator;}} resume{s,paused,accumulator};
   Ref<MjEditorDocument> doc;doc.instantiate();
   if(request.preset){
    if(!doc->restore_spec(object.spec))return doc->get_error();
    Dictionary prepared=doc->preset_candidate(request.snapshot);
    if(!String(prepared["error"]).is_empty())return prepared["error"];
    if(!doc->restore(prepared["snapshot"]))return doc->get_error();
   }else if(!doc->restore_at(request.snapshot,request.directory))return doc->get_error();
   auto*m=doc->native_model();String conflict=gmj_option_conflict(s->options,m->opt);
   if(!conflict.is_empty())return "World/model option conflict: "+conflict;
   if(m->nuserdata||m->nmocap||m->nkey)return "Runtime composition does not support global userdata, mocap bodies or keyframes";
   // Same names must retain state dimensions/semantics. New/deleted names are allowed.
   for(int j=0;j<m->njnt;++j){const char*n=mj_id2name(m,mjOBJ_JOINT,j);int old=mj_name2id(s->model,mjOBJ_JOINT,(object.prefix+n).c_str());if(old>=0&&m->jnt_type[j]!=s->model->jnt_type[old])return "Incompatible joint type: "+String(n);}
   for(int a=0;a<m->nu;++a){const char*n=mj_id2name(m,mjOBJ_ACTUATOR,a);int old=mj_name2id(s->model,mjOBJ_ACTUATOR,(object.prefix+n).c_str());if(old>=0&&(m->actuator_dyntype[a]!=s->model->actuator_dyntype[old]||m->actuator_actnum[a]!=s->model->actuator_actnum[old]))return "Incompatible actuator state: "+String(n);}
   mjSpec*previous=object.spec;Dictionary initial=object.initial;bool dirty=s->dirty;
   object.spec=doc->copy_spec();object.initial=initial_state(m,doc->native_data());s->dirty=true;
   Dictionary controls;
   if(request.preset)for(int a=0;a<m->nu;++a)controls[String((object.prefix+mj_id2name(m,mjOBJ_ACTUATOR,a)).c_str())]=doc->native_data()->ctrl[a];
   if(!rebuild(*s,controls,request.preset)){
    String error=s->last_error;mj_deleteSpec(object.spec);object.spec=previous;object.initial=initial;s->dirty=dirty;
    return error;
   }
   // Rebuild validated migrated state and the entire control set before swap.
   mj_deleteSpec(previous);++object.property_revision;
   result["revision"]=int64_t(object.property_revision);result["success"]=true;
   if(request.preset)result["state"]=scene_state(request.space,request.object);
   return {};
  };
  result["error"]=apply();
  std::lock_guard<std::mutex> lock(edits_mutex);edit_results[request.request]=result;
 }
}

}
