#include "../../src/physics/mj_convex_sweep.h"
#include <cstdio>
#include <random>
using gmj_sweep::Vec;
Vec cross(Vec a,Vec b){return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};}
struct Box{Vec center,axis[3],half;};
double radius(const Box&b,Vec n){return std::abs(b.axis[0].dot(n))*b.half.x+std::abs(b.axis[1].dot(n))*b.half.y+std::abs(b.axis[2].dot(n))*b.half.z;}
Vec support(const Box&b,Vec n){return b.center+b.axis[0]*(b.axis[0].dot(n)>=0?b.half.x:-b.half.x)+b.axis[1]*(b.axis[1].dot(n)>=0?b.half.y:-b.half.y)+b.axis[2]*(b.axis[2].dot(n)>=0?b.half.z:-b.half.z);}
std::vector<Vec> axes(const Box&a,const Box&b){std::vector<Vec> result;for(auto n:a.axis)result.push_back(n);for(auto n:b.axis)result.push_back(n);for(auto p:a.axis)for(auto q:b.axis){auto n=cross(p,q);double l=n.length();if(l>1e-12)result.push_back(n*(1/l));}return result;}
struct Oracle{bool hit=true,initial=true;double lo=0,hi=1;Vec normal{};};
Oracle oracle(const Box&a,const Box&b,Vec motion){Oracle r;
 for(auto n:axes(a,b)){double extent=radius(a,n)+radius(b,n),s=(a.center-b.center).dot(n),v=motion.dot(n);
  if(std::abs(s)>=extent)r.initial=false;
  if(v==0){if(std::abs(s)>extent)r.hit=false;continue;}
  double lo=(-extent-s)/v,hi=(extent-s)/v;if(lo>hi)std::swap(lo,hi);
  if(lo>r.lo){r.lo=lo;r.normal=n*(v<0?1:-1);}r.hi=std::min(r.hi,hi);
 }r.hit=r.hit&&r.lo<=r.hi&&r.hi>=0&&r.lo<=1;return r;}
Box box(Vec center,Vec half,double yaw,double pitch){double c=std::cos(yaw),s=std::sin(yaw),p=std::cos(pitch),q=std::sin(pitch);
 return {center,{{c,s,0},{-s*p,c*p,q},{s*q,-c*q,p}},half};}
int main(){std::mt19937 random(20261026);std::uniform_real_distribution<double> u(0,1);int hit=0,clear=0;
 for(int i=0;i<500;++i){
  Box a=box({-3,2*u(random)-1,2*u(random)-1},{.08+u(random)*.4,.08+u(random)*.5,.08+u(random)*.6},u(random)*3,u(random)*3);
  Box b=box({0,0,0},{.02+u(random)*.4,.1+u(random)*.7,.1+u(random)*.7},u(random)*3,u(random)*3);
  Vec motion{4+u(random)*4,.2*(u(random)-.5),.2*(u(random)-.5)};auto expected=oracle(a,b,motion);
  auto at=[&](double t){Box q=a;q.center=q.center+motion*t;auto p=[&](){auto o=oracle(q,b,{});bool inside=o.initial&&o.hit;return gmj_convex::Penetration{true,inside,support(b,o.normal),o.normal};};
   return gmj_convex::distance([&](Vec n){return support(q,n);},[&](Vec n){return support(b,n);},q.center-b.center,p);};
  auto actual=gmj_convex::cast(at,motion);
  if(!actual.valid||actual.hit!=expected.hit||(actual.hit&&(actual.safe>expected.lo+1e-9||actual.unsafe<expected.lo-1e-9||actual.unsafe-actual.safe>1e-6))){
   std::fprintf(stderr,"SAT_FAIL %d valid=%d hit=%d expected=%d lo=%.17g oracle=%.17g hi=%.17g oracle_exit=%.17g\n",i,actual.valid,actual.hit,expected.hit,actual.safe,expected.lo,actual.unsafe,expected.hi);
   auto probe=a;probe.center=probe.center+motion*double(std::nextafter(float(expected.lo),1.f));auto x=oracle(probe,b,{});
   std::fprintf(stderr,"SAT_UPPER probe hit=%d inside=%d\n",x.hit,x.initial);return 1;
  }
  if(actual.hit)++hit;else ++clear;
 }
 std::printf("CONVEX_ROTATED_SAT_PASS hit=%d clear=%d total=%d\n",hit,clear,hit+clear);
}
