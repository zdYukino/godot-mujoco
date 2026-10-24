#include "../../src/physics/mj_sweep.h"
#include <cassert>
#include <cstdio>
using namespace gmj_sweep;
int main() {
 int checks=0;auto check=[&](bool x){++checks;assert(x);};
 for(auto kind:{Kind::sphere,Kind::box,Kind::cylinder,Kind::capsule}) {
  Primitive g{kind,{1,2,1}};
  for(double length:{0.0,.1,1.0,10.0}) for(double speed:{10.0,1000.0,1000000.0}) {
   auto h=capsule(g,{-5,0,0},{speed,0,0},.5,{0,0,length});
   check(h.valid && h.hit && std::abs(h.unsafe-3.5/speed)<1e-12);
   check(std::abs(h.point.x+1)<1e-10 && std::abs(h.normal.x+1)<1e-10);
   check(capsule(g,{0,0,0},{speed,0,0},.5,{0,0,length}).initial_overlap);
   check(!capsule(g,{-5,0,0},{0,0,0},.5,{0,0,length}).hit);
   check(!capsule(g,{-5,0,0},{-speed,0,0},.5,{0,0,length}).hit);
  }
 }
 // Diagonal capsule translating parallel to its axis toward a sphere. Endcap
 // reaches the expanded target sphere at exactly distance 5 - length - 1.5.
 for(int i=0;i<100;++i) {
  double angle=i*.061, u=std::cos(angle),v=std::sin(angle);Vec n{u,v,0};
  auto h=capsule({Kind::sphere,{1,0,0}},n*-5,n*10,.5,n*1.25);
  check(h.valid && h.hit && std::abs(h.unsafe-.225)<1e-12);
  check((h.normal-n*-1).length()<1e-10);
 }
 // Capsule axes parallel: analytic segment separation, including side grazing.
 Primitive cap{Kind::capsule,{.5,2,0}};
 auto graze=capsule(cap,{-4,1,0},{8,0,0},.5,{0,0,1});
 check(graze.valid && graze.hit && std::abs(graze.unsafe-.5)<1e-8);
 check(!capsule(cap,{-4,1.0001,0},{8,0,0},.5,{0,0,1}).hit);
 // Crossing skew segments at first hit, and a thin target with a short interval.
 auto crossed=capsule(cap,{-4,0,0},{8,0,0},.5,{0,1,0});
 check(crossed.valid && crossed.hit && std::abs(crossed.unsafe-.375)<1e-12);
 Primitive thin{Kind::box,{1e-6,2,2}};
 auto fast=capsule(thin,{-5,0,0},{1e6,0,0},1e-6,{0,0,.5});
 check(fast.valid && fast.hit && std::abs(fast.unsafe-(5-2e-6)/1e6)<1e-15);
 // Line parallel to a cylinder axis projects to the side, not its center.
 auto pair=segment_closest({Kind::cylinder,{1,2,0}},{3,0,0},{0,0,4});
 check(std::abs(pair.delta().length()-2)<1e-12);
 std::printf("CAPSULE_NUMERICS PASS %d checks\n",checks);
}
