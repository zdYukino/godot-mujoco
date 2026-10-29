#pragma once
#include <mujoco/mujoco.h>
#include <cstdint>
#include <mujoco/mjxmacro.h>
#include <type_traits>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <string>

namespace gmj_display {
constexpr int64_t MiB=1024*1024;
constexpr int64_t model_limit=192*MiB;
constexpr int64_t resident_limit=256*MiB;
constexpr int64_t transient_limit=512*MiB;
constexpr int64_t scene_reserve=16*MiB;
static_assert(resident_limit+model_limit+3*8*MiB<=transient_limit,"bounded single in-flight transport");
// Admission accounting for owned CPU buffers, not a cap on driver/process RSS.
// All inputs are checked before conversion, multiplication or accumulation.
// The output is only valid on success; no sentinel can accidentally pass equality.
template<class T> inline bool bounded(T value, int64_t limit) {
 if constexpr(std::is_signed_v<T>) { if(value<0)return false; }
 return limit>=0 && uint64_t(value)<=uint64_t(limit);
}
inline bool add(int64_t &total,int64_t value,int64_t limit) {
 if(!bounded(total,limit)||!bounded(value,limit)||value>limit-total)return false;
 total+=value;return true;
}
inline bool multiply(int64_t a,int64_t b,int64_t limit,int64_t &out) {
 if(!bounded(a,limit)||!bounded(b,limit)||(a && b>limit/a))return false;
 out=a*b;return true;
}
inline bool resident(const mjModel *m,int64_t data_buffer,int64_t &out) {
 if(!m||!bounded(m->nbuffer,resident_limit)||!bounded(m->narena,resident_limit)||!bounded(data_buffer,resident_limit))return false;
 int64_t total=0;
 for(int64_t n:{int64_t(m->nbuffer),data_buffer,int64_t(m->narena),int64_t(sizeof(mjModel)),int64_t(sizeof(mjData)),scene_reserve})
  if(!add(total,n,resident_limit))return false;
 out=total;return true;
}
inline bool rigid_assets(const mjModel *m) {
 return m && m->nplugin==0 && m->nflex==0 && m->nskin==0 && bounded(m->ngeom,9000) && bounded(m->nmeshvert,600000) && bounded(m->nmeshface,1000000) && bounded(m->ntexdata,64*MiB);
}
// Conservative upper bound for the pinned MuJoCo 3.16 MJDATA_POINTERS layout:
// one <=64-byte alignment allowance per field plus initial alignment. This
// independently checks decoded dimensions, rather than trusting packet metadata.
// Post-allocation actual nbuffer must also match the declared value and this bound.
inline bool data_bound(const mjModel *m,int64_t &out) {
 if(!m)return false;int64_t total=64,part=0,bytes=0;
#define X(type,name,nr,nc) if(!bounded(m->nr,resident_limit)||!multiply(int64_t(m->nr),nc,resident_limit,part)||!multiply(part,sizeof(type),resident_limit,bytes)||!add(total,bytes,resident_limit)||!add(total,64,resident_limit))return false;
#define XNV X
 MJDATA_POINTERS
#undef XNV
#undef X
 out=total;return true;
}
inline bool decoded_admission(const mjModel *m,int64_t data_buffer,int64_t declared) {
 int64_t actual=0,upper=0,upper_resident=0;
 return bounded(declared,resident_limit)&&declared>0&&rigid_assets(m)&&
  resident(m,data_buffer,actual)&&actual==declared&&data_bound(m,upper)&&
  data_buffer<=upper&&resident(m,upper,upper_resident);
}
inline void trace(const char *stage, int64_t bytes=0, int64_t generation=0) {
 if(!std::getenv("GMJ_NATIVE_MEMORY_TRACE")) return;
 std::ifstream f("/proc/self/status");std::string line;int64_t rss=0,hwm=0;
 while(std::getline(f,line)) {
  if(line.rfind("VmRSS:",0)==0)rss=std::strtoll(line.c_str()+6,nullptr,10)*1024;
  if(line.rfind("VmHWM:",0)==0)hwm=std::strtoll(line.c_str()+6,nullptr,10)*1024;
 }
 auto us=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
 std::fprintf(stderr,"GMJ_MEMORY {\"stage\":\"%s\",\"steady_us\":%lld,\"rss\":%lld,\"hwm\":%lld,\"bytes\":%lld,\"generation\":%lld}\n",stage,(long long)us,(long long)rss,(long long)hwm,(long long)bytes,(long long)generation);
}
}
