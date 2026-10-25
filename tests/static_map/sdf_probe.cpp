// Isolated MuJoCo capability probe, NOT a claim of Godot backend support.
#include <mujoco/mujoco.h>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <ctime>
#include <initializer_list>
#include <sys/resource.h>
int main(int argc, char** argv) {
  if (argc < 2) return 2;
  if (argc > 3) mj_loadPluginLibrary(argv[3]);
  char error[2048]{};
  auto cpu_begin = std::clock();
  auto begin = std::chrono::steady_clock::now();
  mjModel* m = mj_loadXML(argv[1], nullptr, error, sizeof(error));
  auto compiled = std::chrono::steady_clock::now();
  auto cpu_compiled = std::clock();
  if (!m) { std::fprintf(stderr,"SDF_PROBE_REJECT %s\n",error); return 1; }
  rusage compile_usage{}; getrusage(RUSAGE_SELF,&compile_usage);
  mjData* d = mj_makeData(m);
  // Named lightweight test bodies, when present; official examples keep their own initial state.
  for (const char* name : {"through", "blocked"}) {
    int body = mj_name2id(m,mjOBJ_BODY,name);
    if (body >= 0) d->qvel[m->jnt_dofadr[m->body_jntadr[body]]+1] = -2;
  }
  int steps = argc > 2 ? std::atoi(argv[2]) : 750;
  int peak_contacts = 0;
  for (int i=0;i<steps;i++) { mj_step(m,d); if(d->ncon>peak_contacts) peak_contacts=d->ncon; }
  auto finished = std::chrono::steady_clock::now();
  auto cpu_finished = std::clock();
  rusage usage{}; getrusage(RUSAGE_SELF,&usage);
  std::printf("SDF_PROBE version=%s compile_ms=%.3f step_ms=%.3f compile_cpu_ms=%.3f step_cpu_ms=%.3f steps=%d compile_peak_rss_kib=%ld peak_rss_kib=%ld octree_cells=%ld plugins=%ld peak_contacts=%d\n",
    mj_versionString(),std::chrono::duration<double,std::milli>(compiled-begin).count(),std::chrono::duration<double,std::milli>(finished-compiled).count(),1000.0*(cpu_compiled-cpu_begin)/CLOCKS_PER_SEC,1000.0*(cpu_finished-cpu_compiled)/CLOCKS_PER_SEC,steps,compile_usage.ru_maxrss,usage.ru_maxrss,(long)m->noct,(long)m->nplugin,peak_contacts);
  for (int g=0;g<m->ngeom;g++) if(m->geom_type[g]==mjGEOM_SDF)
    std::printf("SDF_GEOM name=%s plugin=%d mesh=%d\n",mj_id2name(m,mjOBJ_GEOM,g),m->geom_plugin[g],m->geom_dataid[g]);
  bool ok = true;
  for(int i=0;i<m->nq;i++) if(!std::isfinite(d->qpos[i])) ok=false;
  for(int i=0;i<m->nv;i++) if(!std::isfinite(d->qvel[i])) ok=false;
  for (const char* name : {"through", "blocked"}) {
    int b=mj_name2id(m,mjOBJ_BODY,name);
    if(b>=0) {
      std::printf("BODY %s pos=%.6f %.6f %.6f\n",name,d->xpos[3*b],d->xpos[3*b+1],d->xpos[3*b+2]);
      if (name[0]=='t' && d->xpos[3*b+1] >= 2) ok=false;
      if (name[0]=='b' && d->xpos[3*b+1] <= 3.25) ok=false;
    }
  }
  mj_deleteData(d);mj_deleteModel(m);
  return ok?0:3;
}
