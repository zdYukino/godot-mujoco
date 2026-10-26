#pragma once
#include "mj_sweep.h"
#include <array>
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <vector>
// Fixed-orientation convex translation. A separating support plane certifies
// every time interval advanced over. No temporal grid or overlap-only search.
namespace gmj_convex {
using Vec=gmj_sweep::Vec;
using Support=std::function<Vec(Vec)>;
struct Penetration {bool valid=false,inside=false;Vec point{},normal{};};
struct Vertex {Vec point,a,b;};
struct Distance {
 bool valid=false,inside=false,boundary=false;
 double lower=0,upper=0;Vec normal{},point{};double uncertainty=0;Vec query_point{};
};
inline bool solve(double a[5][6],int count,double result[5]) {
 double scale=0;for(int i=0;i<count;++i)for(int j=0;j<count;++j)scale=std::max(scale,std::abs(a[i][j]));
 for(int k=0;k<count;++k){int pivot=k;for(int i=k+1;i<count;++i)if(std::abs(a[i][k])>std::abs(a[pivot][k]))pivot=i;
  if(std::abs(a[pivot][k])<=64*std::numeric_limits<double>::epsilon()*scale)return false;
  for(int j=k;j<=count;++j)std::swap(a[k][j],a[pivot][j]);
  const double d=a[k][k];for(int j=k;j<=count;++j)a[k][j]/=d;
  for(int i=0;i<count;++i)if(i!=k){double factor=a[i][k];for(int j=k;j<=count;++j)a[i][j]-=factor*a[k][j];}
 }
 for(int i=0;i<count;++i)result[i]=a[i][count];return true;
}
inline bool project(std::vector<Vertex>&simplex,Vec &point,Vec &wa,Vec &wb) {
 const int count=int(simplex.size());double best=std::numeric_limits<double>::infinity();std::vector<double> selected;
 for(int mask=1;mask<(1<<count);++mask){std::vector<int> ids;for(int i=0;i<count;++i)if(mask&(1<<i))ids.push_back(i);
  const int n=int(ids.size());double weights[5]={1},a[5][6]={},solution[5]={};
  if(n>1){const Vec base=simplex[ids[0]].point;
   for(int i=1;i<n;++i){Vec u=simplex[ids[i]].point-base;for(int j=1;j<n;++j)a[i-1][j-1]=u.dot(simplex[ids[j]].point-base);a[i-1][n-1]=-u.dot(base);}
   if(!solve(a,n-1,solution))continue;
   weights[0]=1;for(int i=1;i<n;++i){weights[i]=solution[i-1];weights[0]-=weights[i];}
  }
  bool feasible=true;double sum=0;for(int i=0;i<n;++i){if(weights[i]<-1e-12)feasible=false;weights[i]=std::max(0.0,weights[i]);sum+=weights[i];}
  if(!feasible||sum==0)continue;Vec p{},pa{},pb{};std::vector<double> all(count,0);
  for(int i=0;i<n;++i){double w=weights[i]/sum;all[ids[i]]=w;p=p+simplex[ids[i]].point*w;pa=pa+simplex[ids[i]].a*w;pb=pb+simplex[ids[i]].b*w;}
  if(p.dot(p)<best){best=p.dot(p);selected=all;point=p;wa=pa;wb=pb;}
 }
 if(selected.empty())return false;std::vector<Vertex> reduced;for(int i=0;i<count;++i)if(selected[i]>0)reduced.push_back(simplex[i]);
 simplex=std::move(reduced);return true;
}
inline Distance distance(const Support&a,const Support&b,Vec initial,const std::function<Penetration()>&penetration) {
 Distance result;Vec direction=initial;if(direction.length()==0)direction={1,0,0};
 auto vertex=[&](Vec n){Vec pa=a(n),pb=b(n*-1);return Vertex{pa-pb,pa,pb};};
 std::vector<Vertex> simplex{vertex(direction*-1)};Vec point{},wa{},wb{},last_normal=direction*(1/direction.length());
 for(int iteration=0;iteration<96;++iteration){
  if(!project(simplex,point,wa,wb))return result;double upper=point.length();
  if(!std::isfinite(upper))return result;
  double scale=std::max({1.0,wa.length(),wb.length()}),error=256*std::numeric_limits<double>::epsilon()*scale;
  if(upper<=error){
   Penetration p=penetration();if(!p.valid)return result;
   result.valid=true;result.inside=p.inside;result.upper=upper;result.uncertainty=error;result.point=p.inside?p.point:wb;result.normal=p.inside?p.normal:upper>0?point*(1/upper):last_normal;
   if(!p.inside){const double plane=result.normal.dot(vertex(result.normal*-1).point);
    // Boundary accepted only with an actual zero separating support plane.
    result.boundary=plane==0;
   }
   return result;
  }
  Vec normal=point*(1/upper);Vertex next=vertex(normal*-1);double raw=normal.dot(next.point);
  const double lower=std::max(0.0,raw-error);
  result={true,false,false,lower,upper,normal,wb,error};result.query_point=wa;last_normal=normal;
  if(upper-lower<=error*4){
   if(result.lower<=0){auto p=penetration();if(p.valid&&p.inside){result.inside=true;result.point=p.point;result.normal=p.normal;}}
   return result;
  }
  bool duplicate=false;for(const auto &v:simplex)if((v.point-next.point).length()<=error)duplicate=true;
  if(duplicate){
   if(result.lower<=0){auto p=penetration();if(p.valid&&p.inside){result.inside=true;result.point=p.point;result.normal=p.normal;}}
   return result;
  }
  if(simplex.size()>=4){auto p=penetration();if(p.valid&&p.inside){result.inside=true;result.point=p.point;result.normal=p.normal;}return result;}
  simplex.push_back(next);
 }
 // Any retained positive separating-plane lower bound remains a certificate,
 // even if the witness upper bound did not converge to the requested accuracy.
 if(result.lower<=0){auto p=penetration();if(p.valid&&p.inside){result.inside=true;result.point=p.point;result.normal=p.normal;return result;}}
 return result.valid?result:Distance{};
}
using Evaluate=std::function<Distance(double)>;
inline gmj_sweep::Result cast(const Evaluate &at,Vec motion) {
 gmj_sweep::Result result;Distance d=at(0);
 auto trace=[&](const char*reason,double t,const Distance&v){if(std::getenv("GMJ_CONVEX_TRACE"))std::fprintf(stderr,"CONVEX_DIAGNOSTIC %s t=%.17g lower=%.17g upper=%.17g uncertainty=%.17g n=(%.17g,%.17g,%.17g) inside=%d valid=%d\n",reason,t,v.lower,v.upper,v.uncertainty,v.normal.x,v.normal.y,v.normal.z,int(v.inside),int(v.valid));};if(!d.valid){result.valid=false;return result;}
 if(d.inside){result.initial_overlap=true;return result;}
 if(motion.length()==0)return result;
 if(d.boundary){
  if(d.normal.dot(motion)>=0)return result;
  result.hit=true;result.safe=result.unsafe=result.minimum=0;result.point=d.point;result.normal=d.normal;return result;
 }
 double t=0,last_safe=0;
 for(int iteration=0;iteration<256;++iteration){
  if(!d.valid){result.valid=false;return result;}
  if(d.inside||d.boundary){
   double lo=last_safe,hi=t;Distance contact=d;
   for(int refine=0;refine<80;++refine){double mid=lo+(hi-lo)*.5;if(mid<=lo||mid>=hi)break;Distance test=at(mid);
    if(!test.valid)break;if(test.inside||test.boundary){hi=mid;contact=test;}else if(test.lower>0)lo=mid;else break;
   }
   result.hit=true;result.safe=lo;result.unsafe=hi;result.minimum=t;result.point=contact.point;result.normal=contact.normal;return result;
  }
  if(!(d.lower>0)){
   // A convex pair under fixed-orientation translation has one connected
   // intersection interval. A candidate may supply an upper bracket only after
   // actual penetration is certified; a clear candidate never certifies a miss.
   // Thus this branch cannot step past a thin hit and then continue the search.
   const double closing=-d.normal.dot(motion);
   if(closing<=0){trace("uncertain_nonclosing",t,d);result.valid=false;return result;}
   double candidate=t+(d.upper+4*d.uncertainty)/closing;
   // The engine API returns float fractions/poses. Try the next representable
   // fraction as a contact upper bound, then certify actual intersection.
   // This is not a sampled miss test: a non-contact candidate is an error.
   candidate=std::max(candidate,double(std::nextafter(float(t),1.f)));
   if(candidate<=t)candidate=std::nextafter(t,1.0);
   if(candidate>1){result.valid=false;return result;}
   Distance upper=at(candidate);
   if(!upper.valid||(!upper.inside&&!upper.boundary)){trace("candidate_not_contact",candidate,upper);trace("previous",t,d);result.valid=false;return result;}
   t=candidate;d=upper;continue;
  }
  const double closing=-d.normal.dot(motion);
  if(closing<=0)return result; // The same separating plane holds for all future t.
  const double step=d.lower/closing;
  if(step>1-t)return result;
  last_safe=t;double next=t+step;
  if(next<=t){trace("stalled",t,d);result.valid=false;return result;}
  t=next;d=at(t);
 }
 trace("iteration_limit",t,d);result.valid=false;return result;
}
}
