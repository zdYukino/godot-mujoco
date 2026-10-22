#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <mujoco/mujoco.h>
namespace godot {
// Owns a separate preview; never steps or changes the editor PhysicsServer.
class MjEditorDocument : public RefCounted {
 GDCLASS(MjEditorDocument, RefCounted)
 mjSpec *spec=nullptr;
 mjModel *model=nullptr;
 mjData *data=nullptr;
 String error, source;
 int64_t revision=0;
 bool paused=true;
 double accumulator=0;
 bool commit(mjSpec *candidate, const Dictionary &state=Dictionary(), bool migrate=true);
 String xml() const;
protected:
 static void _bind_methods();
public:
 MjEditorDocument();
 ~MjEditorDocument();
 bool import_file(const String &path);
 bool import_g1(const String &path, bool free_base=false, bool relaxed=false);
 mjSpec *copy_spec() const { return mj_copySpec(spec); }
 const mjModel *native_model() const { return model; }
 const mjData *native_data() const { return data; }
 bool restore(const Dictionary &snapshot);
 Dictionary snapshot() const;
 Dictionary asset_manifest() const;
 Dictionary portable_snapshot(const Dictionary &mapping) const;
 bool restore_at(const Dictionary &snapshot, const String &directory);
 bool edit(const Dictionary &command);
 bool restore_spec(const mjSpec *value) { return commit(mj_copySpec(value),Dictionary(),false); }
 String control_signature() const;
 Dictionary preset_candidate(const Dictionary &preset) const;
 Dictionary inspect() const;
 Array geometry() const;
 void set_paused(bool value);
 bool is_paused() const { return paused; }
 void advance(double seconds);
 String get_error() const { return error; }
};
}
