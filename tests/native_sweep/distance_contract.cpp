// Verify the public MuJoCo API limitation motivating analytic sweep distances.
// Compile/link against exactly MuJoCo 3.16.0; no internal engine headers.
#include <mujoco/mujoco.h>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <initializer_list>
int main() {
 assert(mj_version()==3016000);
 mjSpec *spec=mj_makeSpec();
 for(int i=0;i<2;++i) { auto *g=mjs_addGeom(mjs_findBody(spec,"world"),nullptr); g->type=mjGEOM_SPHERE; g->size[0]=1; }
 mjModel *model=mj_compile(spec,nullptr); assert(model);
 mjData *data=mj_makeData(model); assert(data);
 int checks=0,degenerate=0;
 for(int first:{mjGEOM_SPHERE,mjGEOM_CYLINDER,mjGEOM_BOX}) {
   for(int second:{mjGEOM_SPHERE,mjGEOM_CYLINDER,mjGEOM_BOX}) {
     if(first>second) continue;
     model->geom_type[0]=first; model->geom_type[1]=second;
     for(int i=0;i<6;++i) model->geom_size[i]=1;
     for(int i=0;i<2;++i) { model->geom_rbound[i]=2; mju_zero3(data->geom_xpos+3*i); mju_eye(data->geom_xmat+9*i,3); }
     mjtNum witness[6];
     double distance=mj_geomDistance(model,data,0,1,100,witness);
     if(first!=mjGEOM_SPHERE) {
       assert(distance==0); for(double coordinate:witness) assert(coordinate==0);
       ++degenerate;
     } else assert(std::abs(distance+2)<1e-12);
     ++checks;
     printf("DISTANCE_CONTRACT concentric types=%d,%d distance=%.17g\n",first,second,distance);
     data->geom_xpos[3]=5;
     distance=mj_geomDistance(model,data,0,1,100,witness);
     assert(std::abs(distance-3)<1e-6); ++checks;
   }
 }
 assert(degenerate==3);
 mj_deleteData(data); mj_deleteModel(model); mj_deleteSpec(spec);
 printf("DISTANCE_CONTRACT PASS %d checks; %d zero-witness penetration cases\n",checks,degenerate);
}
