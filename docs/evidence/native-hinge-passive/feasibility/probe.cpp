#include <mujoco/mujoco.h>
#include <cmath>
#include <cstdio>
#include <iomanip>
#include <sstream>
#include <string>
#include <algorithm>

std::string body(const char* name, double half) {
 std::ostringstream o; o << std::setprecision(17);
 o << "<body name='" << name << "'><freejoint/><geom type='sphere' size='.2' mass='1' contype='0' conaffinity='0'/>";
 for(int i=0;i<2;++i)o << "<site name='" << name << i << "' pos='0 0 " << (i?half:-half) << "' size='.001'/>";
 o << "</body>";return o.str();
}
void run(bool two, double spacing, bool axial) {
 std::ostringstream o;o << std::setprecision(17);
 o << "<mujoco><option timestep='.001' gravity='0 0 0' integrator='implicitfast' iterations='100' tolerance='1e-12'/><worldbody>";
 o << body("a",spacing*.5);
 if(two)o << body("b",spacing*.5);else for(int i=0;i<2;++i)o << "<site name='b" << i << "' pos='0 0 " << (i?spacing*.5:-spacing*.5) << "' size='.001'/>";
 o << "</worldbody><equality>";
 for(int i=0;i<2;++i)o << "<connect site1='a" << i << "' site2='b" << i << "' solref='.02 1'/>";
 o << "</equality></mujoco>";
 char error[2048]={};mjSpec* s=mj_parseXMLString(o.str().c_str(),nullptr,error,sizeof(error));
 if(!s){fprintf(stderr,"parse: %s\n",error);exit(2);}mjModel*m=mj_compile(s,nullptr);
 if(!m){fprintf(stderr,"compile: %s\n",mjs_getError(s));exit(3);}mj_deleteSpec(s);mjData*d=mj_makeData(m);
 int a=mj_name2id(m,mjOBJ_BODY,"a"),b=two?mj_name2id(m,mjOBJ_BODY,"b"):0;
 int ids[2][2];for(int i=0;i<2;++i){ids[0][i]=mj_name2id(m,mjOBJ_SITE,(std::string("a")+std::to_string(i)).c_str());ids[1][i]=mj_name2id(m,mjOBJ_SITE,(std::string("b")+std::to_string(i)).c_str());}
 double max_error=0,final_error=0;
 for(int step=0;step<1000;++step){
  mju_zero(d->xfrc_applied,m->nbody*6);d->xfrc_applied[6*a+3+(axial?2:0)]=.01;
  if(two)d->xfrc_applied[6*b+3+(axial?2:0)]=-.01;
  mj_step(m,d);mj_forward(m,d);
  final_error=0;for(int i=0;i<2;++i){mjtNum delta[3];mju_sub3(delta,d->site_xpos+3*ids[0][i],d->site_xpos+3*ids[1][i]);final_error=std::max(final_error,mju_norm3(delta));}
  max_error=std::max(max_error,final_error);
 }
 mjtNum va[6],vb[6]={},omega[3],relative[4],conjugate[4];mj_objectVelocity(m,d,mjOBJ_BODY,a,va,0);if(two)mj_objectVelocity(m,d,mjOBJ_BODY,b,vb,0);mju_sub3(omega,va,vb);
 mju_negQuat(conjugate,d->xquat+4*b);mju_mulQuat(relative,conjugate,d->xquat+4*a);
 double angle=2*std::acos(std::min(1.,std::abs(relative[0])));
 mjtNum za[3]={d->xmat[9*a+2],d->xmat[9*a+5],d->xmat[9*a+8]},zb[3]={d->xmat[9*b+2],d->xmat[9*b+5],d->xmat[9*b+8]};
 double tilt=std::acos(std::clamp(mju_dot3(za,zb),-1.,1.));
 int warnings=0;for(int i=0;i<mjNWARNING;++i)warnings+=d->warning[i].number;
 printf("{\"pair\":\"%s\",\"spacing\":%.17g,\"torque_axis\":\"%s\",\"duration\":%.17g,\"per_body_torque\":0.01,\"relative_omega\":[%.17g,%.17g,%.17g],\"relative_angle\":%.17g,\"hinge_axis_misalignment\":%.17g,\"anchor_error_max\":%.17g,\"anchor_error_final\":%.17g,\"warnings\":%d,\"neq\":%lld,\"nefc\":%lld}\n",two?"two_free_bodies":"body_to_world",spacing,axial?"z_axial":"x_transverse",d->time,omega[0],omega[1],omega[2],angle,tilt,max_error,final_error,warnings,(long long)m->neq,(long long)d->nefc);
 if(warnings||!std::isfinite(angle)||!std::isfinite(max_error))exit(4);
 mj_deleteData(d);mj_deleteModel(m);
}
int main(){printf("MUJOCO_VERSION %s\n",mj_versionString());for(bool two:{false,true})for(double spacing:{.1,1.})for(bool axial:{true,false})run(two,spacing,axial);}
