#pragma once
#include <mujoco/mujoco.h>
#include <godot_cpp/variant/dictionary.hpp>
#include <cmath>

namespace godot {
// Only collision detection options are inherited. Other mjOption differences
// remain errors, including unrelated bits in enableflags/disableflags.
inline void gmj_inherit_collision_options(mjOption &target, const mjOption &world) {
 constexpr int mask = mjDSBL_NATIVECCD | mjDSBL_MULTICCD;
 target.disableflags = (target.disableflags & ~mask) | (world.disableflags & mask);
 target.ccd_iterations = world.ccd_iterations;
 target.ccd_tolerance = world.ccd_tolerance;
 target.sdf_iterations = world.sdf_iterations;
 target.sdf_initpoints = world.sdf_initpoints;
}

// MuJoCo 3.16's mesh cache does not include octree_maxdepth in its key.
// Author compilation happens in an isolated process; disable that cache for
// the entire candidate whenever native-only mesh settings are present.
struct GmjMeshCacheScope {
 size_t previous = 0;
 bool active;
 explicit GmjMeshCacheScope(bool enabled) : active(enabled) {
  if (active) { previous = mj_getCacheCapacity(mj_getCache()); mj_setCacheCapacity(mj_getCache(), 0); }
 }
 ~GmjMeshCacheScope() { if (active) mj_setCacheCapacity(mj_getCache(), previous); }
};

inline String gmj_apply_mesh_options(mjSpec *spec, const Dictionary &options) {
 for (auto key : options.keys()) {
  if (key.get_type() != Variant::STRING || options[key].get_type() != Variant::DICTIONARY)
   return "Invalid mesh options";
  String label = key; Dictionary fields = options[key];
  Variant value = fields.get("octree_maxdepth", Variant());
  if (fields.size() != 1 || (value.get_type() != Variant::INT && value.get_type() != Variant::FLOAT))
   return "Mesh options require octree_maxdepth";
  double depth = value;
  if (!std::isfinite(depth) || depth != std::floor(depth) || depth < 3 || depth > 8)
   return "SDF depth must be an integer in 3..8";
  auto *mesh = mjs_findElement(spec, mjOBJ_MESH, label.utf8().get_data());
  if (!mesh) return "Unknown mesh option target: " + label;
  mjs_asMesh(mesh)->octree_maxdepth = int(depth);
 }
 return {};
}
}
