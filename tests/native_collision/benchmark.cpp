#include <mujoco/mujoco.h>
#include <chrono>
#include <vector>
#include <algorithm>
#include <cstdio>
#include <sys/resource.h>
int main(int argc,char**argv){
 if(argc!=2||mj_version()!=3016000)return 2;
 auto start=std::chrono::steady_clock::now();char error[2048]{};mjModel*m=mj_loadXML(argv[1],nullptr,error,sizeof(error));
 if(!m){std::fprintf(stderr,"%s\n",error);return 1;}
 auto compiled=std::chrono::steady_clock::now();mjData*d=mj_makeData(m);
 int through=mj_name2id(m,mjOBJ_BODY,"through"),blocked=mj_name2id(m,mjOBJ_BODY,"blocked");
 for(int body:{through,blocked})d->qvel[m->jnt_dofadr[m->body_jntadr[body]]+1]=-2;
 std::vector<double>costs;double maxforce=0;bool normal=false;
 for(int i=0;i<750;++i){auto a=std::chrono::steady_clock::now();mj_step(m,d);auto b=std::chrono::steady_clock::now();costs.push_back(std::chrono::duration<double,std::micro>(b-a).count());
  for(int c=0;c<d->ncon;++c){auto&contact=d->contact[c];int b1=m->geom_bodyid[contact.geom[0]],b2=m->geom_bodyid[contact.geom[1]];
   if((b1==blocked&&b2==0)||(b2==blocked&&b1==0)){mjtNum f[6]{};mj_contactForce(m,d,c,f);maxforce=std::max(maxforce,double(f[0]));normal|=std::abs(contact.frame[1])>.8;}}
 }
 double sum=0;for(double c:costs)sum+=c;std::sort(costs.begin(),costs.end());rusage u{};getrusage(RUSAGE_SELF,&u);
 std::printf("{\"compile_ms\":%.6f,\"step_mean_us\":%.6f,\"step_p50_us\":%.6f,\"step_p95_us\":%.6f,\"peak_rss_kib\":%ld,\"model_buffer_bytes\":%zu,\"data_buffer_bytes\":%zu,\"octree_cells\":%ld,\"target_force_max\":%.6f,\"target_normal_ok\":%s,\"through_y\":%.6f,\"blocked_y\":%.6f}\n",std::chrono::duration<double,std::milli>(compiled-start).count(),sum/750,costs[375],costs[712],u.ru_maxrss,m->nbuffer,d->nbuffer,(long)m->noct,maxforce,normal?"true":"false",d->xpos[3*through+1],d->xpos[3*blocked+1]);
 bool ok=maxforce>0&&normal&&d->xpos[3*blocked+1]>3.2;mj_deleteData(d);mj_deleteModel(m);return ok?0:3;
}
