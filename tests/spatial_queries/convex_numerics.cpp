#include "../../src/physics/mj_convex_sweep.h"
#include <cstdio>
#include <cstdlib>
using gmj_sweep::Vec;
int main(){
 int checks=0;
 auto run=[&](double start,double motion,double half,double target_half){
  auto at=[&](double t){
   Vec c{start+motion*t,0,0};
   auto sa=[&](Vec n){return c+Vec{n.x>=0?half:-half,n.y>=0?half:-half,n.z>=0?half:-half};};
   auto sb=[&](Vec n){return Vec{n.x>=0?target_half:-target_half,n.y>=0?target_half:-target_half,n.z>=0?target_half:-target_half};};
   auto penetrating=[&](){bool inside=std::abs(c.x)<half+target_half;return gmj_convex::Penetration{true,inside,{c.x<0?-target_half:target_half,0,0},{c.x<0?-1.:1.,0,0}};};
   return gmj_convex::distance(sa,sb,c,penetrating);
  };
  return gmj_convex::cast(at,{motion,0,0});
 };
 for(int i=0;i<300;++i){
  double start=-3-i*.03125,motion=5+i*.125,half=.25,target_half=.125;
  auto result=run(start,motion,half,target_half);double oracle=(-start-half-target_half)/motion;
  if(!result.valid||!result.hit||result.safe>oracle+1e-10||result.unsafe<oracle-1e-10||result.unsafe-result.safe>1e-7){std::fprintf(stderr,"FAIL i=%d valid=%d hit=%d lo=%.17g oracle=%.17g hi=%.17g\n",i,result.valid,result.hit,result.safe,oracle,result.unsafe);return 1;}++checks;
 }
 auto thin=run(-100,1000,.1,1e-6);
 if(!thin.valid||!thin.hit||thin.unsafe-thin.safe>1e-7)return 2;++checks;
 if(run(-3,-10,.25,.125).hit)return 3;++checks;
 if(run(-3,0,.25,.125).hit)return 4;++checks;
 if(!run(0,10,.25,.125).initial_overlap)return 5;++checks;
 std::printf("CONVEX_CONTINUOUS_NUMERICS_PASS %d\n",checks);
}
