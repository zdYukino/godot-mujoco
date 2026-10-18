#pragma once
#include <mujoco/mujoco.h>
#include <mujoco/mjxmacro.h>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
namespace godot {
inline String gmj_option_conflict(const mjOption&a,const mjOption&b){
#define X(type,name,count) if(a.name!=b.name)return #name;
#define XVEC(type,name,count) for(int i=0;i<count;++i)if(a.name[i]!=b.name[i])return #name;
 MJOPTION_FIELDS
#undef X
#undef XVEC
 return {};
}
inline Dictionary gmj_options(const mjOption&o){Dictionary d;
#define X(type,name,count) d[#name]=o.name;
#define XVEC(type,name,count) {Array a;for(int i=0;i<count;++i)a.push_back(o.name[i]);d[#name]=a;}
 MJOPTION_FIELDS
#undef X
#undef XVEC
 return d;
}
}
