#include "mj_physics_server.h"
#include "mj_assets.h"
#include <godot_cpp/classes/project_settings.hpp>
#include <atomic>
#include <thread>
#include <cstring>
#include <cmath>

namespace godot {
thread_local bool gmj_background_worker=false;
struct MjAsyncCandidate {
 std::atomic<bool> ready{false};
 uint64_t revision=0;
 mjModel *model=nullptr; mjData *data=nullptr;
 std::string error;
 std::vector<std::pair<RID,int>> owners;
 std::map<std::string,std::string> aliases;std::set<std::string> reset;
 ~MjAsyncCandidate(){if(data)mj_deleteData(data);if(model)mj_deleteModel(model);}
};
namespace {
Array numbers(const mjtNum *p,int n){Array result;for(int i=0;i<n;++i)result.push_back(p[i]);return result;}
Dictionary dynamic_snapshot(const mjModel*m,const mjData*d){
 Dictionary result,joints,actuators;if(!m||!d)return result;result["time"]=d->time;
 for(int j=0;j<m->njnt;++j){Dictionary state;int type=m->jnt_type[j],nq=type==mjJNT_FREE?7:type==mjJNT_BALL?4:1,nv=type==mjJNT_FREE?6:type==mjJNT_BALL?3:1;
  state["type"]=type;state["qpos"]=numbers(d->qpos+m->jnt_qposadr[j],nq);state["qvel"]=numbers(d->qvel+m->jnt_dofadr[j],nv);state["warmstart"]=numbers(d->qacc_warmstart+m->jnt_dofadr[j],nv);joints[String::utf8(mj_id2name(m,mjOBJ_JOINT,j))]=state;
 }
 for(int a=0;a<m->nu;++a){Dictionary state;state["type"]=m->actuator_dyntype[a];state["ctrl"]=d->ctrl[a];state["act"]=numbers(m->actuator_actnum[a]?d->act+m->actuator_actadr[a]:nullptr,m->actuator_actnum[a]);actuators[String::utf8(mj_id2name(m,mjOBJ_ACTUATOR,a))]=state;}
 result["joints"]=joints;result["actuators"]=actuators;return result;
}
Dictionary entity_map(const Dictionary&definition){Dictionary result;Array entities=definition.get("entities",Array());for(int i=0;i<entities.size();++i){Dictionary e=entities[i];result[e["id"]]=e;}return result;}
void migration_map(const MjImported&o,Dictionary &aliases,Dictionary &reset){
 Dictionary old=entity_map(o.committed_definition),now=entity_map(o.author_definition),affected;
 bool moved=o.has_committed_pose&&o.committed_pose!=o.pose;
 Array ids=now.keys();
 for(int i=0;i<ids.size();++i){Dictionary e=now[ids[i]];if(!old.has(ids[i]))continue;Dictionary previous=old[ids[i]],a=e.get("attrs",Dictionary()),b=previous.get("attrs",Dictionary());
  bool changed=e.get("parent_id",String())!=previous.get("parent_id",String());
  for(const char*key:{"type","axis","pos","quat"})if(a.get(key,Variant())!=b.get(key,Variant()))changed=true;
  if(changed){affected[ids[i]]=true;if(String(e.get("kind",String()))=="joint")affected[e.get("parent_id",String())]=true;}
 }
 bool more=true;while(more){more=false;for(int i=0;i<ids.size();++i){Dictionary e=now[ids[i]];if(!affected.has(ids[i])&&affected.has(e.get("parent_id",String()))){affected[ids[i]]=true;more=true;}}}
 Dictionary initial=o.author_definition.get("initial",Dictionary()),previous_initial=o.committed_definition.get("initial",Dictionary());
 for(int i=0;i<ids.size();++i){Dictionary e=now[ids[i]];if(String(e.get("kind",String()))!="joint")continue;String full=String(o.prefix.c_str())+String(e["name"]);
  if(old.has(ids[i])){Dictionary previous=old[ids[i]];aliases[full]=String(o.prefix.c_str())+String(previous["name"]);}
  if(moved||affected.has(ids[i])||initial.get(e["name"],Variant())!=previous_initial.get(old.has(ids[i])?Dictionary(old[ids[i]]).get("name",e["name"]):e["name"],Variant()))reset[full]=true;
 }
}
}
bool MjPhysicsServer3D::scene_enable_authoring(const RID&r,const String&xml){
 auto*s=space(r);if(!s||flushing)return false;char error[2048]={};auto*spec=mj_parseXMLString(xml.utf8().get_data(),nullptr,error,sizeof(error));
 if(!spec){s->last_error=String::utf8(error);return false;}
 if(mjs_firstElement(spec,mjOBJ_PLUGIN)){mj_deleteSpec(spec);s->last_error="Plugins are disabled";return false;}
 auto options=spec->option;mj_deleteSpec(spec);
 if(!std::isfinite(options.timestep)||options.timestep<.0001||options.timestep>.1){s->last_error="World timestep must be at least .0001 s";return false;}
 s->options=options;s->authoring=true;s->authored_options=true;s->paused=true;s->dirty=true;s->design_blocked=true;s->compile_status="pending";++s->design_revision;
 s->gravity_direction=mj_to_godot(Vector3(s->options.gravity[0],s->options.gravity[1],s->options.gravity[2]));s->gravity=s->gravity_direction.length();if(s->gravity>0)s->gravity_direction/=s->gravity;
 return true;
}
bool MjPhysicsServer3D::scene_pause_for_author(const RID&r,bool invalidate){auto*s=space(r);if(!s||!s->authoring)return false;s->paused=true;s->single_steps=0;s->design_blocked=true;if(invalidate)++s->design_revision;s->compile_status=invalidate?"editing":"rendering";return true;}
bool MjPhysicsServer3D::scene_reset_author_body(const RID&r,const RID&id){auto*s=space(r);auto*b=body(id);if(!s||!b||b->space!=r||!s->authoring)return false;s->author_reset_bodies.insert(id.get_id());b->linear_velocity=Vector3();b->angular_velocity=Vector3();dirty(r);return true;}
bool MjPhysicsServer3D::scene_author_views_ready(const RID&r){auto*s=space(r);if(!s||!s->authoring||s->dirty||!s->model)return false;s->design_blocked=false;s->compile_status="ready";return true;}
void MjPhysicsServer3D::scene_close_authoring(const RID&r){
 auto*s=space(r);if(!s||!s->authoring)return;s->paused=true;s->candidate.reset();
 for(auto&entry:s->imported)handles.free(entry.second->rid);
 s->imported.clear();s->committed_bodies.clear();s->committed_shapes.clear();s->committed_areas.clear();s->imported_query_owners.clear();s->geom_owners.clear();s->query_sdf_fields.clear();
 s->born_state.clear();s->checkpoint.clear();s->prepared_owners.clear();
 auto*model=s->model;auto*data=s->data;s->model=nullptr;s->data=nullptr;s->compile_status="closed";s->design_blocked=true;s->dirty=true;
 if(model||data)async_threads.emplace_back([model,data](){gmj_background_worker=true;if(data)mj_deleteData(data);if(model)mj_deleteModel(model);});
}
RID MjPhysicsServer3D::scene_stage_author_model(const RID&r,const RID&id,const Dictionary&definition){
 auto*s=space(r);if(!s||!s->authoring)return {};String xml=definition.get("xml",String());if(xml.is_empty()){s->last_error="Missing author XML";return {};}
 Transform3D pose=definition.get("pose",Transform3D());if(!pose.is_finite()||!pose.basis.is_orthogonal()||!pose.basis.get_scale().is_equal_approx(Vector3(1,1,1))||pose.basis.determinant()<0){s->last_error="Model placement must be a finite rigid transform";return {};}
 RID result=id;MjImported*object=nullptr;
 if(id.is_valid()){auto found=s->imported.find(id.get_id());if(found==s->imported.end()){s->last_error="Unknown author model handle";return {};}object=found->second.get();}
 else{result=handles.make_rid(0);auto value=std::make_unique<MjImported>();value->rid=result;value->whole_model=true;value->prefix="import_"+std::to_string(result.get_id())+"_";object=value.get();s->imported[result.get_id()]=std::move(value);}
 Dictionary lean;Array entities=definition.get("entities",Array()),layout;
 for(int i=0;i<entities.size();++i){Dictionary source=entities[i],item;for(const char*key:{"id","kind","name","parent_id","attrs"})if(source.has(key))item[key]=source[key];layout.push_back(item);}
 lean["entities"]=layout;lean["initial"]=definition.get("initial",Dictionary());lean["initial_controls"]=definition.get("initial_controls",Dictionary());lean["revision"]=definition.get("revision",0);lean["mesh_options"]=definition.get("mesh_options",Dictionary());
 object->runtime_drives.clear();object->author_xml=xml;object->author_definition=lean;object->pose=pose;object->label=definition.get("label",String("Model"));object->query_object_id=uint64_t(int64_t(definition.get("owner",0)));
 dirty(r);return result;
}
bool MjPhysicsServer3D::scene_stage_author_remove(const RID&r,const RID&id){auto*s=space(r);if(!s||!s->authoring)return false;auto it=s->imported.find(id.get_id());if(it==s->imported.end())return false;it->second->author_definition["removed"]=true;dirty(r);return true;}
Dictionary MjPhysicsServer3D::scene_async_snapshot(const RID&r){
 Dictionary result;auto*s=space(r);if(!s||!s->authoring||!s->dirty||s->compile_status=="editing")return result;
 s->preparing_source=true;bool ok=rebuild(*s);s->preparing_source=false;
 if(!ok){result["error"]=s->last_error;return result;}
 result["op"]="world";result["base_xml"]=s->prepared_xml;result["revision"]=int64_t(s->design_revision);result["state"]=dynamic_snapshot(s->model,s->data);
 PackedByteArray options;options.resize(sizeof(mjOption));std::memcpy(options.ptrw(),&s->options,sizeof(mjOption));result["options"]=options;
 Array sources;Dictionary aliases,reset;
 for(auto &entry:s->imported){auto&o=*entry.second;if(bool(o.author_definition.get("removed",false)))continue;
  Dictionary source;source["xml"]=o.author_xml.is_empty()&&o.spec?gmj_spec_xml(o.spec):o.author_xml;source["prefix"]=String(o.prefix.c_str());source["pose"]=o.pose;source["initial"]=o.author_definition.get("initial",Dictionary());source["initial_controls"]=o.author_definition.get("initial_controls",Dictionary());source["mesh_options"]=o.author_definition.get("mesh_options",Dictionary());source["runtime_drives"]=o.runtime_drives;sources.push_back(source);migration_map(o,aliases,reset);
 }
 for(auto id:s->author_reset_bodies)reset[String("native_joint_")+String::num_uint64(id)]=true;
 result["sources"]=sources;result["aliases"]=aliases;result["reset"]=reset;s->compile_status="compiling";return result;
}
bool MjPhysicsServer3D::scene_submit_async(const RID&r,int64_t revision,const Dictionary&result){
 auto*s=space(r);if(!s||!s->authoring||revision<0||uint64_t(revision)!=s->design_revision)return false;
 String path=result.get("compiled_path",String());Dictionary snapshot=result.get("snapshot",Dictionary()),state=snapshot.get("state",Dictionary());
 Array input=state.get("integration",Array());std::vector<double> integration;for(int i=0;i<input.size();++i){double value=input[i];if(!std::isfinite(value)){s->last_error="Invalid compiled integration state";return false;}integration.push_back(value);}
 auto candidate=std::make_shared<MjAsyncCandidate>();candidate->revision=revision;candidate->owners=s->prepared_owners;{Dictionary aliases=result.get("aliases",Dictionary()),reset=result.get("reset",Dictionary());for(auto key:aliases.keys()){String k=key,v=aliases[key];candidate->aliases[k.utf8().get_data()]=v.utf8().get_data();}for(auto key:reset.keys()){String k=key;candidate->reset.insert(k.utf8().get_data());}}s->candidate=candidate;s->compile_status="loading";
 std::string filename=ProjectSettings::get_singleton()->globalize_path(path).utf8().get_data();
 async_threads.emplace_back([candidate,filename,integration=std::move(integration)](){
  gmj_background_worker=true;
  candidate->model=mj_loadModel(filename.c_str(),nullptr);
  if(!candidate->model)candidate->error="Cannot load compiled world artifact";
  else if(candidate->model->nplugin)candidate->error="Compiled plugins are disabled";
  else if(integration.size()!=size_t(mj_stateSize(candidate->model,mjSTATE_INTEGRATION)))candidate->error="Compiled world state ABI mismatch";
  else{candidate->data=mj_makeData(candidate->model);if(!candidate->data)candidate->error="Cannot allocate compiled world data";
   else{mj_setState(candidate->model,candidate->data,integration.data(),mjSTATE_INTEGRATION);mj_forward(candidate->model,candidate->data);for(int i=0;i<candidate->model->nv;++i)if(!std::isfinite(candidate->data->qacc[i]))candidate->error="Nonfinite compiled world dynamics";}}
  candidate->ready.store(true,std::memory_order_release);
 });return true;
}
void MjPhysicsServer3D::scene_async_error(const RID&r,const String&error){auto*s=space(r);if(!s)return;s->last_error=error;s->compile_status="failed";s->paused=true;s->design_blocked=true;}
void MjPhysicsServer3D::process_async_worlds(){
 for(auto &entry:spaces){auto&s=*entry.second;auto candidate=s.candidate;if(!candidate||!candidate->ready.load(std::memory_order_acquire))continue;
  s.candidate.reset();if(candidate->revision!=s.design_revision)continue;
  if(!candidate->error.empty()){scene_async_error(s.rid,String::utf8(candidate->error.c_str()));continue;}
  auto*m=candidate->model;auto*d=candidate->data;
  // Control and velocity inputs remain live while paused. Take their latest
  // compatible values; qpos comes from the validated, paused design snapshot.
  if(s.model)for(int j=0;j<m->njnt;++j){std::string name=mj_id2name(m,mjOBJ_JOINT,j);auto mapped=candidate->aliases.find(name);std::string old=mapped==candidate->aliases.end()?name:mapped->second;if(candidate->reset.count(name))continue;int previous=mj_name2id(s.model,mjOBJ_JOINT,old.c_str());if(previous<0||s.model->jnt_type[previous]!=m->jnt_type[j])continue;int nv=m->jnt_type[j]==mjJNT_FREE?6:m->jnt_type[j]==mjJNT_BALL?3:1;mju_copy(d->qvel+m->jnt_dofadr[j],s.data->qvel+s.model->jnt_dofadr[previous],nv);}
  if(s.model)for(int a=0;a<m->nu;++a){const char*name=mj_id2name(m,mjOBJ_ACTUATOR,a);int old=mj_name2id(s.model,mjOBJ_ACTUATOR,name);bool reset_target=false;if(m->actuator_trntype[a]==mjTRN_JOINT||m->actuator_trntype[a]==mjTRN_JOINTINPARENT){const char*target=mj_id2name(m,mjOBJ_JOINT,m->actuator_trnid[2*a]);reset_target=target&&candidate->reset.count(target);}if(old>=0&&!reset_target)d->ctrl[a]=s.data->ctrl[old];}
  std::vector<std::pair<RID,int>> mapped(m->ngeom);
  for(size_t i=0;i<candidate->owners.size();++i){int g=mj_name2id(m,mjOBJ_GEOM,("g"+std::to_string(i)).c_str());if(g>=0)mapped[g]=candidate->owners[i];}
  std::map<int,std::unique_ptr<MjBody>> query_owners;
  for(auto&o:s.imported){int local=0;for(int g=0;g<m->ngeom;++g){const char*name=mj_id2name(m,mjOBJ_GEOM,g);if(!name||std::string(name).rfind(o.second->prefix,0)!=0)continue;
    auto owner=std::make_unique<MjBody>();owner->rid=o.second->rid;owner->space=s.rid;owner->object_id=o.second->query_object_id;owner->layer=uint32_t(m->geom_contype[g]);owner->mj_body=m->geom_bodyid[g];owner->ray_pickable=o.second->query_ray_pickable;mapped[g]={owner->rid,local++};query_owners[g]=std::move(owner);}}
  // Repair checkpoint names and reset changed coordinate systems, so later Reset
  // cannot bring back a removed joint type or a pose from before the author edit.
  Dictionary current=dynamic_snapshot(m,d);
  for(Dictionary*checkpoint:{&s.born_state,&s.checkpoint})if(!checkpoint->is_empty())for(const char*section:{"joints","actuators"}){
   Dictionary before=checkpoint->get(section,Dictionary()),now=current[section],retained;
   for(auto key:now.keys()){String name=key;std::string n=name.utf8().get_data();auto alias=candidate->aliases.find(n);String old=alias==candidate->aliases.end()?name:String::utf8(alias->second.c_str());
    bool reset=candidate->reset.count(n);Dictionary previous=before.get(old,Dictionary()),value=now[name];
    if(!reset&&!previous.is_empty()&&int(previous.get("type",-1))==int(value.get("type",-2)))retained[name]=previous;else retained[name]=value;
   }(*checkpoint)[section]=retained;
  }
  s.author_reset_bodies.clear();
  auto*old_model=s.model;auto*old_data=s.data;s.model=m;s.data=d;candidate->model=nullptr;candidate->data=nullptr;
  s.geom_owners=std::move(mapped);s.imported_query_owners=std::move(query_owners);s.query_sdf_fields.clear();s.dirty=false;s.design_blocked=false;s.paused=true;s.last_error="";s.compile_status="ready";s.committed_design_revision=s.design_revision;++s.revision;
  for(auto it=s.imported.begin();it!=s.imported.end();){if(bool(it->second->author_definition.get("removed",false))){handles.free(it->second->rid);it=s.imported.erase(it);}else{if(it->second->has_committed_pose&&(it->second->committed_definition!=it->second->author_definition||it->second->committed_pose!=it->second->pose))++it->second->property_revision;it->second->committed_definition=it->second->author_definition.duplicate(true);it->second->committed_pose=it->second->pose;it->second->has_committed_pose=true;++it;}}
  s.committed_bodies.clear();s.committed_shapes.clear();s.committed_areas.clear();
  for(auto&area:areas)if(area.second->space==s.rid){s.committed_areas.emplace(area.first,*area.second);for(auto&instance:area.second->shapes){auto*sh=shape(instance.shape);if(sh)s.committed_shapes[sh->rid.get_id()]=*sh;}}
  for(auto &body_entry:bodies){auto&b=*body_entry.second;if(b.space!=s.rid)continue;b.mj_body=mj_name2id(m,mjOBJ_BODY,("b"+std::to_string(b.rid.get_id())).c_str());read_body(b);s.committed_bodies.emplace(body_entry.first,b);for(auto&shape_instance:b.shapes){auto*sh=shape(shape_instance.shape);if(sh){auto copy=*sh;if(copy.data.get_type()==Variant::DICTIONARY)copy.data=Dictionary(copy.data).duplicate(true);s.committed_shapes[sh->rid.get_id()]=copy;}}}
  remember_initial_state(s);
  if(old_model||old_data)async_threads.emplace_back([old_model,old_data](){gmj_background_worker=true;if(old_data)mj_deleteData(old_data);if(old_model)mj_deleteModel(old_model);});
 }
}
} // namespace godot
