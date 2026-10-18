#include "mj_physics_server.h"
#include "mj_options.h"
#include "../mj_editor_document.h"
#include <cmath>
namespace godot {
namespace {
Array values(const mjtNum*p,int count){Array result;for(int i=0;i<count;++i)result.push_back(p[i]);return result;}
Dictionary initial_state(const mjModel*m,const mjData*d){Dictionary result,joints,controls,activation,counts;counts["geom"]=m->ngeom;counts["joint"]=m->njnt;counts["actuator"]=m->nu;counts["equality"]=m->neq;counts["tendon"]=m->ntendon;counts["sensor"]=m->nsensor;result["counts"]=counts;
 for(int j=0;j<m->njnt;++j){Dictionary state;int type=m->jnt_type[j];state["qpos"]=values(d->qpos+m->jnt_qposadr[j],type==mjJNT_FREE?7:type==mjJNT_BALL?4:1);state["qvel"]=values(d->qvel+m->jnt_dofadr[j],type==mjJNT_FREE?6:type==mjJNT_BALL?3:1);joints[String(mj_id2name(m,mjOBJ_JOINT,j))]=state;}
 for(int a=0;a<m->nu;++a){String name(mj_id2name(m,mjOBJ_ACTUATOR,a));controls[name]=d->ctrl[a];if(m->actuator_actnum[a])activation[name]=values(d->act+m->actuator_actadr[a],m->actuator_actnum[a]);}
 result["joints"]=joints;result["controls"]=controls;result["activation"]=activation;return result;
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
 auto*s=space(r);if(!s)return {};if(!s->paused||flushing||!s->authored_options){s->last_error="A configured, paused runtime world is required";return {};}
 Ref<MjEditorDocument> doc;doc.instantiate();if(!doc->restore_at(snapshot,directory)){s->last_error=doc->get_error();return {};}
 auto*m=doc->native_model();String conflict=gmj_option_conflict(s->options,m->opt);
 if(!conflict.is_empty()){s->last_error="World/model option conflict: "+conflict;return {};}
 // Global userdata and mocap target semantics do not belong to a model instance.
 // Reject rather than silently dropping or sharing those mutable global arrays.
 if(m->nuserdata||m->nmocap||m->nkey){s->last_error="Runtime composition does not support global userdata, mocap bodies or keyframes";return {};}
 return scene_insert(*s,doc->copy_spec(),label,pose,true,initial_state(m,doc->native_data()));
}
bool MjPhysicsServer3D::scene_set_actuator(const RID&r,const RID&id,const String&name,double value){
 auto*s=space(r);if(!s||!s->model||!std::isfinite(value))return false;auto it=s->imported.find(id.get_id());if(it==s->imported.end())return false;
 int a=mj_name2id(s->model,mjOBJ_ACTUATOR,(it->second->prefix+name.utf8().get_data()).c_str());if(a<0)return false;
 if(s->model->actuator_ctrllimited[a]&&(value<s->model->actuator_ctrlrange[2*a]||value>s->model->actuator_ctrlrange[2*a+1]))return false;
 s->data->ctrl[a]=value;return true;
}
bool MjPhysicsServer3D::scene_release_model(const RID&r,const RID&id){auto*s=space(r);if(!s||!s->imported.count(id.get_id()))return false;if(flushing){pending_free.insert(id.get_id());return true;}bool paused=s->paused;s->paused=true;bool ok=scene_remove(r,id);s->paused=paused;return ok;}
}
