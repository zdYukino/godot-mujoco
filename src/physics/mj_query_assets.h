#pragma once
#include <mujoco/mujoco.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <limits>
#include <vector>
// Read-only views: no live material/group/alpha/pose or dynamics array is written.
namespace gmj_query {
inline bool hull_plane(const mjModel *m,int mesh,int polygon,mjtNum n[3],mjtNum &offset) {
 const int base=m->mesh_vertadr[mesh],adr=m->mesh_polyvertadr[polygon],count=m->mesh_polyvertnum[polygon];
 if(count<3)return false;
 mjtNum a[3],u[3],v[3],center[3]={};
 auto vertex=[&](int i,mjtNum out[3]){const float*p=m->mesh_vert+3*(base+m->mesh_polyvert[adr+i]);for(int k=0;k<3;++k)out[k]=p[k];};
 vertex(0,a); bool found=false;
 for(int i=1;i+1<count;++i){vertex(i,u);vertex(i+1,v);mju_subFrom3(u,a);mju_subFrom3(v,a);mju_cross(n,u,v);if(mju_norm3(n)>1e-14){found=true;break;}}
 if(!found)return false;mju_normalize3(n);
 for(int i=0;i<m->mesh_vertnum[mesh];++i)for(int k=0;k<3;++k)center[k]+=m->mesh_vert[3*(base+i)+k]/m->mesh_vertnum[mesh];
 offset=mju_dot3(n,a);if(mju_dot3(n,center)>offset){mju_scl3(n,n,-1);offset=-offset;}return true;
}
inline bool hfield_top(const mjModel*m,int geom,const mjtNum p[3],mjtNum &top,mjtNum normal[3]){
 const int id=m->geom_dataid[geom];if(id<0)return false;const mjtNum*size=m->hfield_size+4*id;
 if(std::abs(p[0])>size[0]||std::abs(p[1])>size[1])return false;
 int cols=m->hfield_ncol[id],rows=m->hfield_nrow[id];
 double x=(p[0]/size[0]+1)*.5*(cols-1),y=(p[1]/size[1]+1)*.5*(rows-1);
 int col=std::clamp(int(x),0,cols-2),row=std::clamp(int(y),0,rows-2);x-=col;y-=row;
 const float*h=m->hfield_data+m->hfield_adr[id]+row*cols+col;double dx,dy;
 if(y<=x){dx=h[1]-h[0];dy=h[cols+1]-h[1];top=(h[0]+x*dx+y*dy)*size[2];}
 else{dx=h[cols+1]-h[cols];dy=h[cols]-h[0];top=(h[0]+x*dx+y*dy)*size[2];}
 normal[0]=-dx*(cols-1)*size[2]/(2*size[0]);normal[1]=-dy*(rows-1)*size[2]/(2*size[1]);normal[2]=1;mju_normalize3(normal);return true;
}
inline double asset_surface_error(const mjModel*m,const mjData*d,int geom,const mjtNum p[3]){
 const int type=m->geom_type[geom];int id=m->geom_dataid[geom];
 if(type==mjGEOM_ELLIPSOID){const mjtNum*z=m->geom_size+3*geom;return std::abs(std::sqrt(p[0]*p[0]/(z[0]*z[0])+p[1]*p[1]/(z[1]*z[1])+p[2]*p[2]/(z[2]*z[2]))-1)*std::min({z[0],z[1],z[2]});}
 if(type==mjGEOM_MESH){double near=std::numeric_limits<double>::infinity(),outside=0;for(int i=0;i<m->mesh_polynum[id];++i){mjtNum n[3],off;if(!hull_plane(m,id,m->mesh_polyadr[id]+i,n,off))return near;double gap=mju_dot3(n,p)-off;near=std::min(near,std::abs(gap));outside=std::max(outside,gap);}return std::max(near,outside);}
 if(type==mjGEOM_SDF){const mjpPlugin*plugin=nullptr;mjtGeom kind=mjGEOM_SDF;mjSDF sdf{};sdf.plugin=&plugin;sdf.id=&id;sdf.type=mjSDFTYPE_SINGLE;sdf.geomtype=&kind;return std::abs(mjc_distance(m,d,&sdf,p));}
 if(type==mjGEOM_HFIELD){mjtNum top,n[3];if(!hfield_top(m,geom,p,top,n))return std::numeric_limits<double>::infinity();const mjtNum*z=m->hfield_size+4*id;
  double error=std::min(std::abs(p[2]-top),std::abs(p[2]+z[3]));
  if(p[2]>=-z[3]&&p[2]<=top)error=std::min({error,std::abs(std::abs(p[0])-z[0]),std::abs(std::abs(p[1])-z[1])});return error;}
 return std::numeric_limits<double>::infinity();
}
inline bool asset_normal(const mjModel*m,const mjData*d,int geom,const mjtNum p[3],const mjtNum hint[3],mjtNum n[3]){
 const int type=m->geom_type[geom];int id=m->geom_dataid[geom];mju_zero3(n);
 if(type==mjGEOM_ELLIPSOID){for(int k=0;k<3;++k)n[k]=p[k]/(m->geom_size[3*geom+k]*m->geom_size[3*geom+k]);}
 else if(type==mjGEOM_SDF){const mjpPlugin*plugin=nullptr;mjtGeom kind=mjGEOM_SDF;mjSDF sdf{};sdf.plugin=&plugin;sdf.id=&id;sdf.type=mjSDFTYPE_SINGLE;sdf.geomtype=&kind;mjc_gradient(m,d,&sdf,n,p);}
 else if(type==mjGEOM_MESH){mjtNum nearest[3]={};double distance=std::numeric_limits<double>::infinity();
  for(int i=0;i<m->mesh_polynum[id];++i){mjtNum plane[3],off;if(!hull_plane(m,id,m->mesh_polyadr[id]+i,plane,off))return false;double gap=std::abs(mju_dot3(plane,p)-off);if(gap<distance){distance=gap;mju_copy3(nearest,plane);}if(gap<1e-5)mju_addToScl3(n,plane,std::max(0.0,mju_dot3(plane,hint)));}
  if(mju_norm3(n)==0)mju_copy3(n,nearest);
 }else if(type==mjGEOM_HFIELD){mjtNum top;if(!hfield_top(m,geom,p,top,n))return false;const mjtNum*z=m->hfield_size+4*id;
  double best=std::abs(p[2]-top);if(std::abs(p[2]+z[3])<best){best=std::abs(p[2]+z[3]);mju_zero3(n);n[2]=-1;}
  for(int k=0;k<2;++k)if(std::abs(std::abs(p[k])-z[k])<best){best=std::abs(std::abs(p[k])-z[k]);mju_zero3(n);n[k]=p[k]<0?-1:1;}
 }else return false;
 return std::isfinite(mju_norm3(n))&&mju_normalize3(n)>0;
}
// Certify a separated sphere against the actual 3.16 trilinear octree field.
// A trilinear polynomial is bounded by its eight corner values on a box.
// Subdivision tightens that interval; boxes outside the ball are discarded.
// A budget/ambiguous boundary is UNKNOWN, never a collision-free result.
inline bool sdf_ball_clear(const mjModel*m,int id,const mjtNum c[3],double radius){
 const int root=m->mesh_octadr[id],count=m->mesh_octnum[id];if(root<0||count<=0)return false;
 const mjtNum*rootbox=m->oct_aabb+6*root;const double tolerance=512*std::numeric_limits<double>::epsilon()*std::max({1.0,radius,rootbox[3],rootbox[4],rootbox[5]});
 for(int node=0;node<count;++node){int children=0;for(int k=0;k<8;++k){int child=m->oct_child[8*(root+node)+k];if(child>=0){if(child>=count)return false;++children;}}
  if(children!=0&&children!=8)return false;
  for(int k=0;k<8;++k)if(!std::isfinite(m->oct_coeff[8*(root+node)+k]))return false;
 }
 // Outside the root MuJoCo adds box distance to an interior-clamped
 // field. Its global corner minimum supplies a lower bound even if a
 // boundary leaf is negative. Do not assume the root boundary is positive.
 double global_min=std::numeric_limits<double>::infinity(),domain_lo[3],domain_hi[3];
 for(int k=0;k<3;++k){double lo=rootbox[k]-rootbox[3+k],hi=rootbox[k]+rootbox[3+k];
  domain_lo[k]=std::clamp(c[k]-radius,lo,hi);domain_hi[k]=std::clamp(c[k]+radius,lo,hi);
  if(c[k]-radius<lo)domain_hi[k]=std::max(domain_hi[k],lo+1e-6);
  if(c[k]+radius>hi)domain_lo[k]=std::min(domain_lo[k],hi-1e-6);
 }
 for(int node=0;node<count;++node)if(m->oct_child[8*(root+node)]<0){
  const mjtNum*box=m->oct_aabb+6*(root+node);bool relevant=true;
  for(int k=0;k<3;++k)if(box[k]+box[3+k]<domain_lo[k]||box[k]-box[3+k]>domain_hi[k])relevant=false;
  if(relevant)for(int corner=0;corner<8;++corner)global_min=std::min(global_min,m->oct_coeff[8*(root+node)+corner]);
 }
 double root_distance=0;bool contained=true;
 for(int k=0;k<3;++k){double gap=std::max(0.0,std::abs(c[k]-rootbox[k])-rootbox[3+k]);root_distance+=gap*gap;if(std::abs(c[k]-rootbox[k])+radius>rootbox[3+k])contained=false;}
 root_distance=std::sqrt(root_distance)-radius;
 if(root_distance>0&&global_min+root_distance>tolerance)return true;
 if(!contained&&global_min<=tolerance)return false;
 struct Cell {double lo[3],hi[3],value[8];int depth=0;};
 auto outside=[&](const double*lo,const double*hi){double q=0;for(int k=0;k<3;++k){double v=std::max({lo[k]-c[k],c[k]-hi[k],0.0});q+=v*v;}return q>radius*radius;};
 std::vector<int> nodes{0};std::vector<Cell> cells;int budget=0;
 while(!nodes.empty()){int relative=nodes.back();nodes.pop_back();int absolute=root+relative;const mjtNum*box=m->oct_aabb+6*absolute;Cell cell;
  for(int k=0;k<3;++k){cell.lo[k]=box[k]-box[3+k];cell.hi[k]=box[k]+box[3+k];}if(outside(cell.lo,cell.hi))continue;
  if(m->oct_child[8*absolute]>=0){for(int j=0;j<8;++j){int child=m->oct_child[8*absolute+j];if(child<0||child>=count)return false;nodes.push_back(child);}continue;}
  std::copy_n(m->oct_coeff+8*absolute,8,cell.value);cells.push_back(cell);
 }
 while(!cells.empty()){if(++budget>60000)return false;Cell cell=cells.back();cells.pop_back();if(outside(cell.lo,cell.hi))continue;
  double minimum=*std::min_element(cell.value,cell.value+8);if(minimum>tolerance)continue;
  if(cell.depth>=18)return false;
  int axis=0;for(int k=1;k<3;++k)if(cell.hi[k]-cell.lo[k]>cell.hi[axis]-cell.lo[axis])axis=k;
  double mid=(cell.lo[axis]+cell.hi[axis])*.5;
  for(int side=0;side<2;++side){Cell child=cell;child.depth++;
   if(side)child.lo[axis]=mid;else child.hi[axis]=mid;
   for(int corner=0;corner<8;++corner)if(((corner>>axis)&1)!=side){int opposite=corner^(1<<axis);child.value[corner]=(cell.value[corner]+cell.value[opposite])*.5;}
   cells.push_back(child);
  }
 }
 return true;
}
// SDF collision contacts in 3.16.0 are midsurface optimization points, not
// generally a Godot pair of original surface witnesses. For a sphere, project
// with the native field/gradient and accept only a stationary zero-level point.
// This is a bounded field query, not a temporal sweep or an exact mesh oracle.
inline bool sphere_sdf_contact(const mjModel*m,const mjData*d,int geom,const mjtNum center[3],double radius,double margin,mjPreContact &out,bool &hit){
 hit=false;int id=m->geom_dataid[geom];if(id<0||m->geom_plugin[geom]>=0||m->mesh_octadr[id]<0)return false;
 const mjtNum*mat=d->geom_xmat+9*geom;const mjtNum*pos=d->geom_xpos+3*geom;
 mjtNum offset[3],c[3];mju_sub3(offset,center,pos);mju_mulMatTVec3(c,mat,offset);
 const mjtNum*box=m->geom_aabb+6*geom;double outside=0;
 for(int k=0;k<3;++k){double gap=std::max(0.0,std::abs(c[k]-box[k])-box[k+3]);outside+=gap*gap;}
 // A visual/mesh AABB alone is not a certificate for the interpolated field.
 if(sdf_ball_clear(m,id,c,radius+margin))return true;
 const mjpPlugin*plugin=nullptr;mjtGeom kind=mjGEOM_SDF;mjSDF sdf{};sdf.plugin=&plugin;sdf.id=&id;sdf.type=mjSDFTYPE_SINGLE;sdf.geomtype=&kind;
 mjtNum p[3],gradient[3];mju_copy3(p,c);const double tolerance=1e-7*std::max(1.0,m->geom_rbound[geom]);bool converged=false;
 for(int iteration=0;iteration<48;++iteration){
  double value=mjc_distance(m,d,&sdf,p);mjc_gradient(m,d,&sdf,gradient,p);
  double norm=mju_norm3(gradient);if(!std::isfinite(value)||!std::isfinite(norm)||norm<1e-10)return false;
  if(std::abs(value)>tolerance){double step=value/(norm*norm);if(std::abs(step)*norm>4*std::max(1.0,m->geom_rbound[geom]))return false;mju_addToScl3(p,gradient,-step);continue;}
  mju_scl3(gradient,gradient,1/norm);mjtNum delta[3],tangent[3];mju_sub3(delta,c,p);double along=mju_dot3(delta,gradient);
  mju_addScl3(tangent,delta,gradient,-along);
  if(mju_norm3(tangent)<=tolerance*10){converged=true;break;}
  mju_addTo3(p,tangent);
 }
 if(!converged)return false;
 mjtNum delta[3];mju_sub3(delta,c,p);double gap=mju_dot3(delta,gradient)-radius;
 if(!std::isfinite(gap))return false;
 // Local stationarity is not global nearest distance. Only the interval
 // certificate above may report a miss; an unresolved projection stays UNKNOWN.
 if(gap>margin)return false;
 double center_value=mjc_distance(m,d,&sdf,c);
 if(center_value>tolerance && mju_dot3(delta,gradient)<0)return false;
 mjtNum normal[3],target[3],query[3];mju_mulMatVec3(normal,mat,gradient);
 mju_mulMatVec3(target,mat,p);mju_addTo3(target,pos);mju_addScl3(query,center,normal,-radius);
 out={};out.dist=gap;mju_scl3(out.normal,normal,-1);mju_add3(out.pos,query,target);mju_scl3(out.pos,out.pos,.5);hit=true;return true;
}
inline bool inside(const mjModel*m,const mjData*d,int geom,const mjtNum p[3],bool &valid) {
 valid=true;const int type=m->geom_type[geom];int id=m->geom_dataid[geom];
 if(type==mjGEOM_ELLIPSOID){const mjtNum*s=m->geom_size+3*geom;return p[0]*p[0]/(s[0]*s[0])+p[1]*p[1]/(s[1]*s[1])+p[2]*p[2]/(s[2]*s[2])<1;}
 if(type==mjGEOM_MESH){
  if(id<0||m->mesh_polynum[id]<=0){valid=false;return false;}
  for(int i=0;i<m->mesh_polynum[id];++i){mjtNum n[3],off;if(!hull_plane(m,id,m->mesh_polyadr[id]+i,n,off)){valid=false;return false;}if(mju_dot3(n,p)>=off)return false;}return true;
 }
 if(type==mjGEOM_SDF){
  if(id<0||m->geom_plugin[geom]>=0||m->mesh_octadr[id]<0){valid=false;return false;}
  const mjpPlugin*plugin=nullptr;mjtGeom kind=mjGEOM_SDF;mjSDF sdf{};sdf.plugin=&plugin;sdf.id=&id;sdf.type=mjSDFTYPE_SINGLE;sdf.geomtype=&kind;
  const mjtNum distance=mjc_distance(m,d,&sdf,p);if(!std::isfinite(distance)){valid=false;return false;}return distance<0;
 }
 if(type==mjGEOM_HFIELD){mjtNum top,n[3];const mjtNum*z=m->hfield_size+4*id;return hfield_top(m,geom,p,top,n)&&std::abs(p[0])<z[0]&&std::abs(p[1])<z[1]&&p[2]>-z[3]&&p[2]<top;}
 valid=false;return false;
}
inline mjtNum ray(const mjModel*m,const mjData*d,int geom,const mjtNum origin[3],const mjtNum direction[3],const mjtNum local[3],mjtNum normal[3],bool &valid) {
 valid=true;const int type=m->geom_type[geom];int id=m->geom_dataid[geom];
 if(type==mjGEOM_MESH){
  if(id<0||m->mesh_polynum[id]<=0){valid=false;return -1;}
  mjtNum v[3];mju_mulMatTVec3(v,d->geom_xmat+9*geom,direction);
  mjtNum enter=-std::numeric_limits<mjtNum>::infinity(),leave=std::numeric_limits<mjtNum>::infinity(),entry_normal[3]={},boundary_normal[3]={};bool boundary=false;
  for(int i=0;i<m->mesh_polynum[id];++i){mjtNum n[3],off;if(!hull_plane(m,id,m->mesh_polyadr[id]+i,n,off)){valid=false;return -1;}
   const mjtNum gap=mju_dot3(n,local)-off,speed=mju_dot3(n,v);if(gap==0){boundary=true;mju_copy3(boundary_normal,n);}
   if(speed==0){if(gap>0)return -1;continue;}
   const mjtNum t=-gap/speed;if(speed<0){if(t>enter){enter=t;mju_copy3(entry_normal,n);}}else leave=std::min(leave,t);
   if(enter>leave)return -1;
  }
  if(leave<0)return -1;if(enter<0){if(!boundary)return -1;enter=0;mju_copy3(entry_normal,boundary_normal);}mju_mulMatVec3(normal,d->geom_xmat+9*geom,entry_normal);return enter;
 }
 if(type==mjGEOM_SDF){
  if(id<0||m->geom_plugin[geom]>=0||m->mesh_octadr[id]<0){valid=false;return -1;}
  // mj_raySdf is private in exact 3.16.0. Select only this geom in a shallow
  // model view and neutralize visual alpha/material filtering in that view.
  // The public dispatcher retains the engine's 40-iteration/1e-7 SDF ray rule.
  mjModel view=*m;std::vector<int> groups(m->ngeom,1),materials(m->ngeom,-1);std::vector<float> rgba(4*m->ngeom,1);
  groups[geom]=0;view.geom_group=groups.data();view.geom_matid=materials.data();view.geom_rgba=rgba.data();
  const mjtByte filter[6]={1,0,0,0,0,0};int hit=-1;const mjtNum t=mj_ray(&view,d,origin,direction,filter,1,-1,&hit,normal);
  if(t>=0&&hit!=geom){valid=false;return -1;}return t;
 }
 valid=false;return -1;
}
}
