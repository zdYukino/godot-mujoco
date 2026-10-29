#pragma once
#include "mj_sdf_interval.h"
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <set>
namespace godot {
inline Array gmj_collision_stats(const mjModel*model) {
 Array result;if(!model)return result;std::set<int> used;
 for(int g=0;g<model->ngeom;++g)if(model->geom_type[g]==mjGEOM_SDF)used.insert(model->geom_dataid[g]);
 for(int mesh:used){
  int root=model->mesh_octadr[mesh],count=model->mesh_octnum[mesh],depth=0;
  for(int n=0;n<count;++n)depth=std::max(depth,model->oct_depth[root+n]);
  gmj_sdf::Field field(model,mesh);Dictionary stat;
  const char*label=mj_id2name(model,mjOBJ_MESH,mesh);stat["mesh"]=label?String::utf8(label):String();
  stat["triangles"]=model->mesh_facenum[mesh];stat["cells"]=count;stat["depth"]=depth;stat["query_valid"]=field.valid;result.push_back(stat);
 }return result;
}
}
