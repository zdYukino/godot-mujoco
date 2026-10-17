#include "mj_physics_server.h"
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <algorithm>
#include <cmath>
#include <sstream>
#include <iomanip>

namespace godot {
namespace {
bool belongs(const char *name,const std::string &prefix){return name && std::string(name).rfind(prefix,0)==0;}
bool rigid_pose(const Transform3D &t){return t.is_finite() && t.basis.is_orthogonal() && t.basis.get_scale().is_equal_approx(Vector3(1,1,1)) && t.basis.determinant()>0;}
Transform3D geom_pose(const mjData *d,int g){const auto *p=d->geom_xpos+3*g,*m=d->geom_xmat+9*g;Basis b;for(int r=0;r<3;++r)for(int c=0;c<3;++c)b[r][c]=m[3*r+c];return Transform3D(mj_to_godot(b),mj_to_godot(Vector3(p[0],p[1],p[2])));}
}
void MjPhysicsServer3D::_bind_methods(){
 ClassDB::bind_method(D_METHOD("scene_pause","space","paused"),&MjPhysicsServer3D::scene_pause);
 ClassDB::bind_method(D_METHOD("scene_import_g1","space","path","label","pose"),&MjPhysicsServer3D::scene_import_g1);
 ClassDB::bind_method(D_METHOD("scene_add_box","space","label","pose","size","mass"),&MjPhysicsServer3D::scene_add_box);
 ClassDB::bind_method(D_METHOD("scene_remove","space","object"),&MjPhysicsServer3D::scene_remove);
 ClassDB::bind_method(D_METHOD("scene_info","space"),&MjPhysicsServer3D::scene_info);
 ClassDB::bind_method(D_METHOD("scene_state","space","object"),&MjPhysicsServer3D::scene_state);
 ClassDB::bind_method(D_METHOD("scene_geometry","space","object"),&MjPhysicsServer3D::scene_geometry);
 ClassDB::bind_method(D_METHOD("scene_set_control","space","object","joint","target"),&MjPhysicsServer3D::scene_set_control);
}
bool MjPhysicsServer3D::scene_pause(const RID &r,bool value){auto*s=space(r);if(!s||flushing)return false;if(!rebuild(*s))return false;s->paused=value;return true;}
RID MjPhysicsServer3D::scene_insert(MjSpace &s,mjSpec *spec,const String &label,const Transform3D &pose){
 std::unique_ptr<MjImported> object=std::make_unique<MjImported>();object->spec=spec;
 if(!s.paused||flushing){s.last_error="Pause the space outside physics callbacks before editing";return {};}
 if(!rigid_pose(pose)||label.is_empty()){s.last_error="A nonempty unique label and finite rigid pose are required";return {};}
 for(auto &e:s.imported)if(e.second->label==label){s.last_error="Duplicate object label";return {};}
 int serial=0;for(auto*e=mjs_firstElement(spec,mjOBJ_GEOM);e;e=mjs_nextElement(spec,e))mjs_setName(e,("geom_"+std::to_string(serial++)).c_str());
 RID id=handles.make_rid(0);object->rid=id;object->label=label;object->pose=pose;object->prefix="import_"+std::to_string(id.get_id())+"_";
 bool was_dirty=s.dirty;s.imported[id.get_id()]=std::move(object);s.dirty=true;
 if(!rebuild(s)){s.imported.erase(id.get_id());handles.free(id);s.dirty=was_dirty;return {};}
 return id;
}
RID MjPhysicsServer3D::scene_import_g1(const RID &r,const String &path,const String &label,const Transform3D &pose){
 auto*s=space(r);if(!s)return {};s->last_error="";
 if(!s->paused||flushing){s->last_error="Pause the space before importing";return {};}
 String absolute=ProjectSettings::get_singleton()->globalize_path(path);
 if(!FileAccess::file_exists(absolute)){s->last_error="URDF file does not exist";return {};}
 char error[2048]={};mjSpec *spec=mj_parseXML(absolute.utf8().get_data(),nullptr,error,sizeof(error));
 if(!spec){s->last_error=String::utf8(error);return {};}
 // G1's URDF repeats meshes/ in meshdir and filenames. Resolve copies of
 // the spec's paths to absolute files; never rewrite the upstream URDF/assets.
 spec->strippath=false;mjs_setString(spec->compiler.meshdir,"");
 for(auto*e=mjs_firstElement(spec,mjOBJ_MESH);e;e=mjs_nextElement(spec,e)){
  auto*m=mjs_asMesh(e);String name=String::utf8(mjs_getString(m->file)).get_file();
  String resolved=absolute.get_base_dir().path_join("meshes").path_join(name);mjs_setString(m->file,resolved.utf8().get_data());
 }
 mjModel *source=mj_compile(spec,nullptr);
 if(!source){s->last_error=String::utf8(mjs_getError(spec));mj_deleteSpec(spec);return {};}
 bool compatible=source->njnt==29&&source->nq==29&&source->nv==29&&source->nu==0&&source->nmesh==34;
 mj_deleteModel(source);
 if(!compatible){s->last_error="Expected fixed-base G1 URDF: 29 hinge joints, 34 meshes, no source actuators";mj_deleteSpec(spec);return {};}
 // Explicit synthetic bounded position drives, not a Unitree controller.
 // Compensation holds the fixed-base robot against gravity; world gravity
 // and robot/obstacle contacts remain enabled. Self-contact is excluded by mask.
 for(auto*e=mjs_firstElement(spec,mjOBJ_BODY);e;e=mjs_nextElement(spec,e))mjs_asBody(e)->gravcomp=1;
 for(auto*e=mjs_firstElement(spec,mjOBJ_GEOM);e;e=mjs_nextElement(spec,e)){auto*g=mjs_asGeom(e);if(g->contype||g->conaffinity){g->contype=2;g->conaffinity=1;}}
 for(auto*e=mjs_firstElement(spec,mjOBJ_JOINT);e;e=mjs_nextElement(spec,e)){
  auto*j=mjs_asJoint(e);if(j->type!=mjJNT_HINGE){s->last_error="G1 joints must be hinges";mj_deleteSpec(spec);return {};}
  const char *name=mjs_getString(mjs_getName(e));auto*a=mjs_addActuator(spec,nullptr);
  mjs_setName(a->element,(std::string(name)+"_position").c_str());mjs_setString(a->target,name);
  a->trntype=mjTRN_JOINT;a->gear[0]=1;a->gaintype=mjGAIN_FIXED;a->gainprm[0]=100;
  a->biastype=mjBIAS_AFFINE;a->biasprm[1]=-100;a->biasprm[2]=-10;
  a->ctrllimited=mjLIMITED_TRUE;a->ctrlrange[0]=j->range[0];a->ctrlrange[1]=j->range[1];
  a->forcelimited=mjLIMITED_TRUE;a->forcerange[0]=j->actfrcrange[0];a->forcerange[1]=j->actfrcrange[1];
 }
 return scene_insert(*s,spec,label,pose);
}
RID MjPhysicsServer3D::scene_add_box(const RID &r,const String &label,const Transform3D &pose,const Vector3 &size,double mass){
 auto*s=space(r);if(!s)return {};
 if(!size.is_finite()||size.x<=0||size.y<=0||size.z<=0||!std::isfinite(mass)||mass<0){s->last_error="Invalid box size or mass";return {};}
 std::ostringstream xml;xml.imbue(std::locale::classic());xml<<std::setprecision(17)<<"<mujoco><worldbody><body name='box'>";
 if(mass>0)xml<<"<freejoint name='free'/>";
 xml<<"<geom type='box' size='"<<size.x/2<<" "<<size.z/2<<" "<<size.y/2<<"' contype='1' conaffinity='3' mass='"<<(mass>0?mass:1)<<"'/></body></worldbody></mujoco>";
 char error[2048]={};auto*spec=mj_parseXMLString(xml.str().c_str(),nullptr,error,sizeof(error));if(!spec){s->last_error=String::utf8(error);return {};}
 return scene_insert(*s,spec,label,pose);
}
bool MjPhysicsServer3D::scene_remove(const RID &r,const RID &id){
 auto*s=space(r);if(!s)return false;if(!s->paused||flushing){s->last_error="Pause the space before removing objects";return false;}
 auto it=s->imported.find(id.get_id());if(it==s->imported.end()){s->last_error="Unknown object RID in this space";return false;}
 auto saved=std::move(it->second);s->imported.erase(it);bool was_dirty=s->dirty;s->dirty=true;
 if(!rebuild(*s)){s->imported[id.get_id()]=std::move(saved);s->dirty=was_dirty;return false;}
 handles.free(id);return true;
}
Dictionary MjPhysicsServer3D::scene_info(const RID &r) const {
 Dictionary result;auto*s=space(r);if(!s)return result;result["paused"]=s->paused;result["revision"]=int64_t(s->revision);result["last_error"]=s->last_error;
 Array objects;for(auto &e:s->imported){Dictionary o;o["rid"]=e.second->rid;o["label"]=e.second->label;o["prefix"]=String(e.second->prefix.c_str());objects.push_back(o);}result["objects"]=objects;
 if(!s->model)return result;auto*m=s->model;auto*d=s->data;result["nbody"]=m->nbody;result["ngeom"]=m->ngeom;result["njnt"]=m->njnt;result["nu"]=m->nu;result["ncon"]=d->ncon;result["time"]=d->time;result["version"]=String(mj_versionString());
 int warnings=0;for(int i=0;i<mjNWARNING;++i)warnings+=d->warning[i].number;result["warning_count"]=warnings;
 Array contacts;for(int i=0;i<d->ncon;++i){Array pair;for(int side=0;side<2;++side){int g=d->contact[i].geom[side];RID owner;for(auto&e:s->imported)if(belongs(mj_id2name(m,mjOBJ_GEOM,g),e.second->prefix))owner=e.second->rid;pair.push_back(owner);}contacts.push_back(pair);}result["contacts"]=contacts;return result;
}
Dictionary MjPhysicsServer3D::scene_state(const RID &r,const RID &id) const {
 Dictionary result;auto*s=space(r);if(!s||!s->model)return result;auto it=s->imported.find(id.get_id());if(it==s->imported.end())return result;
 auto&m=*s->model;auto&d=*s->data;auto &prefix=it->second->prefix;result["rid"]=id;result["label"]=it->second->label;
 Dictionary joints,controls;Array geoms;int body_count=0;
 for(int b=1;b<m.nbody;++b)if(belongs(mj_id2name(&m,mjOBJ_BODY,b),prefix))++body_count;
 for(int j=0;j<m.njnt;++j){const char*n=mj_id2name(&m,mjOBJ_JOINT,j);if(!belongs(n,prefix))continue;int nq=m.jnt_type[j]==mjJNT_FREE?7:(m.jnt_type[j]==mjJNT_BALL?4:1),nv=m.jnt_type[j]==mjJNT_FREE?6:(m.jnt_type[j]==mjJNT_BALL?3:1);PackedFloat64Array q,v;for(int k=0;k<nq;++k)q.push_back(d.qpos[m.jnt_qposadr[j]+k]);for(int k=0;k<nv;++k)v.push_back(d.qvel[m.jnt_dofadr[j]+k]);Dictionary state;state["qpos"]=q;state["qvel"]=v;joints[String(n+prefix.size())]=state;}
 for(int a=0;a<m.nu;++a){const char*n=mj_id2name(&m,mjOBJ_ACTUATOR,a);if(belongs(n,prefix))controls[String(n+prefix.size())]=d.ctrl[a];}
 for(int g=0;g<m.ngeom;++g)if(belongs(mj_id2name(&m,mjOBJ_GEOM,g),prefix)){Dictionary geo;geo["name"]=String(mj_id2name(&m,mjOBJ_GEOM,g));geo["transform"]=geom_pose(&d,g);geoms.push_back(geo);}
 result["body_count"]=body_count;result["joints"]=joints;result["controls"]=controls;result["geoms"]=geoms;return result;
}
bool MjPhysicsServer3D::scene_set_control(const RID &r,const RID &id,const String &joint,double target){
 auto*s=space(r);if(!s||!s->model||!std::isfinite(target))return false;auto it=s->imported.find(id.get_id());if(it==s->imported.end())return false;
 std::string name=it->second->prefix+joint.utf8().get_data()+std::string("_position");int a=mj_name2id(s->model,mjOBJ_ACTUATOR,name.c_str());if(a<0||target<s->model->actuator_ctrlrange[2*a]||target>s->model->actuator_ctrlrange[2*a+1])return false;s->data->ctrl[a]=target;return true;
}
Array MjPhysicsServer3D::scene_geometry(const RID &r,const RID &id) const {
 Array result;auto*s=space(r);if(!s||!s->model)return result;auto it=s->imported.find(id.get_id());if(it==s->imported.end())return result;auto*m=s->model;
 for(int g=0;g<m->ngeom;++g){const char*n=mj_id2name(m,mjOBJ_GEOM,g);if(!belongs(n,it->second->prefix))continue;
  Dictionary geo;geo["name"]=String(n);geo["type"]=m->geom_type[g];geo["visual"]=m->geom_group[g]==1;geo["transform"]=geom_pose(s->data,g);geo["size"]=Vector3(m->geom_size[3*g],m->geom_size[3*g+2],m->geom_size[3*g+1]);
  if(m->geom_type[g]==mjGEOM_MESH){int mesh=m->geom_dataid[g];PackedVector3Array vertices,normals;
   for(int f=0;f<m->mesh_facenum[mesh];++f){Vector3 triangle[3];for(int k=0;k<3;++k){int v=m->mesh_vertadr[mesh]+m->mesh_face[3*(m->mesh_faceadr[mesh]+f)+k];auto*p=m->mesh_vert+3*v;triangle[k]=mj_to_godot(Vector3(p[0],p[1],p[2]));}Vector3 normal=(triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).normalized();for(int k:{0,2,1}){vertices.push_back(triangle[k]);normals.push_back(normal);}}
   geo["vertices"]=vertices;geo["normals"]=normals;
  }
  result.push_back(geo);
 }
 return result;
}
} // namespace godot
