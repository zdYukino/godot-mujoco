#include "mj_physics_server.h"
#include <godot_cpp/variant/utility_functions.hpp>
#include <mutex>
namespace godot {
Vector3 godot_to_mj(const Vector3 &v) { return Vector3(v.x,-v.z,v.y); }
Vector3 mj_to_godot(const Vector3 &v) { return Vector3(v.x,v.z,-v.y); }
static Basis coordinate_basis() { return Basis(Vector3(1,0,0), Vector3(0,0,1), Vector3(0,-1,0)); }
Basis godot_to_mj(const Basis &b) { auto c=coordinate_basis(); return c*b*c.transposed(); }
Basis mj_to_godot(const Basis &b) { auto c=coordinate_basis(); return c.transposed()*b*c; }
void mj_unsupported(const char *feature) {
 static std::set<std::string> reported;
 static std::mutex mutex;
 std::lock_guard<std::mutex> lock(mutex);
 if (reported.insert(feature).second) UtilityFunctions::push_warning(String("MuJoCo minimal backend: unsupported ")+feature);
}
}
