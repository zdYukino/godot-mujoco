#include <mujoco/mujoco.h>
#include <algorithm>
#include <cmath>
#include <fstream>
#include <iostream>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>
static void check(bool ok,const std::string& msg){if(!ok)throw std::runtime_error(msg);}
struct Joint{std::string name;double lo,hi,effort,velocity;int j,q,v,a;};
int main(int argc,char**argv){try{
 check(std::string(mj_versionString())=="3.16.0","requires MuJoCo 3.16.0");
 check(argc>=3,"usage: native_test model.xml inventory.tsv OR --canonical model.urdf out.xml");
 bool canonical=std::string(argv[1])=="--canonical";check(!canonical||argc==4,"canonical arguments");char err[2048]={};mjModel*m=mj_loadXML(argv[canonical?2:1],nullptr,err,sizeof(err));check(m,err);
 if(canonical){check(m->nq==29&&m->nv==29&&m->njnt==29&&m->nu==0&&m->nbody==30&&m->ngeom==69&&m->nmesh==34,"source dimensions");check(mj_saveLastXML(argv[3],m,err,sizeof(err)),err);std::cout<<"SOURCE nq=29 nv=29 njnt=29 nu=0 nbody=30 ngeom=69 nmesh=34\n";mj_deleteModel(m);return 0;}
 check(m->nq==29&&m->nv==29&&m->njnt==29&&m->nu==29,"fixture dimensions");check(m->opt.timestep==.001&&m->opt.integrator==mjINT_IMPLICITFAST,"fixture options");check((m->opt.disableflags & mjDSBL_CONTACT)!=0,"contacts disabled");for(double g:m->opt.gravity)check(g==0,"gravity zero");
 std::ifstream in(argv[2]);std::vector<Joint> js;Joint x;std::set<int> aids,jids,qids,vids;
 while(in>>x.name>>x.lo>>x.hi>>x.effort>>x.velocity){x.j=mj_name2id(m,mjOBJ_JOINT,x.name.c_str());x.a=mj_name2id(m,mjOBJ_ACTUATOR,(x.name+"_position").c_str());check(x.j>=0&&x.a>=0,"names "+x.name);x.q=m->jnt_qposadr[x.j];x.v=m->jnt_dofadr[x.j];check(jids.insert(x.j).second&&aids.insert(x.a).second&&qids.insert(x.q).second&&vids.insert(x.v).second,"unique mapping");check(m->jnt_type[x.j]==mjJNT_HINGE&&m->actuator_trnid[2*x.a]==x.j,"joint transmission");check(m->actuator_gear[6*x.a]==1,"unit gear");check(std::abs(m->jnt_range[2*x.j]-x.lo)<1e-12&&std::abs(m->jnt_range[2*x.j+1]-x.hi)<1e-12,"exact ranges");check(m->jnt_actfrclimited[x.j]&&m->jnt_actfrcrange[2*x.j]==-x.effort&&m->jnt_actfrcrange[2*x.j+1]==x.effort,"URDF effort mapping");check(m->actuator_forcelimited[x.a]&&m->actuator_forcerange[2*x.a]==-x.effort&&m->actuator_forcerange[2*x.a+1]==x.effort,"force limits");check(m->actuator_ctrllimited[x.a]&&m->actuator_ctrlrange[2*x.a]==x.lo&&m->actuator_ctrlrange[2*x.a+1]==x.hi,"control limits");js.push_back(x);}
 check(js.size()==29,"inventory count");mjData*d=mj_makeData(m);check(d,"make data");std::vector<double>base(29),target(29);for(auto&j:js)base[j.q]=std::clamp(0.0,j.lo+.03,j.hi-.03);
 double max_final=0,max_other=0,max_transient=0;long steps=0;int cases=0;
 auto run=[&](int selected,int sign){mj_resetData(m,d);target=base;for(size_t k=0;k<js.size();++k){auto&j=js[k];d->qpos[j.q]=base[j.q];if(selected<0||selected==(int)k)target[j.q]+=.02*(selected<0?(k%2?1:-1):sign);d->ctrl[j.a]=target[j.q];}mj_forward(m,d);
 for(int s=0;s<4000;s++){mj_step(m,d);++steps;for(auto&j:js){check(std::isfinite(d->qpos[j.q])&&std::isfinite(d->qvel[j.v])&&std::isfinite(d->actuator_force[j.a]),"finite state");check(d->qpos[j.q]>=j.lo-.002&&d->qpos[j.q]<=j.hi+.002,"joint range");check(std::abs(d->actuator_force[j.a])<=j.effort+1e-9,"force bound");if(selected>=0&&j.q!=js[selected].q)max_transient=std::max(max_transient,std::abs(d->qpos[j.q]-base[j.q]));}for(int w=0;w<mjNWARNING;w++)check(d->warning[w].number==0,"MuJoCo warning");}
 for(auto&j:js){double e=std::abs(d->qpos[j.q]-target[j.q]);max_final=std::max(max_final,e);if(selected>=0&&j.q!=js[selected].q)max_other=std::max(max_other,e);check(e<=.002,"final target error "+j.name);}++cases;};
 for(int k=0;k<29;k++){run(k,-1);run(k,1);}run(-1,1);check(max_transient<=.005,"non-target transient");
 // Deliberately large velocities force each synthetic damper to both force caps.
 for(auto&j:js)for(int sign:{-1,1}){mj_resetData(m,d);for(auto&k:js){d->qpos[k.q]=base[k.q];d->ctrl[k.a]=base[k.q];}d->qvel[j.v]=-sign*1e6;mj_forward(m,d);check(std::abs(d->actuator_force[j.a]-sign*j.effort)<1e-9,"bidirectional saturation "+j.name);}
 std::cout.precision(12);std::cout<<"PASS cases="<<cases<<" steps="<<steps<<" max_final_rad="<<max_final<<" max_non_target_final_rad="<<max_other<<" max_non_target_transient_rad="<<max_transient<<" saturation_checks=58\n";mj_deleteData(d);mj_deleteModel(m);return 0;
 }catch(const std::exception&e){std::cerr<<"FAIL "<<e.what()<<'\n';return 1;}}
