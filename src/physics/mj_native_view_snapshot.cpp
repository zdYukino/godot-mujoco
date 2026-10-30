// Experimental read-only display transport. The shared world remains authoritative.
#include "mj_physics_server.h"
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <cmath>
#include <mujoco/mjxmacro.h>
#include "mj_native_view_budget.h"
namespace godot {
Dictionary MjPhysicsServer3D::scene_native_view_snapshot(const RID &rid, int64_t known_revision, bool include_model,const Dictionary &viewer_options) const {
 Dictionary out;
 auto fail=[&](const char *why){out["error"]=why;return out;};
 if(OS::get_singleton()->get_thread_caller_id()!=OS::get_singleton()->get_main_thread_id() || bool(ProjectSettings::get_singleton()->get_setting("physics/3d/run_on_separate_thread",false))) return fail("Native view requires main-thread physics and snapshot caller");
 auto*s=space(rid);
 if(!s) return fail("Shared world is unavailable");
 if(s->authoring && s->compile_status=="closed") return fail("Shared world is closed");
 if(flushing) return fail("Snapshot during physics callbacks is unsupported");
 if(s->dirty||s->design_blocked){out["pending"]=true;out["status"]=s->compile_status;return out;}
 if(!s->model||!s->data) return fail("Shared world has no committed model");
 auto*m=s->model;auto*d=s->data;
 if(!gmj_display::rigid_assets(m)) return fail("Native view excludes plugins and worlds above 9000 geoms");
 const int count=mj_stateSize(m,mjSTATE_INTEGRATION);
 if(count<0||count>1048576) return fail("Native view state exceeds bounded transport");
 PackedFloat64Array state;if(state.resize(count)!=OK)return fail("Display state allocation failed");mj_getState(m,d,state.ptrw(),mjSTATE_INTEGRATION);
 for(int i=0;i<count;++i)if(!std::isfinite(state[i]))return fail("Non-finite display state");
 out["state"]=state;out["space"]=int64_t(rid.get_id());out["revision"]=int64_t(s->revision);out["time"]=d->time;out["ngeom"]=int(m->ngeom);
 double qsum=0;for(int i=0;i<m->nq;++i)qsum+=(i+1)*d->qpos[i];out["qpos_checksum"]=qsum;
 if(known_revision!=int64_t(s->revision)){
  Dictionary profile; int64_t resident=0;
  if(!gmj_display::bounded(d->nbuffer,gmj_display::resident_limit)||!gmj_display::resident(m,int64_t(d->nbuffer),resident)||!gmj_display::decoded_admission(m,int64_t(d->nbuffer),resident))return fail("Native model resident budget rejected");
  const int64_t serialized=mj_sizeModel(m);
  profile["serialized_bytes"]=serialized;profile["model_buffer_bytes"]=int64_t(m->nbuffer);profile["data_buffer_bytes"]=int64_t(d->nbuffer);profile["data_arena_bytes"]=int64_t(d->narena);
  profile["state_bytes"]=int64_t(count)*sizeof(mjtNum);profile["nmesh"]=int64_t(m->nmesh);profile["nmeshvert"]=int64_t(m->nmeshvert);profile["nmeshface"]=int64_t(m->nmeshface);profile["texture_bytes"]=int64_t(m->ntexdata);
  Dictionary mesh_fields;int64_t mesh_total=0;
#define X(type,name,nr,nc) {int64_t elements=0,bytes=0;if(!gmj_display::bounded(m->nr,gmj_display::resident_limit)||!gmj_display::multiply(int64_t(m->nr),nc,gmj_display::resident_limit,elements)||!gmj_display::multiply(elements,sizeof(type),gmj_display::resident_limit,bytes)||!gmj_display::add(mesh_total,bytes,gmj_display::resident_limit))return fail("Mesh profile exceeds budget");mesh_fields[#name]=bytes;}
#define XNV X
  MJMODEL_POINTERS_MESH
#undef XNV
#undef X
  int64_t bvh=0,static_bvh=0,octree=0;
  if(!gmj_display::bounded(m->nbvh,gmj_display::resident_limit)||!gmj_display::bounded(m->nbvhstatic,gmj_display::resident_limit)||!gmj_display::bounded(m->noct,gmj_display::resident_limit)||
     !gmj_display::multiply(m->nbvh,16,gmj_display::resident_limit,bvh)||!gmj_display::multiply(m->nbvhstatic,6*sizeof(mjtNum),gmj_display::resident_limit,static_bvh)||!gmj_display::add(bvh,static_bvh,gmj_display::resident_limit)||!gmj_display::multiply(m->noct,36+14*sizeof(mjtNum),gmj_display::resident_limit,octree))return fail("Spatial profile exceeds budget");
  profile["bvh_bytes"]=bvh;profile["octree_bytes"]=octree;
  profile["display_resident_estimate"]=resident;
  profile["mesh_fields"]=mesh_fields;profile["mesh_field_bytes"]=mesh_total;out["model_profile"]=profile;
  if(!include_model)return out;
  const auto size=mj_sizeModel(m);
  const int64_t limit_mib=ProjectSettings::get_singleton()->get_setting("rendering/mujoco_native_view/max_model_mib",64);
  if(limit_mib<1||limit_mib>192)return fail("Native model limit must be between 1 and 192 MiB");
  out["transport_limit_bytes"]=limit_mib*gmj_display::MiB;
  if(size<=0||size>limit_mib*gmj_display::MiB)return fail("Native model exceeds configured transport limit");

  if(m->nflex||m->nskin||m->nmeshface>1000000||m->nmeshvert>600000||m->ntexdata>64*gmj_display::MiB)return fail("Native display asset budget or rigid-model scope exceeded");
  gmj_display::trace("serialize_begin",size,s->revision);
  PackedByteArray bytes;if(bytes.resize(size)!=OK)return fail("Display model allocation failed");mj_saveModel(m,nullptr,bytes.ptrw(),size);out["model"]=bytes;gmj_display::trace("serialize_end",size,s->revision);
  Array objects;for(const auto &entry:s->imported){Dictionary o;o["rid"]=entry.second->rid;o["prefix"]=String(entry.second->prefix.c_str());objects.append(o);}out["objects"]=objects;
 }
 Dictionary options=viewer_options.duplicate();options["backend"]="native";
 Dictionary frame=const_cast<MjPhysicsServer3D*>(this)->scene_viewer_frame(rid,known_revision,options);
 if(frame.has("pending")||frame.has("error"))return frame;
 out.merge(frame,true);
 return out;
}
}
