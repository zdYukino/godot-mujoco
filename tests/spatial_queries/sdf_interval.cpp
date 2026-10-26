#include "../../src/physics/mj_sdf_interval.h"
#include <cstdio>
#include <random>
#include <memory>
int main(){
 const char*xml="<mujoco><asset><mesh name='cube' vertex='-1 -1 -.4 1 -1 -.4 1 1 -.4 -1 1 -.4 -1 -1 .4 1 -1 .4 1 1 .4 -1 1 .4' face='0 2 1 0 3 2 4 5 6 4 6 7 0 1 5 0 5 4 1 2 6 1 6 5 2 3 7 2 7 6 3 0 4 3 4 7'/></asset><worldbody><geom type='sdf' mesh='cube'/></worldbody></mujoco>";
 char error[2048]={};std::unique_ptr<mjSpec,decltype(&mj_deleteSpec)> spec(mj_parseXMLString(xml,nullptr,error,sizeof(error)),mj_deleteSpec);
 if(!spec){std::fprintf(stderr,"%s\n",error);return 2;}
 std::unique_ptr<mjModel,decltype(&mj_deleteModel)> m(mj_compile(spec.get(),nullptr),mj_deleteModel);
 if(!m){std::fprintf(stderr,"%s\n",mjs_getError(spec.get()));return 2;}
 std::unique_ptr<mjData,decltype(&mj_deleteData)> d(mj_makeData(m.get()),mj_deleteData);mj_forward(m.get(),d.get());
 int id=m->geom_dataid[0];const mjpPlugin*plugin=nullptr;mjtGeom kind=mjGEOM_SDF;mjSDF sdf{};sdf.plugin=&plugin;sdf.id=&id;sdf.type=mjSDFTYPE_SINGLE;sdf.geomtype=&kind;
 gmj_sdf::Field field(m.get(),id);if(!field.valid)return 3;
 std::mt19937 gen(20261026);std::uniform_real_distribution<double> u(0,1);int checks=0;
 auto value=[&](gmj_sdf::Vec v){double p[3]={v.x,v.y,v.z};return mjc_distance(m.get(),d.get(),&sdf,p);};
 const mjtNum*root=m->oct_aabb+6*m->mesh_octadr[id];
 for(int i=0;i<500;++i){double a[3],b[3];for(int k=0;k<3;++k){a[k]=root[k]+(u(gen)*4-2)*root[k+3];b[k]=a[k]+u(gen)*root[k+3];}
  gmj_sdf::Box box{{a[0],a[1],a[2]},{b[0],b[1],b[2]}};gmj_sdf::Stats stats;auto bounds=field.range(box,stats);if(!bounds.valid)return 4;
  for(int j=0;j<24;++j){double p[3];for(int k=0;k<3;++k)p[k]=a[k]+(b[k]-a[k])*(j<8?double((j>>k)&1):u(gen));double v=value({p[0],p[1],p[2]});
   if(v<bounds.lo||v>bounds.hi){std::fprintf(stderr,"SDF_RANGE_FAIL sample=%d value=%.17g range=(%.17g,%.17g)\n",i,v,bounds.lo,bounds.hi);return 1;}++checks;
  }
 }
 std::printf("SDF_RANGE_ENCLOSURE_PASS %d local_lipschitz_bound=%.17g\n",checks,field.local_lipschitz_bound);
 // The affine tightening bounds the polynomial over box intersect support.
 // Check native values of actual sphere points, including a geometric envelope.
 int affine_checks=0;
 for(int i=0;i<200;++i){
  gmj_sdf::Vec center{(u(gen)-.5)*.8,(u(gen)-.5)*.8,(u(gen)-.5)*.3};
  double radius=.05+.2*u(gen),error=1e-10;
  gmj_convex::Support sphere=[&](auto n){double len=n.length();return center+(len?n*(radius/len):gmj_sdf::Vec{});};
  gmj_sdf::Box box{center-gmj_sdf::Vec{radius,radius,radius},center+gmj_sdf::Vec{radius,radius,radius}};
  gmj_sdf::Stats stats;auto enclosure=field.range(box,stats,&sphere,error);if(!enclosure.valid)return 7;
  for(int j=0;j<32;++j){gmj_sdf::Vec direction{u(gen)-.5,u(gen)-.5,u(gen)-.5};auto point=center+direction*(radius*u(gen)/direction.length());double actual=value(point);
   if(actual<enclosure.lo||actual>enclosure.hi||(enclosure.shape_positive&&actual<=0)){std::fprintf(stderr,"SDF_AFFINE_FAIL value=%.17g lo=%.17g hi=%.17g\n",actual,enclosure.lo,enclosure.hi);return 1;}++affine_checks;
  }
 }
 std::printf("SDF_AFFINE_ENCLOSURE_PASS %d\n",affine_checks);

 // Explicit root boundary/exterior projection probes. The 1e-6 inward
 // shift must be enclosed, including a second coordinate exactly on a face.
 int boundary_checks=0;
 for(int axis=0;axis<3;++axis)for(int side:{-1,1})for(double delta:{-2e-6,-1e-6,-1e-8,-1e-12,0.,1e-12,1e-8,1e-6,2e-6})for(int extra:{0,1}){
  double p[3]={root[0],root[1],root[2]};p[axis]=root[axis]+side*(root[axis+3]+delta);
  if(extra)p[(axis+1)%3]=root[(axis+1)%3]+root[3+(axis+1)%3];
  gmj_sdf::Box b{{p[0],p[1],p[2]},{p[0],p[1],p[2]}};gmj_sdf::Stats st;auto range=field.range(b,st);double actual=value({p[0],p[1],p[2]});
  if(!range.valid||actual<range.lo||actual>range.hi){std::fprintf(stderr,"SDF_ROOT_BOUNDARY_FAIL axis=%d delta=%.17g value=%.17g lo=%.17g hi=%.17g\n",axis,delta,actual,range.lo,range.hi);return 1;}++boundary_checks;
 }
 double p0[3]={root[0]+root[3]-1e-12,root[1],root[2]},p1[3]={root[0]+root[3]+1e-12,root[1],root[2]};
 double jump=std::abs(value({p1[0],p1[1],p1[2]})-value({p0[0],p0[1],p0[2]}));
 std::printf("SDF_BOUNDARY_ENCLOSURE_PASS %d root_face_difference=%.17g sample_separation=2e-12\n",boundary_checks,jump);
 // Offset root + single-ULP inside + another axis outside: native rounded
 // subtraction can still select q>=0 and shift the "inside" axis by 1e-6.
 int ulp_probes=0;
 for(double center:{-.5,.5,-.25,.25})for(int side:{-1,1}){
  mjModel view=*m;int root_address=0,node_count=1,children[8]={-1,-1,-1,-1,-1,-1,-1,-1};
  double bounds[6]={center,0,0,1,1,1},coefficients[8];for(int j=0;j<8;++j)coefficients[j]=center+(j&1?1:-1);
  view.noct=1;view.nmesh=1;view.mesh_octadr=&root_address;view.mesh_octnum=&node_count;view.oct_child=children;view.oct_aabb=bounds;view.oct_coeff=coefficients;
  gmj_sdf::Field offset_field(&view,0);if(!offset_field.valid)return 5;
  double face_value=center+side,point_x=face_value;
  for(int step=0;step<5;++step){if(step)point_x=std::nextafter(point_x,side>0?-std::numeric_limits<double>::infinity():std::numeric_limits<double>::infinity());
   for(double outside:{1.125,1.5}){double p[3]={point_x,outside,0};gmj_sdf::Stats st;auto enclosed=offset_field.range({{p[0],p[1],0},{p[0],p[1],0}},st);double actual=mjc_distance(&view,d.get(),&sdf,p);
    if(!enclosed.valid||actual<enclosed.lo||actual>enclosed.hi){std::fprintf(stderr,"OFFSET_ULP_ROOT_FAIL c=%.17g side=%d step=%d x=%.17g actual=%.17g lo=%.17g hi=%.17g\n",center,side,step,p[0],actual,enclosed.lo,enclosed.hi);return 1;}++ulp_probes;
   }
  }
 }
 std::printf("SDF_OFFSET_ULP_BOUNDARY_PASS %d\n",ulp_probes);

 // Joint-domain counterexample: the unconstrained sphere crosses the plane,
 // but its intersection with this cell is strictly positive.
 {
  mjModel view=*m;int address=0,number=1,children[8]={-1,-1,-1,-1,-1,-1,-1,-1};
  double aabb[6]={0,0,0,2,2,2},coeff[8];for(int j=0;j<8;++j)coeff[j]=1.12-(j&1?2:-2)-(j&2?2:-2);
  view.noct=1;view.nmesh=1;view.mesh_octadr=&address;view.mesh_octnum=&number;view.oct_child=children;view.oct_aabb=aabb;view.oct_coeff=coeff;
  gmj_sdf::Field linear_field(&view,0);gmj_sdf::Vec center{-1,0,0};double radius=1.5;
  gmj_convex::Support sphere=[&](auto n){return center+n*(radius/n.length());};
  gmj_sdf::Stats st;auto bound=linear_field.range({{0,0,-.05},{.5,1,.05}},st,&sphere,1e-12);
  double actual_min=1.12-std::sqrt(1.25);
  if(!bound.valid||!bound.shape_positive||!(actual_min>0)||!(1.12-(-1+radius*std::sqrt(2.0))<0)){std::fprintf(stderr,"JOINT_CELL_CERTIFICATE_FAIL positive=%d min=%.17g\n",bound.shape_positive,actual_min);return 8;}
  std::printf("SDF_JOINT_CELL_CERTIFICATE_PASS actual_min=%.17g\n",actual_min);
 }

 int joint_samples=0,joint_positive=0;
 for(int trial=0;trial<200;++trial){
  mjModel view=*m;int address=0,number=1,children[8]={-1,-1,-1,-1,-1,-1,-1,-1};
  double aabb[6]={0,0,0,2,2,2},coeff[8];for(double&c:coeff)c=4*u(gen)-2;
  view.noct=1;view.nmesh=1;view.mesh_octadr=&address;view.mesh_octnum=&number;view.oct_child=children;view.oct_aabb=aabb;view.oct_coeff=coeff;
  gmj_sdf::Field random_field(&view,0);gmj_sdf::Vec center{3*u(gen)-1.5,3*u(gen)-1.5,3*u(gen)-1.5};double radius=.1+.3*u(gen);
  gmj_convex::Support sphere=[&](auto n){double len=n.length();return center+(len?n*(radius/len):gmj_sdf::Vec{});};
  gmj_sdf::Vec box_center=center+gmj_sdf::Vec{(u(gen)-.5)*radius,(u(gen)-.5)*radius,(u(gen)-.5)*radius},half{radius*(.1+.9*u(gen)),radius*(.1+.9*u(gen)),radius*(.1+.9*u(gen))};
  gmj_sdf::Box box{box_center-half,box_center+half};gmj_sdf::Stats stats;auto bound=random_field.range(box,stats,&sphere,1e-12);if(!bound.valid)return 9;if(bound.shape_positive)++joint_positive;
  for(int j=0;j<128;++j){gmj_sdf::Vec point=box_center+gmj_sdf::Vec{(2*u(gen)-1)*half.x,(2*u(gen)-1)*half.y,(2*u(gen)-1)*half.z};if((point-center).length()>=radius)continue;
   double xyz[3]={point.x,point.y,point.z},actual=mjc_distance(&view,d.get(),&sdf,xyz);
   if(actual<bound.lo||actual>bound.hi||(bound.shape_positive&&actual<=0)){std::fprintf(stderr,"JOINT_SIGN_FAIL trial=%d value=%.17g lo=%.17g hi=%.17g positive=%d\n",trial,actual,bound.lo,bound.hi,bound.shape_positive);return 1;}++joint_samples;
  }
 }
 if(joint_samples<10000||joint_positive==0)return 10;
 std::printf("SDF_RANDOM_JOINT_SIGN_PASS samples=%d positive_cases=%d\n",joint_samples,joint_positive);

 int branch_probes=0;
 for(auto center:{gmj_sdf::Vec{-.5,.25,-.125},gmj_sdf::Vec{512,-128,256}}){
  mjModel view=*m;int address=0,number=9,children[72];std::fill_n(children,72,-1);for(int j=0;j<8;++j)children[j]=j+1;
  double bounds[54],coeff[72]={};bounds[0]=center.x;bounds[1]=center.y;bounds[2]=center.z;bounds[3]=bounds[4]=bounds[5]=1;
  for(int j=0;j<8;++j){for(int axis=0;axis<3;++axis){bounds[6*(j+1)+axis]=bounds[axis]+(j&(1<<axis)?.5:-.5);bounds[6*(j+1)+axis+3]=.5;}for(int k=0;k<8;++k)coeff[8*(j+1)+k]=10*(j+1);}
  view.noct=9;view.nmesh=1;view.mesh_octadr=&address;view.mesh_octnum=&number;view.oct_child=children;view.oct_aabb=bounds;view.oct_coeff=coeff;
  gmj_sdf::Field branch_field(&view,0);if(!branch_field.valid)return 11;
  for(int axis=0;axis<3;++axis)for(int sign:{-1,1}){
   double xyz[3]={center.x+.25,center.y-.25,center.z+.25};xyz[axis]=bounds[axis];
   for(int step=0;step<10;++step){
    if(step==9)xyz[axis]=bounds[axis]+sign*1e-9;
    else if(step)xyz[axis]=std::nextafter(xyz[axis],sign>0?std::numeric_limits<double>::infinity():-std::numeric_limits<double>::infinity());
    gmj_sdf::Vec point{xyz[0],xyz[1],xyz[2]};gmj_sdf::Stats st;auto range=branch_field.range({point,point},st);double actual=mjc_distance(&view,d.get(),&sdf,xyz);
    if(!range.valid||actual<range.lo||actual>range.hi||(step==9&&range.hi-range.lo>1e-7)){std::fprintf(stderr,"SDF_BRANCH_PROBE_FAIL axis=%d sign=%d step=%d value=%.17g range=(%.17g,%.17g)\n",axis,sign,step,actual,range.lo,range.hi);return 1;}++branch_probes;
   }
  }
 }
 std::printf("SDF_NATIVE_BRANCH_SELECTION_PASS %d\n",branch_probes);
 auto cube=[](gmj_sdf::Vec n){return gmj_sdf::Vec{n.x>=0?1.:-1.,n.y>=0?1.:-1.,n.z>=0?1.:-1.};};
 auto plane=[](gmj_sdf::Vec n){return gmj_sdf::Vec{n.x>=0?1.:-1.,n.y>=0?1.:-1.,0};};
 if(!gmj_sdf::support_hull_contains(cube,{0,0,0})||gmj_sdf::support_hull_contains(cube,{2,0,0})||gmj_sdf::support_hull_contains(plane,{0,0,1}))return 6;
 // Derive the actual native-field face, never a source-triangle oracle.
 double lo=root[0],hi=root[0]+3*root[3];for(int i=0;i<80;++i){double mid=(lo+hi)*.5;if(value({mid,root[1],root[2]})<0)lo=mid;else hi=mid;}double face=(lo+hi)*.5;
 int casts=0;for(int i=0;i<12;++i){double radius=.1,start=face+1+i*.1,speed=i==11?100000:3+i;
  gmj_sdf::Vec center{start,root[1],root[2]},motion{-speed,0,0};gmj_convex::Support support=[&](auto n){double length=n.length();return center+(length?n*(radius/length):gmj_sdf::Vec{});};
  auto contact=[&](double t){gmj_convex::Distance result;auto c=center+motion*t;gmj_sdf::Vec p{c.x-radius,c.y,c.z};result.valid=true;
   result.inside=value(p)<-1e-11&&std::abs(c.x-face)<radius;result.point={face,c.y,c.z};result.normal={1,0,0};return result;};
  gmj_sdf::Stats stats;auto actual=gmj_sdf::cast(field,support,motion,contact,stats);double expected=(start-radius-face)/speed;
  if(!actual.valid||!actual.hit||actual.safe>expected+1e-10||actual.unsafe<expected-1e-10){std::fprintf(stderr,"SDF_CAST_FAIL i=%d valid=%d hit=%d lo=%.17g expected=%.17g hi=%.17g boxes=%d nodes=%d intervals=%d\n",i,actual.valid,actual.hit,actual.safe,expected,actual.unsafe,stats.boxes,stats.field_nodes,stats.intervals);return 1;}++casts;
 }
 std::printf("SDF_INTERVAL_NATIVE_RESULT {\"range_samples\":%d,\"affine_samples\":%d,\"joint_samples\":%d,\"joint_positive_cases\":%d,\"branch_probes\":%d,\"casts\":%d,\"boundary_probes\":%d,\"offset_ulp_probes\":%d,\"failed\":0,\"actual_mujoco\":\"%s\",\"octree_nodes\":%d,\"max_leaf_lipschitz_bound\":%.17g}\n",checks,affine_checks,joint_samples,joint_positive,branch_probes,casts,boundary_checks,ulp_probes,mj_versionString(),field.nodes(),field.local_lipschitz_bound);
}
