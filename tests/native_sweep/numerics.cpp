#include "../../src/physics/mj_sweep.h"
#include <cassert>
#include <cstdio>
using namespace gmj_sweep;
int main() {
 int checks=0;
 auto check=[&](bool value){++checks; assert(value);};
 Primitive ball{Kind::sphere,{1,0,0}}, box{Kind::box,{1,1,1}}, cylinder{Kind::cylinder,{1,1,0}};
 for(auto g:{ball,box,cylinder}) {
   for(double speed:{10.0,1000.0,1000000.0}) {
     auto hit=sphere(g,{-5,0,0},{speed,0,0},1);
     check(hit.valid && hit.hit && hit.safe<=3/speed+1e-15 && hit.unsafe>=3/speed-1e-15);
     check(hit.point.x==-1 && hit.normal.x==-1);
   }
   check(sphere(g,{0,0,0},{10,0,0},1).initial_overlap);
   check(!sphere(g,{-5,0,0},{0,0,0},1).hit);
   check(!sphere(g,{-5,0,0},{-10,0,0},1).hit);
 }
 auto tangent=sphere(ball,{-5,2,0},{10,0,0},1);
 check(tangent.valid && tangent.hit && std::abs(tangent.unsafe-.5)<1e-7);
 auto miss=sphere(ball,{-5,2.00001,0},{10,0,0},1);
 check(miss.valid && !miss.hit);
 check(!sphere(ball,{-5,2+1e-14,0},{10,0,0},1).valid);
 auto touch=sphere(ball,{-2,0,0},{10,0,0},1);
 check(touch.hit && touch.safe==0 && touch.unsafe==0);
 check(!sphere(ball,{-2,0,0},{-10,0,0},1).hit);
 // A rotated box reduces to these local coordinates. Corner entry is rounded,
 // not the falsely early slab hit from inflating every box extent by radius.
 auto corner=sphere(box,{-5,1.6,0},{10,0,0},1);
 check(corner.valid && corner.hit && std::abs(corner.unsafe-.32)<1e-12);
 auto edge=sphere(cylinder,{-5,0,1.6},{10,0,0},1);
 check(edge.valid && edge.hit && std::abs(edge.unsafe-.32)<1e-12);
 auto p=plane(4,-10); check(p.hit && p.safe<=.4 && p.unsafe>=.4);
 check(!plane(-1,-10).hit && plane(-1,-10).initial_overlap);
 // Vary wall thickness and speed independently: no temporal sample grid.
 for(double thickness:{1.0,1e-3,1e-6}) for(double speed:{10.0,1e3,1e6,1e9}) {
   auto h=sphere({Kind::box,{thickness,100,100}},{-5,0,0},{speed,0,0},.01);
   double exact=(5-thickness-.01)/speed;
   check(h.valid && h.hit && std::abs(h.unsafe-exact)<1e-14);
 }
 for(int i=0;i<1000;++i) {
   double y=2.5*i/999.0, radius=.3, sum=1+radius;
   auto hit=sphere(ball,{-5,y,0},{10,0,0},radius);
   if(y>sum) check(hit.valid && !hit.hit);
   else { double exact=(5-std::sqrt(sum*sum-y*y))/10; check(hit.valid && hit.hit && std::abs(hit.unsafe-exact)<1e-12); }
 }
 printf("SWEEP_NUMERICS PASS %d checks\n",checks);
}
