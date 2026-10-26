#pragma once
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <thread>
// Opt-in diagnostics scoped to synchronous scene_load_model only. Use stderr
// directly and flush each boundary; do not acquire Godot logging/physics locks.
namespace gmj_load_trace {
inline std::atomic<unsigned long long> sequence{0};
inline thread_local bool enabled=false;
inline thread_local unsigned long long operation=0;
inline thread_local std::chrono::steady_clock::time_point started;
inline void mark(const char *stage,long long a=-1,long long b=-1) {
 if(!enabled)return;
 auto ms=std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-started).count();
 std::fprintf(stderr,"MJ_NATIVE_LOAD_STAGE id=%llu elapsed_ms=%lld stage=%s a=%lld b=%lld thread=%zu\n",operation,static_cast<long long>(ms),stage,a,b,std::hash<std::thread::id>{}(std::this_thread::get_id()));
 std::fflush(stderr);
}
struct Scope {
 bool previous_enabled=enabled;
 unsigned long long previous_operation=operation;
 std::chrono::steady_clock::time_point previous_started=started;
 Scope(){const char *flag=std::getenv("GMJ_TRACE_SCENE_LOAD");enabled=flag&&std::strcmp(flag,"1")==0;if(enabled){operation=++sequence;started=std::chrono::steady_clock::now();mark("load.enter");}}
 ~Scope(){mark("load.exit");enabled=previous_enabled;operation=previous_operation;started=previous_started;}
};
}
