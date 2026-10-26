#pragma once
#ifdef __FAST_MATH__
#error SDF interval certificates require ordinary IEEE arithmetic, without fast-math
#endif
#include "mj_convex_sweep.h"
#include <mujoco/mujoco.h>
#include <array>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <vector>
// Bounds the actual MuJoCo 3.16 octree polynomial, including exterior clamp
// and box-distance extension. No source-triangle or unit-Lipschitz assumption.
namespace gmj_sdf {
using Vec=gmj_sweep::Vec;
struct Box {Vec lo{},hi{};};
struct Range {bool valid=false;double lo=0,hi=0;bool shape_positive=false;};
struct Stats {
 int boxes=0,field_nodes=0,gjk=0,intervals=0;bool exhausted=false;
 std::chrono::steady_clock::time_point deadline=std::chrono::steady_clock::now()+std::chrono::seconds(2);
 bool expired(){if(std::chrono::steady_clock::now()>deadline){exhausted=true;return true;}return false;}
};
// Outward-rounded arithmetic encloses each kernel operation. The polynomial
// is multi-affine, so its extrema on a coordinate box occur at its corners.
struct Number {double lo=0,hi=0;};
inline double down(double x){return std::nextafter(x,-std::numeric_limits<double>::infinity());}
inline double up(double x){return std::nextafter(x,std::numeric_limits<double>::infinity());}
inline Number add(Number a,Number b){return {down(a.lo+b.lo),up(a.hi+b.hi)};}
inline Number sub(Number a,Number b){return {down(a.lo-b.hi),up(a.hi-b.lo)};}
inline Number mul(Number a,Number b){double p[4]={a.lo*b.lo,a.lo*b.hi,a.hi*b.lo,a.hi*b.hi};return {down(*std::min_element(p,p+4)),up(*std::max_element(p,p+4))};}
inline Number divide_positive(Number a,double b){return {down(a.lo/b),up(a.hi/b)};}
inline Number lerp(Number a,Number b,Number t){return add(mul(sub({1,1},t),a),mul(t,b));}
inline Vec cross(Vec a,Vec b){return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};}
// A tetrahedron of actual swept support points is contained in the convex
// swept volume. A point strictly inside it is an existential intersection
// witness, not a temporal sample and never a separation/miss certificate.
inline bool support_hull_contains(const gmj_convex::Support&shape,Vec point,double geometry_error=0){
 std::vector<Vec> vertices;
 for(Vec n:{Vec{1,1,1},Vec{-1,-1,1},Vec{-1,1,-1},Vec{1,-1,-1},Vec{1,0,0},Vec{-1,0,0},Vec{0,1,0},Vec{0,-1,0},Vec{0,0,1},Vec{0,0,-1}})vertices.push_back(shape(n)-point);
 double scale=1;for(auto v:vertices)scale=std::max(scale,v.length());double tolerance=512*std::numeric_limits<double>::epsilon()*scale+std::sqrt(3.0)*geometry_error;
 for(int a=0;a<int(vertices.size());++a)for(int b=a+1;b<int(vertices.size());++b)for(int c=b+1;c<int(vertices.size());++c)for(int d=c+1;d<int(vertices.size());++d){
  Vec tetra[4]={vertices[a],vertices[b],vertices[c],vertices[d]};bool inside=true;
  for(int opposite=0;opposite<4;++opposite){int ids[3],n=0;for(int k=0;k<4;++k)if(k!=opposite)ids[n++]=k;
   Vec normal=cross(tetra[ids[1]]-tetra[ids[0]],tetra[ids[2]]-tetra[ids[0]]);double length=normal.length();
   double p=(tetra[ids[0]]*-1).dot(normal),q=(tetra[opposite]-tetra[ids[0]]).dot(normal);
   if(!(length>0)||!std::isfinite(length)||std::abs(p)<=tolerance*length||std::abs(q)<=tolerance*length||(p>0)!=(q>0)){inside=false;break;}
  }
  if(inside)return true;
 }
 return false;
}
class Field {
 const mjModel*m=nullptr;int root=-1,count=0;
 std::vector<double> minimum,maximum;
 Range polynomial(int absolute,const double*a,const double*z,const Vec*plane=nullptr)const{
  const mjtNum*b=m->oct_aabb+6*absolute,*c=m->oct_coeff+8*absolute;Number coefficients[8];double maximum_abs=0;Number absolute_weights{1,1};
  for(int j=0;j<8;++j){coefficients[j]={c[j],c[j]};maximum_abs=std::max(maximum_abs,std::abs(c[j]));}
  for(int axis=0;axis<3;++axis){
   // Reproduce native vmin/vmax and denominator rounding, not 2*half_size.
   const double low=b[axis]-b[axis+3],high=b[axis]+b[axis+3],denominator=high-low;if(!(denominator>0))return {};
   Number low_coord=divide_positive(sub({a[axis],a[axis]},{low,low}),denominator),high_coord=divide_positive(sub({z[axis],z[axis]},{low,low}),denominator);
   double excess=std::max({0.0,-low_coord.lo,high_coord.hi-1});absolute_weights=mul(absolute_weights,{1,up(1+2*excess)});
   for(int j=0;j<8;++j)if(!(j&(1<<axis))){int other=j^(1<<axis);auto first=coefficients[j],second=coefficients[other];coefficients[j]=lerp(first,second,low_coord);coefficients[other]=lerp(first,second,high_coord);}
  }
  double lo=std::numeric_limits<double>::infinity(),hi=-lo;
  for(int j=0;j<8;++j){auto v=coefficients[j];if(plane){Number linear{0,0};
    for(int axis=0;axis<3;++axis){double c=component(*plane,axis),x=j&(1<<axis)?z[axis]:a[axis];linear=add(linear,mul({c,c},{x,x}));}v=sub(v,linear);}
   lo=std::min(lo,v.lo);hi=std::max(hi,v.hi);}
  // Native weights/products/accumulation have fewer than 64 operations.
  // gamma_128(machine epsilon) also covers subnormal absolute roundoff.
  const double u=std::numeric_limits<double>::epsilon(),gamma=128*u/(1-128*u);
  double error=mul(mul({gamma,gamma},{maximum_abs,maximum_abs}),absolute_weights).hi+128*std::numeric_limits<double>::denorm_min();
  return {true,down(lo-error),up(hi+error)};
 }
 // Enclose box intersect (a.x + residual <= 0) by a convex hull
 // of outward interval vertex boxes. GJK separation from this superset is
 // a sign certificate on the JOINT shape/cell domain, not a scalar minimum.
 bool negative_region_disjoint(const double*lo,const double*hi,Vec plane,double residual,
     const gmj_convex::Support&shape,Stats&stats,double geometry_error)const{
  struct Vertex{Vec lo,hi;};std::vector<Vertex> vertices;
  double slope[3]={plane.x,plane.y,plane.z};
  auto eval=[&](const double*p){Number value{residual,residual};for(int k=0;k<3;++k)value=add(value,mul({slope[k],slope[k]},{p[k],p[k]}));return value;};
  for(int mask=0;mask<8;++mask){double p[3];for(int k=0;k<3;++k)p[k]=mask&(1<<k)?hi[k]:lo[k];
   if(eval(p).lo<=0){Vec v{p[0],p[1],p[2]};vertices.push_back({v,v});}}
  for(int axis=0;axis<3;++axis){
   if(lo[axis]==hi[axis]||slope[axis]==0)continue;
   Number denominator=mul({slope[axis],slope[axis]},sub({hi[axis],hi[axis]},{lo[axis],lo[axis]}));
   if(denominator.lo<=0&&denominator.hi>=0)return false;
   for(int mask=0;mask<8;++mask)if(!(mask&(1<<axis))){
    double p[3];for(int k=0;k<3;++k)p[k]=mask&(1<<k)?hi[k]:lo[k];auto at=eval(p);Number numerator{-at.hi,-at.lo};
    double ratios[4]={numerator.lo/denominator.lo,numerator.lo/denominator.hi,numerator.hi/denominator.lo,numerator.hi/denominator.hi};
    Number t{down(*std::min_element(ratios,ratios+4)),up(*std::max_element(ratios,ratios+4))};
    if(!std::isfinite(t.lo)||!std::isfinite(t.hi))return false;if(t.hi<0||t.lo>1)continue;
    t.lo=std::max(0.0,t.lo);t.hi=std::min(1.0,t.hi);
    Number coordinate=add({lo[axis],lo[axis]},mul(sub({hi[axis],hi[axis]},{lo[axis],lo[axis]}),t));
    double a[3]={p[0],p[1],p[2]},b[3]={p[0],p[1],p[2]};a[axis]=coordinate.lo;b[axis]=coordinate.hi;
    vertices.push_back({{a[0],a[1],a[2]},{b[0],b[1],b[2]}});
   }
  }
  if(vertices.empty())return true;
  auto support=[&](Vec n){double best=-std::numeric_limits<double>::infinity();Vec result{};
   for(const auto&v:vertices){Vec p{n.x>=0?v.hi.x:v.lo.x,n.y>=0?v.hi.y:v.lo.y,n.z>=0?v.hi.z:v.lo.z};double d=n.dot(p);if(d>best){best=d;result=p;}}return result;};
  Vec center{(lo[0]+hi[0])*.5,(lo[1]+hi[1])*.5,(lo[2]+hi[2])*.5};++stats.gjk;
  auto distance=gmj_convex::distance(shape,support,shape({1,0,0})-center,[](){return gmj_convex::Penetration{true,false,{},{}};});
  return distance.valid&&distance.lower>roundoff+std::sqrt(3.0)*geometry_error;
 }
 bool fill(int relative,std::vector<unsigned char>&visited){
  if(relative<0||relative>=count||visited[relative])return false;visited[relative]=1;int absolute=root+relative;
  const mjtNum*b=m->oct_aabb+6*absolute;for(int k=0;k<3;++k)if(!std::isfinite(b[k])||!std::isfinite(b[k+3])||b[k+3]<=0)return false;
  minimum[relative]=std::numeric_limits<double>::infinity();maximum[relative]=-minimum[relative];
  int children=0;for(int k=0;k<8;++k){int child=m->oct_child[8*absolute+k];if(child>=0){++children;if(!fill(child,visited))return false;minimum[relative]=std::min(minimum[relative],minimum[child]);maximum[relative]=std::max(maximum[relative],maximum[child]);}}
  if(children&&children!=8)return false;
  if(!children){
   double a[3],z[3];for(int k=0;k<3;++k){double low=b[k]-b[k+3],high=b[k]+b[k+3],guard=16*std::numeric_limits<double>::epsilon()*std::max({1.0,std::abs(low),std::abs(high)});
    a[k]=down(low-1e-8-guard);z[k]=up(high+1e-8+guard);}
   for(int k=0;k<8;++k)if(!std::isfinite(m->oct_coeff[8*absolute+k]))return false;
   auto range=polynomial(absolute,a,z);if(!range.valid)return false;minimum[relative]=range.lo;maximum[relative]=range.hi;
  }
  visited[relative]=2;return true;
 }
 static double component(Vec v,int k){return k==0?v.x:k==1?v.y:v.z;}
public:
 bool valid=false;double roundoff=0,local_lipschitz_bound=0,build_seconds=0;
 Field(const mjModel*model,int id):m(model){
  const auto began=std::chrono::steady_clock::now();
  if(mj_version()!=3016000||sizeof(mjtNum)!=8||!m||id<0||id>=m->nmesh)return;root=m->mesh_octadr[id];count=m->mesh_octnum[id];
  if(root<0||count<=0||count>500000||root+count>m->noct)return;
  minimum.resize(count);maximum.resize(count);std::vector<unsigned char> visited(count);
  if(!fill(0,visited))return;for(auto v:visited)if(v!=2)return;
  const mjtNum*r=m->oct_aabb+6*root;for(int k=0;k<3;++k)if(r[k+3]<=2e-6||std::abs(r[k])+r[k+3]>1024)return;
  double scale=std::max({1.0,std::abs(minimum[0]),std::abs(maximum[0]),r[3],r[4],r[5]});
  roundoff=2048*std::numeric_limits<double>::epsilon()*scale;
  for(int n=0;n<count;++n)if(m->oct_child[8*(root+n)]<0){const mjtNum*b=m->oct_aabb+6*(root+n),*c=m->oct_coeff+8*(root+n);double bounds[3]={};
   for(int k=0;k<3;++k)for(int j=0;j<8;++j)if(!(j&(1<<k)))bounds[k]=std::max(bounds[k],std::abs(c[j^(1<<k)]-c[j])/(2*b[k+3]));
   local_lipschitz_bound=std::max(local_lipschitz_bound,std::hypot(bounds[0],bounds[1],bounds[2]));
  }
  valid=true;build_seconds=std::chrono::duration<double>(std::chrono::steady_clock::now()-began).count();
 }
 int nodes()const{return count;}
 Range range(const Box&box,Stats&stats,const gmj_convex::Support*shape=nullptr,double geometry_error=0)const{
  if(!valid)return {};double lo[3],hi[3];const mjtNum*r=m->oct_aabb+6*root;Number squared_distance{0,0};bool strictly_internal=true;
  for(int k=0;k<3;++k){double a=component(box.lo,k),b=component(box.hi,k),low=r[k]-r[3+k],high=r[k]+r[3+k];if(!std::isfinite(a)||!std::isfinite(b)||a>b)return {};
   Number offset=sub({a,b},{r[k],r[k]});double near=offset.lo<=0&&offset.hi>=0?0:std::min(std::abs(offset.lo),std::abs(offset.hi)),far=std::max(std::abs(offset.lo),std::abs(offset.hi));
   Number raw_gap=sub({near,far},{r[k+3],r[k+3]});bool possible_low=offset.lo<=0&&raw_gap.hi>=0,possible_high=offset.hi>=0&&raw_gap.hi>=0;if(raw_gap.hi>=0)strictly_internal=false;
   Number gap{std::max(0.0,raw_gap.lo),std::max(0.0,raw_gap.hi)};squared_distance=add(squared_distance,mul(gap,gap));
   lo[k]=std::clamp(a,low,high);hi[k]=std::clamp(b,low,high);
   // Native decides q >= 0 after rounded subtraction, including a point one
   // ULP geometrically inside when another axis triggers the projection.
   if(possible_low||possible_high){
    // Bound the cancellation error of native p -= (abs(p-c)-h+eps).
    // Reject when its fixed inward shift is not representable reliably.
    double error=up(128*std::numeric_limits<double>::epsilon()*std::max({1.0,std::abs(a),std::abs(b),std::abs(r[k]),r[k+3]}));
    if(error>1e-6/8)return {};
    if(possible_low)hi[k]=std::max(hi[k],up(low+1e-6));
    if(possible_high)lo[k]=std::min(lo[k],down(high-1e-6));
    lo[k]=down(lo[k]-error);hi[k]=up(hi[k]+error);
   }
  }
  bool shape_positive=shape&&strictly_internal;
  Range result;result.lo=std::numeric_limits<double>::infinity();result.hi=-result.lo;
  struct NodeTask{int relative;std::array<double,3> lo,hi;};
  std::vector<NodeTask> pending{{0,{lo[0],lo[1],lo[2]},{hi[0],hi[1],hi[2]}}};
  while(!pending.empty()){
   if(++stats.field_nodes>8000000||((stats.field_nodes&127)==0&&stats.expired())){stats.exhausted=true;return {};}
   auto task=pending.back();pending.pop_back();int relative=task.relative,absolute=root+relative;const mjtNum*b=m->oct_aabb+6*absolute;
   bool intersects=true,contains=true;double a[3],z[3];
   for(int k=0;k<3;++k){double base_low=b[k]-b[k+3],base_high=b[k]+b[k+3],guard=16*std::numeric_limits<double>::epsilon()*std::max({1.0,std::abs(base_low),std::abs(base_high)});
    double low=down(base_low-1e-8-guard),high=up(base_high+1e-8+guard);a[k]=std::max(task.lo[k],low);z[k]=std::min(task.hi[k],high);if(a[k]>z[k])intersects=false;if(task.lo[k]>low||task.hi[k]<high)contains=false;}
   if(!intersects)continue;
   if(contains&&(!shape||!strictly_internal||minimum[relative]>roundoff)){if(minimum[relative]<=roundoff)shape_positive=false;result.lo=std::min(result.lo,minimum[relative]);result.hi=std::max(result.hi,maximum[relative]);continue;}
   if(m->oct_child[8*absolute]>=0){
    Number coordinate[3],split[3];double guard[3];
    for(int k=0;k<3;++k){double low=b[k]-b[k+3],high=b[k]+b[k+3],denominator=high-low;if(!(denominator>0))return {};
     coordinate[k]=divide_positive(sub({a[k],z[k]},{low,low}),denominator);
     split[k]=add({low,low},mul({.5,.5},{denominator,denominator}));
     // Preimage error for native rounded subtraction and division. The
     // forward coordinate interval also controls whether a branch exists.
     guard[k]=up(64*std::numeric_limits<double>::epsilon()*std::max({1.0,std::abs(low),std::abs(high),std::abs(a[k]),std::abs(z[k]),denominator}));
    }
    for(int child=0;child<8;++child){NodeTask next{m->oct_child[8*absolute+child],{a[0],a[1],a[2]},{z[0],z[1],z[2]}};bool possible=true;
     for(int k=0;k<3;++k){if(child&(1<<k)){
       if(coordinate[k].hi<.5)possible=false;
       next.lo[k]=std::max(next.lo[k],down(split[k].lo-guard[k]));
      }else{
       if(coordinate[k].lo>=.5)possible=false;
       next.hi[k]=std::min(next.hi[k],up(split[k].hi+guard[k]));
      }
      if(next.lo[k]>next.hi[k])possible=false;
     }
     if(possible)pending.push_back(next);
    }
    continue;
   }
   auto values=polynomial(absolute,a,z);if(!values.valid)return {};bool leaf_positive=values.lo>roundoff;
   if(shape&&strictly_internal&&!leaf_positive){
    // Any finite affine plane is allowed: subtract it from the actual
    // multi-affine leaf polynomial, bound the residual at all eight corners,
    // then minimize the plane over the entire convex swept support volume.
    // This is a lower bound on its intersection with this leaf, even when
    // the support point lies outside the leaf. No nearest-plane assumption.
    double slopes[3]={},parameter[3]={};const mjtNum*c=m->oct_coeff+8*absolute;
    // Recenter the arbitrary affine plane on the current clipped cell box.
    // Validity still comes solely from its complete interval residual.
    for(int k=0;k<3;++k){double low=b[k]-b[k+3],high=b[k]+b[k+3];parameter[k]=((a[k]+z[k])*.5-low)/(high-low);}
    for(int k=0;k<3;++k)for(int j=0;j<8;++j)if(!(j&(1<<k))){
     double weight=1;for(int axis=0;axis<3;++axis)if(axis!=k)weight*=j&(1<<axis)?parameter[axis]:1-parameter[axis];
     double low=b[k]-b[k+3],high=b[k]+b[k+3];slopes[k]+=(c[j^(1<<k)]-c[j])*weight/(high-low);
    }
    Vec plane{slopes[0],slopes[1],slopes[2]};
    if(std::isfinite(plane.length())){
     auto residual=polynomial(absolute,a,z,&plane);Vec point=(*shape)(plane*-1);Number linear{0,0},error{0,0};
     for(int k=0;k<3;++k){double slope=slopes[k],coordinate=component(point,k);linear=add(linear,mul({slope,slope},{coordinate,coordinate}));error=add(error,mul({std::abs(slope),std::abs(slope)},{geometry_error,geometry_error}));}
     if(residual.valid){values.lo=std::max(values.lo,sub(add(linear,{residual.lo,residual.lo}),error).lo);
      leaf_positive=values.lo>roundoff||negative_region_disjoint(a,z,plane,down(residual.lo-roundoff),*shape,stats,geometry_error);}
    }
   }
   if(!leaf_positive)shape_positive=false;
   result.lo=std::min(result.lo,values.lo);result.hi=std::max(result.hi,values.hi);
  }
  if(!std::isfinite(result.lo)||!std::isfinite(result.hi))return {};
  Number distance{down(std::sqrt(std::max(0.0,squared_distance.lo))),up(std::sqrt(std::max(0.0,squared_distance.hi)))};
  auto extended=add({result.lo,result.hi},distance);return {true,down(extended.lo-roundoff),up(extended.hi+roundoff),shape_positive};
 }
 bool separated(const gmj_convex::Support&shape,Stats&stats,double geometry_error=0)const{
  Box initial;double lo[3],hi[3];for(int k=0;k<3;++k){Vec n{};if(k==0)n.x=1;else if(k==1)n.y=1;else n.z=1;lo[k]=down(component(shape(n*-1),k)-geometry_error);hi[k]=up(component(shape(n),k)+geometry_error);}
  initial.lo={lo[0],lo[1],lo[2]};initial.hi={hi[0],hi[1],hi[2]};

  const mjtNum*root_box=m->oct_aabb+6*root;Vec root_center{root_box[0],root_box[1],root_box[2]};
  if(root_center.x>=initial.lo.x&&root_center.x<=initial.hi.x&&root_center.y>=initial.lo.y&&root_center.y<=initial.hi.y&&root_center.z>=initial.lo.z&&root_center.z<=initial.hi.z){
   auto at_center=range({root_center-Vec{geometry_error,geometry_error,geometry_error},root_center+Vec{geometry_error,geometry_error,geometry_error}},stats);
   if(at_center.valid&&at_center.hi<0&&support_hull_contains(shape,root_center,geometry_error))return false;
  }

  struct Task{Box box;int depth;};std::vector<Task> pending{{initial,0}};
  while(!pending.empty()){
   if(++stats.boxes>160000||stats.expired()){stats.exhausted=true;return false;}Task task=pending.back();pending.pop_back();
   Range field=range(task.box,stats,&shape,geometry_error);if(!field.valid)return false;if(field.lo>0||field.shape_positive)continue;
   Vec center=(task.box.lo+task.box.hi)*.5,half=(task.box.hi-task.box.lo)*.5;
   // A spatial negative-field point inside the exact swept convex volume
   // proves that this interval cannot be discarded. It is not a time sample;
   // returned hits still need a real pose and the earlier safe-prefix proof.
   auto center_field=range({center-Vec{geometry_error,geometry_error,geometry_error},center+Vec{geometry_error,geometry_error,geometry_error}},stats);
   if(center_field.valid&&center_field.hi<0&&support_hull_contains(shape,center,geometry_error))return false;

   auto support_box=[&](Vec n){return center+Vec{n.x>=0?half.x:-half.x,n.y>=0?half.y:-half.y,n.z>=0?half.z:-half.z};};
   ++stats.gjk;auto d=gmj_convex::distance(shape,support_box,shape({1,0,0})-center,[](){return gmj_convex::Penetration{true,false,{},{}};});
   if(d.valid&&d.lower>roundoff+std::sqrt(3.0)*geometry_error)continue;
   if(field.hi<0||task.depth>=80)return false;
   Vec size=task.box.hi-task.box.lo;int axis=size.y>size.x?1:0;if(size.z>component(size,axis))axis=2;
   double middle=(component(task.box.lo,axis)+component(task.box.hi,axis))*.5;
   if(middle<=component(task.box.lo,axis)||middle>=component(task.box.hi,axis))return false;
   Task left=task,right=task;++left.depth;++right.depth;
   if(axis==0){left.box.hi.x=middle;right.box.lo.x=middle;}else if(axis==1){left.box.hi.y=middle;right.box.lo.y=middle;}else{left.box.hi.z=middle;right.box.lo.z=middle;}
   pending.push_back(right);pending.push_back(left);
  }
  return true;
 }
};
// Contact callback certifies an actual pose intersection and physical witness.
// Unknown is never a successful miss. Only a whole swept-volume positive-field
// certificate discards a time interval; pose evaluations only certify uppers.
using ContactAt=std::function<gmj_convex::Distance(double)>;
using GeometryError=std::function<double(double,double)>;
inline gmj_sweep::Result cast(const Field&field,const gmj_convex::Support&base,Vec motion,const ContactAt&contact,Stats&stats,const GeometryError&geometry_error={}){
 gmj_sweep::Result result;if(!field.valid){result.valid=false;return result;}
 if(motion.length()==0)return result;
 auto initial=contact(0);
 if(initial.valid&&initial.inside){result.initial_overlap=true;return result;}
 auto swept=[&](double lo,double hi){return gmj_convex::Support([&,lo,hi](Vec n){return base(n)+motion*(n.dot(motion)>0?hi:lo);});};
 if(!field.separated(swept(0,0),stats,geometry_error?geometry_error(0,0):0)){result.valid=false;return result;}
 if(motion.length()==0)return result;
 struct Interval{double lo,hi;int depth;};std::vector<Interval> pending{{0,1,0}};double safe=0;
 while(!pending.empty()){
  if(stats.expired()){result.valid=false;return result;}
  if(++stats.intervals>160){stats.exhausted=true;result.valid=false;return result;}
  auto interval=pending.back();pending.pop_back();
  auto at=contact(interval.hi);if(stats.expired()){result.valid=false;return result;}
  if(!(at.valid&&at.inside)&&interval.hi<1){
   double candidate=double(std::nextafter(float(interval.hi),1.f));
   if(candidate>interval.hi&&candidate<=1){auto upper=contact(candidate);
    // An actual hit at the next API-representable pose is a valid upper
    // bracket even for a nonconvex field. All pending intervals are later
    // than the current interval; the earliest unproved prefix is retained.
    // A clear candidate never skips or certifies any time.
    if(upper.valid&&upper.inside){interval.hi=candidate;at=upper;pending.clear();}
   }
  }
  // Match the public float-fraction representation instead of demanding
  // a narrower bracket than adjacent representable contact upper bounds.
  double ulp=double(std::nextafter(float(interval.hi),std::numeric_limits<float>::infinity()))-double(float(interval.hi));
  // Stop at an explicit spatial TOI bracket, not an exact zero. Both
  // endpoints still require independent separation/contact certificates.
  double fraction_precision=std::max(8*ulp,4e-6/std::max(1.0,motion.length()));
  if(at.valid&&at.inside&&interval.hi-interval.lo<=fraction_precision){result.hit=true;result.safe=safe;result.unsafe=interval.hi;result.minimum=interval.hi;result.point=at.point;result.normal=at.normal;return result;}
  if(!(at.valid&&at.inside)&&field.separated(swept(interval.lo,interval.hi),stats,geometry_error?geometry_error(interval.lo,interval.hi):0)){safe=interval.hi;continue;}
  if(stats.exhausted){if(std::getenv("GMJ_SDF_TRACE"))std::fprintf(stderr,"SDF_BUDGET safe=%.17g lo=%.17g hi=%.17g upper_inside=%d\n",safe,interval.lo,interval.hi,int(at.inside));result.valid=false;return result;}
  double mid=interval.lo+(interval.hi-interval.lo)*.5;
  if(interval.depth>=48||mid<=interval.lo||mid>=interval.hi){
   if(std::getenv("GMJ_SDF_TRACE")){auto later=contact(std::min(1.0,interval.hi+1e-6));std::fprintf(stderr,"SDF_INTERVAL_UNRESOLVED safe=%.17g lo=%.17g hi=%.17g later_inside=%d boxes=%d nodes=%d\n",safe,interval.lo,interval.hi,int(later.inside),stats.boxes,stats.field_nodes);}
   result.valid=false;return result;}
  pending.push_back({mid,interval.hi,interval.depth+1});pending.push_back({interval.lo,mid,interval.depth+1});
 }
 return result;
}
} // namespace gmj_sdf
