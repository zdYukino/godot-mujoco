#include <godot_cpp/godot.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <cstdio>
using namespace godot;
class ColdImportProbe : public RefCounted {
 GDCLASS(ColdImportProbe, RefCounted)
protected:
 static void _bind_methods() { ClassDB::bind_method(D_METHOD("answer"), &ColdImportProbe::answer); }
public:
 int answer() const { return 42; }
};
void initialize_probe(ModuleInitializationLevel level) {
 if(level != MODULE_INITIALIZATION_LEVEL_SCENE)return;
#ifndef NO_PROBE_CLASS
 ClassDB::register_class<ColdImportProbe>();
#endif
 std::fprintf(stderr,"PROBE_INITIALIZED_SCENE\n");
}
void terminate_probe(ModuleInitializationLevel level) {
 if(level == MODULE_INITIALIZATION_LEVEL_SCENE)std::fprintf(stderr,"PROBE_TERMINATED_SCENE\n");
}
extern "C" GDExtensionBool GDE_EXPORT cold_probe_init(GDExtensionInterfaceGetProcAddress get_proc_address,GDExtensionClassLibraryPtr library,GDExtensionInitialization *initialization) {
 GDExtensionBinding::InitObject init(get_proc_address,library,initialization);
 init.register_initializer(initialize_probe);init.register_terminator(terminate_probe);
 init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
 return init.init();
}
