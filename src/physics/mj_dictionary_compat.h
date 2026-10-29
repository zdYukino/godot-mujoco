#pragma once
#include <godot_cpp/variant/dictionary.hpp>
namespace godot {
// The pinned godot-cpp generated Dictionary::operator=(Dictionary&&) overwrites
// opaque without destroying its previous value. Do not patch the shared SDK.
// Binding the value to const& forces the destructor-aware copy assignment.
// Keeping the source alive for the complete assignment also preserves sharing.
inline void replace_dictionary(Dictionary &target,const Dictionary &value) {
 if(&target!=&value)target=value;
}
}
