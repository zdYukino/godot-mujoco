#include "mj_dictionary_compat.h"
#include "mj_physics_server.h"
#include "../viewer/mj_runtime_viewer.h"
#include <cmath>
namespace godot {
namespace {
Array numbers(const mjtNum*p,int count){Array a;for(int i=0;i<count;++i)a.push_back(p[i]);return a;}
Dictionary capture(const mjModel*m,const mjData*d){
 Dictionary out,joints,actuators;out["time"]=d->time;
 for(int j=0;j<m->njnt;++j){Dictionary v;int type=m->jnt_type[j];v["type"]=type;v["qpos"]=numbers(d->qpos+m->jnt_qposadr[j],type==mjJNT_FREE?7:type==mjJNT_BALL?4:1);v["qvel"]=numbers(d->qvel+m->jnt_dofadr[j],type==mjJNT_FREE?6:type==mjJNT_BALL?3:1);joints[String(mj_id2name(m,mjOBJ_JOINT,j))]=v;}
 for(int a=0;a<m->nu;++a){Dictionary v;v["type"]=m->actuator_dyntype[a];v["ctrl"]=d->ctrl[a];v["act"]=numbers(m->actuator_actnum[a]?d->act+m->actuator_actadr[a]:nullptr,m->actuator_actnum[a]);actuators[String(mj_id2name(m,mjOBJ_ACTUATOR,a))]=v;}
 out["joints"]=joints;out["actuators"]=actuators;return out;
}
String restore(const Dictionary &snapshot,const mjModel*m,mjData*d){
 Dictionary joints=snapshot.get("joints",Dictionary()),actuators=snapshot.get("actuators",Dictionary());
 for(int j=0;j<m->njnt;++j){String name(mj_id2name(m,mjOBJ_JOINT,j));if(!joints.has(name))continue;Dictionary v=joints[name];if(int(v["type"])!=m->jnt_type[j])return "Checkpoint joint type changed: "+name;Array q=v["qpos"],vel=v["qvel"];for(int k=0;k<q.size();++k)d->qpos[m->jnt_qposadr[j]+k]=double(q[k]);for(int k=0;k<vel.size();++k)d->qvel[m->jnt_dofadr[j]+k]=double(vel[k]);}
 for(int a=0;a<m->nu;++a){String name(mj_id2name(m,mjOBJ_ACTUATOR,a));if(!actuators.has(name))continue;Dictionary v=actuators[name];Array act=v["act"];if(int(v["type"])!=m->actuator_dyntype[a]||act.size()!=m->actuator_actnum[a])return "Checkpoint actuator state changed: "+name;d->ctrl[a]=double(v["ctrl"]);for(int k=0;k<act.size();++k)d->act[m->actuator_actadr[a]+k]=double(act[k]);}
 return {};
}
}
void MjPhysicsServer3D::remember_initial_state(MjSpace&s){
 Dictionary current=capture(s.model,s.data);
 if(s.born_state.is_empty()){s.born_state=current;return;}
 for(const char*key:{"joints","actuators"}){Dictionary old=s.born_state[key],now=current[key],retained;Array names=now.keys();for(int i=0;i<names.size();++i){Variant name=names[i];retained[name]=old.has(name)?old[name]:now[name];}s.born_state[key]=retained;}
}
int64_t MjPhysicsServer3D::scene_request_world_command(const RID&r,const String&command,int count){
 std::lock_guard<std::mutex> lock(requests_mutex);
 if(world_commands.size()>=64||world_command_results.size()>=256)return 0;
 for(auto &pending:world_commands)if(pending.space==r)return 0;
 int64_t id=next_request_id++;world_commands.push_back({id,r,command,count});return id;
}
Dictionary MjPhysicsServer3D::scene_world_command_result(int64_t request){std::lock_guard<std::mutex> lock(requests_mutex);auto it=world_command_results.find(request);if(it==world_command_results.end())return {};Dictionary result=it->second;world_command_results.erase(it);return result;}
void MjPhysicsServer3D::scene_cancel_world_command(int64_t request){std::lock_guard<std::mutex> lock(requests_mutex);for(auto it=viewer_commands.begin();it!=viewer_commands.end();++it)if(it->request==request){auto*s=space(it->space);if(s&&s->viewer&&int64_t(s->revision)==it->revision)for(auto&f:s->viewer->frames)if(f->id==it->frame)f->pins=std::max(0,f->pins-1);viewer_commands.erase(it);break;}for(auto it=world_commands.begin();it!=world_commands.end();++it)if(it->request==request){world_commands.erase(it);break;}world_command_results.erase(request);}
void MjPhysicsServer3D::process_world_commands(){
 std::deque<WorldCommand> pending;{std::lock_guard<std::mutex> lock(requests_mutex);pending.swap(world_commands);}
 for(auto &request:pending){Dictionary result;result["request"]=request.request;result["command"]=request.command;
  auto apply=[&]()->String {
   auto*s=space(request.space);if(!s||!s->authored_options)return "Configured runtime world was removed";
   if(s->authoring&&(s->dirty||s->design_blocked||!s->model)&&request.command!="pause")return "Wait for the current physical design to compile, or restore the committed design";
   if(s->authoring&&request.command=="pause"){s->paused=true;s->single_steps=0;return {};}
   if(!rebuild(*s))return s->last_error;
   if(s->pending_step_request)return "Previous simulation step still pending";
   String command=request.command;
   if(command=="pause"||command=="resume"){s->paused=command=="pause";s->accumulator=0;return {};}
   if(command=="step"){if(!active||!s->active)return "Single-step requires an active physics space";if(!s->paused)return "Single-step requires a paused simulation";if(request.count<1||request.count>1000)return "Step count must be 1..1000";s->single_steps=request.count;s->pending_step_request=request.request;s->skip_tick=false;return {};}
   if(command=="capture"){replace_dictionary(s->checkpoint,capture(s->model,s->data));gmj_viewer_capture_snapshot(*s);s->skip_tick=true;return {};}
   if(command=="restore_snapshot"){String error=gmj_viewer_restore_snapshot(*s);if(error.is_empty()){for(auto&entry:bodies)if(entry.second->space==s->rid)read_body(*entry.second);s->skip_tick=true;}return error;}
   if(command!="reset"&&command!="reset_initial")return "Unknown simulation command";
   if(command=="reset"&&s->checkpoint.is_empty())return "No simulation checkpoint; capture one before resetting";
   if(s->viewer)s->viewer->cancel(*s);
   // Candidate data is isolated until validation succeeds; the active data remains intact.
   mjData*candidate=mj_makeData(s->model);if(!candidate)return "Could not allocate reset candidate";
   String error=restore(s->born_state,s->model,candidate);
   if(error.is_empty()&&command=="reset")error=restore(s->checkpoint,s->model,candidate);
   candidate->time=command=="reset"?double(s->checkpoint["time"]):0.;
   if(command=="reset_initial"){
    for(auto&entry:s->imported){auto&o=*entry.second;Dictionary initial=o.author_definition.get("initial",Dictionary());
     for(auto key:initial.keys()){String short_name=key;int j=mj_name2id(s->model,mjOBJ_JOINT,(o.prefix+short_name.utf8().get_data()).c_str());if(j<0)continue;Array values=initial[key];int count=s->model->jnt_type[j]==mjJNT_FREE?7:s->model->jnt_type[j]==mjJNT_BALL?4:1;if(values.size()!=count)continue;auto*p=candidate->qpos+s->model->jnt_qposadr[j];for(int k=0;k<count;k++)p[k]=double(values[k]);if(s->model->jnt_type[j]==mjJNT_FREE){Basis rotation=godot_to_mj(o.pose.basis);Vector3 position=rotation.xform(Vector3(p[0],p[1],p[2]))+godot_to_mj(o.pose.origin);Quaternion q=rotation.get_rotation_quaternion()*Quaternion(p[4],p[5],p[6],p[3]);for(int k=0;k<3;k++)p[k]=position[k];p[3]=q.w;p[4]=q.x;p[5]=q.y;p[6]=q.z;}}
     Dictionary controls=o.author_definition.get("initial_controls",Dictionary());for(auto key:controls.keys()){String name=key;int a=mj_name2id(s->model,mjOBJ_ACTUATOR,(o.prefix+name.utf8().get_data()).c_str());if(a>=0)candidate->ctrl[a]=double(controls[key]);}
    }
    mju_zero(candidate->qvel,s->model->nv);
   }
   // Legacy checkpoint reset retains externally controlled mocap poses.
   // Initial reset uses the compiled design's poses, including paused edits.
   if(command=="reset"){
    mju_copy(candidate->mocap_pos,s->data->mocap_pos,3*s->model->nmocap);
    mju_copy(candidate->mocap_quat,s->data->mocap_quat,4*s->model->nmocap);
   }
   for(int i=0;i<3*s->model->nmocap;++i)if(!std::isfinite(candidate->mocap_pos[i]))error="Nonfinite reset mocap position";
   for(int i=0;i<4*s->model->nmocap;++i)if(!std::isfinite(candidate->mocap_quat[i]))error="Nonfinite reset mocap orientation";
   if(error.is_empty()){
    mj_normalizeQuat(s->model,candidate->qpos);mj_forward(s->model,candidate);
    for(int i=0;i<s->model->nv;++i)if(!std::isfinite(candidate->qacc[i])||!std::isfinite(candidate->qvel[i]))error="Nonfinite reset dynamics";
    for(int i=0;i<s->model->nq;++i)if(!std::isfinite(candidate->qpos[i]))error="Nonfinite reset position";
   }
   if(!error.is_empty()){mj_deleteData(candidate);return error;}
   // No force or warm-start history is restored; contacts are freshly recomputed.
   mju_zero(candidate->qacc_warmstart,s->model->nv);
   mj_deleteData(s->data);s->data=candidate;s->accumulator=0;s->single_steps=0;s->skip_tick=true;
   if(s->viewer){s->viewer->history_count=0;s->viewer->history_cursor=-1;s->viewer->add_history(*s);}
   for(auto &entry:bodies){auto&b=*entry.second;if(b.space!=s->rid)continue;b.force=Vector3();b.torque=Vector3();b.constant_force=Vector3();b.constant_torque=Vector3();b.sleeping=false;read_body(b);}
   return {};
  };
  String error=apply();result["success"]=error.is_empty();result["error"]=error;
  if(request.command=="step"&&error.is_empty())continue; // Complete only after real integration.
  auto*s=space(request.space);if(s&&s->data){result["time"]=s->data->time;result["paused"]=s->paused;}
  std::lock_guard<std::mutex> lock(requests_mutex);world_command_results[request.request]=result;
 }
}
void MjPhysicsServer3D::complete_world_step(MjSpace&s,const String&error){
 if(!s.pending_step_request)return;
 Dictionary result;result["request"]=s.pending_step_request;result["command"]="step";
 result["success"]=error.is_empty();result["error"]=error;result["time"]=s.data?s.data->time:0;result["paused"]=s.paused;
 std::lock_guard<std::mutex> lock(requests_mutex);world_command_results[s.pending_step_request]=result;s.pending_step_request=0;
}

}
