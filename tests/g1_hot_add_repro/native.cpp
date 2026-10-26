// Standalone MuJoCo: no Godot headers, engine, rendering or UI.
#include <mujoco/mujoco.h>
#include "mj_state_transfer.h"
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>
using Spec=std::unique_ptr<mjSpec,decltype(&mj_deleteSpec)>;
using Model=std::unique_ptr<mjModel,decltype(&mj_deleteModel)>;
using Data=std::unique_ptr<mjData,decltype(&mj_deleteData)>;
static const auto start=std::chrono::steady_clock::now();
void mark(const std::string&s){auto ms=std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-start).count();std::fprintf(stderr,"NATIVE_REPRO_STAGE ms=%lld stage=%s\n",(long long)ms,s.c_str());std::fflush(stderr);}
void require(bool ok,const std::string&s){if(!ok)throw std::runtime_error(s);}
Spec donor(const std::string&path,const std::string&name){
 char error[2048]{};mark(name+".parse_begin");Spec s(mj_parseXML(path.c_str(),nullptr,error,sizeof(error)),mj_deleteSpec);require(bool(s),error);
 mark(name+".compile_begin");Model m(mj_compile(s.get(),nullptr),mj_deleteModel);require(bool(m),mjs_getError(s.get()));mark(name+".compile_end");
 Data d(mj_makeData(m.get()),mj_deleteData);require(bool(d),"makeData");mj_forward(m.get(),d.get());mark(name+".forward_end");return s;
}
Model combine(const std::vector<mjSpec*>&sources,bool serial){
 char error[2048]{};Spec s(mj_parseXMLString("<mujoco><compiler angle='radian'/><worldbody/></mujoco>",nullptr,error,sizeof(error)),mj_deleteSpec);require(bool(s),error);mjs_setDeepCopy(s.get(),1);s->option=sources[0]->option;
 for(size_t i=0;i<sources.size();++i){mark("attach_"+std::to_string(i)+".begin");auto*frame=mjs_addFrame(mjs_findBody(s.get(),"world"),nullptr);
  if(i){frame->pos[0]=i==1?-1.8:1.8;frame->pos[2]=.82;double angle=5.0*std::acos(-1.0)/180;frame->quat[0]=std::cos(angle/2);frame->quat[2]=std::sin(angle/2);}
  const auto prefix="object_"+std::to_string(i)+"_";
  auto*attached=mjs_attach(frame->element,mjs_findBody(sources[i],"world")->element,prefix.c_str(),"");require(attached,mjs_getError(s.get()));auto*wrapper=mjs_asBody(attached);require(wrapper&&mjs_bodyToFrame(&wrapper),"flatten");mark("attach_"+std::to_string(i)+".end");
 }
 s->compiler.usethread=!serial;mark("combined_"+std::to_string(sources.size())+".compile_begin");Model m(mj_compile(s.get(),nullptr),mj_deleteModel);require(bool(m),mjs_getError(s.get()));mark("combined_"+std::to_string(sources.size())+".compile_end");return m;
}
int main(int argc,char**argv){try{
 require((argc==3||argc==4)&&(std::string(argv[2])=="cold"||std::string(argv[2])=="hot")&&(argc!=4||std::string(argv[3])=="serial"),"native PROJECT cold|hot [serial] (unknown mode rejected)");std::string base=argv[1];bool hot=std::string(argv[2])=="hot",serial=argc==4&&std::string(argv[3])=="serial";
 require(mj_version()==3016000,"requires MuJoCo 3.16.0");
 std::fprintf(stderr,"NATIVE_REPRO_CONFIG version=%s cpu=%u hot=%d serial_combined=%d\n",mj_versionString(),std::thread::hardware_concurrency(),hot,serial);
 auto floor=donor(base+"/floor/model.xml","floor");auto first=donor(base+"/g1/model.xml","first");
 auto old=combine({floor.get(),first.get()},serial);Data d(mj_makeData(old.get()),mj_deleteData);mj_forward(old.get(),d.get());require(old->nu==0&&old->nv==35&&old->ngeom==70,"single model counts");
 mark("step.begin");if(hot)for(int i=0;i<3000;++i)mj_step(old.get(),d.get());mark("step.end");
 auto second=donor(base+"/g1/model.xml","second");auto next=combine({floor.get(),first.get(),second.get()},serial);
 require(next->nu==0&&next->nv==70&&next->ngeom==139,"pair model counts");Data nd(mj_makeData(next.get()),mj_deleteData);
 mark("transfer.begin");gmj_transfer_state(old.get(),d.get(),next.get(),nd.get());mark("transfer.end");
 require(nd->time==d->time,"time transfer");for(int j=0;j<old->njnt;++j){int k=mj_name2id(next.get(),mjOBJ_JOINT,mj_id2name(old.get(),mjOBJ_JOINT,j));require(k>=0,"joint mapping");int nq=old->jnt_type[j]==mjJNT_FREE?7:1,nv=old->jnt_type[j]==mjJNT_FREE?6:1;for(int a=0;a<nq;++a)require(d->qpos[old->jnt_qposadr[j]+a]==nd->qpos[next->jnt_qposadr[k]+a],"qpos");for(int a=0;a<nv;++a)require(d->qvel[old->jnt_dofadr[j]+a]==nd->qvel[next->jnt_dofadr[k]+a],"qvel");}
 mark("forward.begin");mj_forward(next.get(),nd.get());mark("forward.end");std::fprintf(stderr,"NATIVE_REPRO_RESULT PASS time=%.17g ngeom=%d nv=%d\n",nd->time,next->ngeom,next->nv);return 0;
 }catch(const std::exception&e){std::fprintf(stderr,"NATIVE_REPRO_RESULT FAIL %s\n",e.what());return 1;}}
