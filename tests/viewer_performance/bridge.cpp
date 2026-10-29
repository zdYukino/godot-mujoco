// Only compiled with GMJ_VIEWER_BENCHMARK. All operations run in the dedicated
// main-thread test process, outside physics/query callbacks.
#include "../../src/physics/mj_physics_server.h"
#include <algorithm>
#include <cmath>
#include <fstream>
#include <dlfcn.h>
#include <cstring>
#include <mujoco/mjxmacro.h>
#include <godot_cpp/classes/node.hpp>

namespace godot {
double gmj_benchmark_step_us = 0;
double gmj_benchmark_state_us = 0;
double gmj_benchmark_info_us = 0;
double gmj_benchmark_ray_us = 0;
uint64_t gmj_benchmark_ray_count = 0;

// Runtime RID prefixes may change between fresh Godot processes. Before using
// the exact frozen MJB, prove that every non-name model array/options matches.
static String equivalent(const mjModel *a,const mjModel *b) {
#define X(field) if(std::strcmp(#field,"nnames")&&std::strcmp(#field,"nbuffer")&&a->field!=b->field)return "Model size changed: " #field;
 MJMODEL_SIZES
#undef X
 MJMODEL_POINTERS_PREAMBLE(a)
#define X(type,field,nr,nc) if(std::strncmp(#field,"name",4)&&a->nr*(nc)>0&&std::memcmp(a->field,b->field,sizeof(type)*a->nr*(nc)))return "Model array changed: " #field;
#define XNV X
 MJMODEL_POINTERS
#undef XNV
#undef X
#define X(type,field,n) if(a->opt.field!=b->opt.field)return "Physics option changed: " #field;
#define XVEC(type,field,n) if(std::memcmp(a->opt.field,b->opt.field,sizeof(type)*(n)))return "Physics option changed: " #field;
 MJOPTION_FIELDS
#undef XVEC
#undef X
 if(std::memcmp(&a->vis,&b->vis,sizeof(mjVisual))||std::memcmp(&a->stat,&b->stat,sizeof(mjStatistic)))return "Visual/statistic options changed";
 return {};
}

Dictionary MjPhysicsServer3D::scene_benchmark(const RID &rid, const String &action, const Dictionary &payload) {
 Dictionary out;
 auto fail=[&](const char *message){out["error"]=message;return out;};
 auto *s=space(rid);
 if(!s||!s->model||!s->data||flushing||s->dirty||s->design_blocked||s->candidate)
  return fail("Benchmark requires a ready, unchanging world outside query callbacks");
 auto *m=s->model;auto *d=s->data;
 out["error"]="";
 if(action=="metrics") {
  out["step_us"]=gmj_benchmark_step_us;out["state_us"]=gmj_benchmark_state_us;out["info_us"]=gmj_benchmark_info_us;
  out["ray_us"]=gmj_benchmark_ray_us;out["ray_count"]=int64_t(gmj_benchmark_ray_count);
  gmj_benchmark_step_us=gmj_benchmark_state_us=gmj_benchmark_info_us=0;
  gmj_benchmark_ray_us=0;gmj_benchmark_ray_count=0;
  out["time"]=d->time;out["ncon"]=d->ncon;return out;
 }
 if(!s->paused||s->pending_step_request) return fail("Pause the benchmark world first");
 Dl_info library{};dladdr(reinterpret_cast<void*>(mj_versionString),&library);
 out["mujoco_library"]=library.dli_fname?String(library.dli_fname):String();
 out["version"]=String(mj_versionString());
 if(action=="load_fixture") {
  String path=payload.get("model_path",String());
  auto*model=mj_loadModel(path.utf8().get_data(),nullptr);
  if(!model)return fail("Cannot load frozen model");
  String error=equivalent(m,model);
  Dictionary prefixes=payload.get("prefixes",Dictionary());
  for(auto&object:s->imported)if(!prefixes.has(object.second->label))error="Fixture model ownership differs";
  if(!error.is_empty()){mj_deleteModel(model);out["error"]=error;return out;}
  auto*data=mj_makeData(model);if(!data){mj_deleteModel(model);return fail("Cannot allocate frozen data");}
  for(auto&object:s->imported)object.second->prefix=String(prefixes[object.second->label]).utf8().get_data();
  s->model=model;s->data=data;s->query_sdf_fields.clear();++s->revision;
  mj_deleteData(d);mj_deleteModel(m);s->accumulator=0;s->skip_tick=false;
  return out;
 }
 const int mask=mjSTATE_INTEGRATION, size=mj_stateSize(m,mask);
 if(action=="restore"||action=="physics") {
  PackedFloat64Array state=payload.get("state",PackedFloat64Array());
  if(state.size()!=size)return fail("Integration state length does not match this model");
  for(int i=0;i<size;++i)if(!std::isfinite(state[i]))return fail("Nonfinite integration state");
  mj_resetData(m,d);mj_setState(m,d,state.ptr(),mask);mj_forward(m,d);
  s->accumulator=0;s->skip_tick=false;s->single_steps=0;
  if(action=="restore")return out;
  int count=payload.get("steps",10000);double tick=payload.get("tick",1.0/60);
  if(count<1||count>10000000||tick<=0||!std::isfinite(tick))return fail("Invalid physics benchmark size/tick");
  int completed=0, frame=0;double begin=d->time;
  auto start=std::chrono::steady_clock::now();
  while(completed<count) {
   // Match the production physics tick's substep grouping, but never wait for
   // SceneTree's 60-Hz scheduler. Include real backend bookkeeping and forward.
   int batch=int(std::floor((frame+1)*tick/m->opt.timestep+1e-8))-int(std::floor(frame*tick/m->opt.timestep+1e-8));
   ++frame;if(batch==0)continue;
   batch=std::min(batch,count-completed);s->single_steps=batch;
   _step(float(tick));completed+=batch;
  }
  out["elapsed_s"]=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();
  out["steps"]=completed;out["time_delta"]=d->time-begin;out["tick"]=tick;
 }
 else if(action=="capture") {
  String path=payload.get("model_path",String());
  if(path.is_empty())return fail("Missing model output path");
  mj_saveModel(m,path.utf8().get_data(),nullptr,0);
  std::ifstream saved(path.utf8().get_data(),std::ios::binary);
  if(!saved)return fail("Cannot write compiled model");
  out["mask"]=mask;out["version"]=String(mj_versionString());
  out["nq"]=m->nq;out["nv"]=m->nv;out["na"]=m->na;out["nu"]=m->nu;out["nbody"]=m->nbody;out["ngeom"]=m->ngeom;out["state_size"]=size;
  out["revision"]=int64_t(s->revision);out["design_revision"]=int64_t(s->committed_design_revision);
  out["timestep"]=m->opt.timestep;
  Dictionary models;for(auto&object:s->imported)models[object.second->label]=String(object.second->prefix.c_str());out["models"]=models;
  Array geoms;
  for(int g=0;g<m->ngeom;++g){Dictionary geom;const char*n=mj_id2name(m,mjOBJ_GEOM,g);geom["name"]=n?String(n):String();geom["id"]=g;geom["type"]=m->geom_type[g];geom["group"]=m->geom_group[g];geom["position"]=mj_to_godot(Vector3(d->geom_xpos[3*g],d->geom_xpos[3*g+1],d->geom_xpos[3*g+2]));
   const float*rgba=m->geom_matid[g]>=0?m->mat_rgba+4*m->geom_matid[g]:m->geom_rgba+4*g;Array color;for(int k=0;k<4;++k)color.push_back(rgba[k]);geom["rgba"]=color;
   if(g<int(s->geom_owners.size())){auto*owner=body(s->geom_owners[g].first);auto*node=owner?Object::cast_to<Node>(ObjectDB::get_instance(owner->object_id)):nullptr;if(node)geom["node_path"]=String(node->get_path());}
   geoms.push_back(geom);}
  out["geoms"]=geoms;
 }
 else if(action!="state")return fail("Unknown benchmark action");
 PackedFloat64Array state;state.resize(size);mj_getState(m,d,state.ptrw(),mask);out["state"]=state;
 int warnings=0;for(int i=0;i<mjNWARNING;++i)warnings+=d->warning[i].number;out["warnings"]=warnings;
 return out;
}
}
