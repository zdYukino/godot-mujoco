#include "mj_physics_server.h"
#include "mj_sweep.h"
#include "mj_convex_sweep.h"
#include "mj_query_assets.h"
#include "mj_sdf_interval.h"
#include "query_ccd/witness.h"
#include <godot_cpp/classes/physics_server3d_extension_motion_result.hpp>

#include <godot_cpp/core/object.hpp>

#include <algorithm>
#include <array>
#include <cmath>
#include <limits>

namespace godot {
bool MjDirectSpaceState::set_sdf_query_precision_m(double value){
 if(!std::isfinite(value)||value<0||value>.001||(value>0&&value<1e-6))return false;
 sdf_query_precision_m=value;return true;
}
namespace {
thread_local const MjDirectSpaceState *active_query=nullptr;
struct QueryScope {
 const MjDirectSpaceState &state; const MjDirectSpaceState *previous;
 QueryScope(const MjDirectSpaceState &s,const char *kind):state(s),previous(active_query){active_query=&s;s.query_error="";s.query_kind=kind;s.query_details.clear();++s.query_sequence;}
 ~QueryScope(){active_query=previous;}
};
void query_problem(const String &reason){if(active_query&&active_query->query_error.is_empty())active_query->query_error=reason;mj_unsupported(reason.utf8().get_data());}

// The primitive dimensions and poses must come from the compiled model, so
// queries see exactly the geometry used by the MuJoCo simulation.
bool point_inside_geom(int p_type, const mjtNum p_local[3], const mjtNum p_size[3]) {
	switch (p_type) {
		case mjGEOM_BOX:
			return std::abs(p_local[0]) < p_size[0] &&
					std::abs(p_local[1]) < p_size[1] &&
					std::abs(p_local[2]) < p_size[2];
		case mjGEOM_SPHERE:
			return std::hypot(p_local[0], p_local[1], p_local[2]) < p_size[0];
		case mjGEOM_CAPSULE:
			return std::hypot(p_local[0],p_local[1],p_local[2]-std::clamp(p_local[2],-p_size[1],p_size[1])) < p_size[0];
		case mjGEOM_CYLINDER:
			return std::hypot(p_local[0], p_local[1]) < p_size[0] && std::abs(p_local[2]) < p_size[1];
		case mjGEOM_PLANE:
			// WorldBoundaryShape3D occupies the negative half-space.
			return p_local[2] < 0;
		default:
			return false;
	}
}

mjtNum intersect_geom(int p_type, const mjtNum p_position[3], const mjtNum p_matrix[9],
		const mjtNum p_size[3], const mjtNum p_from[3], const mjtNum p_direction[3],
		const mjtNum p_local_from[3], mjtNum r_normal[3]) {
	if (p_type == mjGEOM_PLANE) {
		// mju_rayGeom's plane query is for a rendered, front-facing rectangle.
		// A Godot world boundary is infinite, and a ray starting on its surface
		// can hit at t = 0 in either direction. The inside policy is handled by
		// the caller before this test, independently of hit_back_faces.
		const mjtNum denominator = p_matrix[2] * p_direction[0] +
				p_matrix[5] * p_direction[1] + p_matrix[8] * p_direction[2];
		if (denominator == 0) {
			return -1;
		}
		r_normal[0] = p_matrix[2];
		r_normal[1] = p_matrix[5];
		r_normal[2] = p_matrix[8];
		return -p_local_from[2] / denominator;
	}
	return mju_rayGeom(p_position, p_matrix, p_size, p_from, p_direction, p_type, r_normal);
}


// All native queries share ownership validation and query-mask semantics.
MjBody *query_body(MjDirectSpaceState &state, MjSpace &space, int geom, uint32_t mask, bool pick = false, const MjBody *moving = nullptr) {
 const auto &owner = space.geom_owners[geom];
 auto *body = state.server->body(owner.first);
 const bool imported=!body;
 if(imported){auto found=space.imported_query_owners.find(geom);if(found==space.imported_query_owners.end()||!space.imported.count(owner.first.get_id()))return nullptr;body=found->second.get();}
 if (!body || state.server->pending_free.count(owner.first.get_id()) || body->space != state.rid ||
     !(body->layer & mask) || (pick && !body->ray_pickable) ||
     (!moving && state.is_body_excluded_from_query(owner.first))) return nullptr;
 if(!imported && (owner.second<0 || size_t(owner.second)>=body->shapes.size() || body->shapes[owner.second].disabled ||
     !state.server->shape(body->shapes[owner.second].shape) ||
     state.server->pending_free.count(body->shapes[owner.second].shape.get_id())))return nullptr;
 if(moving && (body==moving || moving->exceptions.count(body->rid.get_id()) || body->exceptions.count(moving->rid.get_id()) ||
     state.server->body_test_motion_is_excluding_body(body->rid) ||
     (body->object_id && state.server->body_test_motion_is_excluding_object(body->object_id))))return nullptr;
 return body;
}
MjSpace *query_space(MjDirectSpaceState &state, uint32_t mask, bool bodies, bool areas) {
 if((!bodies&&!areas)||!mask)return nullptr;
 if(!state.server||state.server->pending_free.count(state.rid.get_id())){query_problem("invalid or freed query space");return nullptr;}
 auto *space = state.server->space(state.rid);
 if (!space || !state.server->rebuild(*space) || !space->model || !space->data ||
     space->geom_owners.size() != size_t(space->model->ngeom)){query_problem("query space rebuild or ownership failed");return nullptr;}
 return space;
}
bool primitive(int type) {
 return type == mjGEOM_BOX || type == mjGEOM_SPHERE || type == mjGEOM_CYLINDER || type == mjGEOM_CAPSULE || type == mjGEOM_PLANE;
}
PhysicsServer3DExtensionShapeResult shape_result(MjBody &body, int shape) {
 PhysicsServer3DExtensionShapeResult result{};
 result.rid = body.rid; result.collider_id = ObjectID(body.object_id); result.shape = shape;
 Object *object = body.object_id ? ObjectDB::get_instance(body.object_id) : nullptr;
 result.collider = object ? reinterpret_cast<Object *>(object->_owner) : nullptr;
 return result;
}
struct AreaQueryGeom {
 std::shared_ptr<MjBody> owner;int shape=0,type=0;mjtNum size[3]={},position[3]={},matrix[9]={};
};
std::vector<AreaQueryGeom> area_query_geometries(MjDirectSpaceState &state,uint32_t mask,bool pick,bool &valid){
 valid=true;std::vector<AreaQueryGeom> result;
 for(const auto &entry:state.server->areas){const auto &area=*entry.second;
  if(area.space!=state.rid||state.server->pending_free.count(area.rid.get_id())||!(area.layer&mask)||(pick&&!area.ray_pickable)||state.is_body_excluded_from_query(area.rid))continue;
  for(size_t index=0;index<area.shapes.size();++index){const auto &instance=area.shapes[index];auto*shape=state.server->shape(instance.shape);
   if(instance.disabled||!shape||state.server->pending_free.count(instance.shape.get_id()))continue;
   Transform3D pose=area.transform*instance.transform;
   if(!pose.is_finite()||!pose.basis.is_orthogonal()||!pose.basis.get_scale().is_equal_approx(Vector3(1,1,1))||pose.basis.determinant()<=0){query_problem("Area query target transform is invalid");valid=false;return {};}
   AreaQueryGeom geom;geom.shape=int(index);
   if(shape->type==PhysicsServer3D::SHAPE_BOX){Vector3 size=shape->data;geom.type=mjGEOM_BOX;geom.size[0]=size.x;geom.size[1]=size.z;geom.size[2]=size.y;}
   else if(shape->type==PhysicsServer3D::SHAPE_SPHERE){geom.type=mjGEOM_SPHERE;geom.size[0]=double(shape->data);}
   else if(shape->type==PhysicsServer3D::SHAPE_CYLINDER||shape->type==PhysicsServer3D::SHAPE_CAPSULE){Dictionary sizes=shape->data;geom.size[0]=double(sizes["radius"]);geom.size[1]=double(sizes["height"])*.5;
    if(shape->type==PhysicsServer3D::SHAPE_CAPSULE){geom.size[1]-=geom.size[0];geom.type=geom.size[1]==0?mjGEOM_SPHERE:mjGEOM_CAPSULE;}else geom.type=mjGEOM_CYLINDER;
   }else{query_problem("Area query shape unsupported by native Area contract");valid=false;return {};}
   Vector3 position=godot_to_mj(pose.origin);Basis basis=godot_to_mj(pose.basis);
   for(int k=0;k<3;++k){geom.position[k]=position[k];for(int j=0;j<3;++j)geom.matrix[3*k+j]=basis[k][j];}
   geom.owner=std::make_shared<MjBody>();geom.owner->rid=area.rid;geom.owner->space=area.space;geom.owner->object_id=area.object_id;geom.owner->mode=PhysicsServer3D::BODY_MODE_STATIC;geom.owner->layer=area.layer;geom.owner->ray_pickable=area.ray_pickable;
   result.push_back(std::move(geom));
  }
 }
 return result;
}
struct Overlap {
 MjBody *body; int shape; mjPreContact contact; bool reversed; Vector3 target_normal;
 std::shared_ptr<MjBody> owned_area;
};
Vector3 contact_point(const Overlap &hit, bool query);

gmj_sweep::Vec support(int type, const mjtNum *size, const mjtNum *matrix, gmj_sweep::Vec n);
// Analytic signed-distance magnitude to the original primitive surface. This
// checks actual ownership, not just whether a narrowphase produced a contact.
double surface_error(const mjModel *model, const mjData *data, int geom, const mjtNum *point) {
 mjtNum offset[3],p[3]; mju_sub3(offset,point,data->geom_xpos+3*geom);
 mju_mulMatTVec3(p,data->geom_xmat+9*geom,offset);
 const mjtNum *size=model->geom_size+3*geom;
 if(!primitive(model->geom_type[geom]))return gmj_query::asset_surface_error(model,data,geom,p);
 switch(model->geom_type[geom]) {
 case mjGEOM_SPHERE:return std::abs(mju_norm3(p)-size[0]);
 case mjGEOM_PLANE:return std::abs(p[2]);
 case mjGEOM_CAPSULE:return std::abs(std::hypot(p[0],p[1],p[2]-std::clamp(p[2],-size[1],size[1]))-size[0]);
 case mjGEOM_CYLINDER: {
   double a=std::hypot(p[0],p[1])-size[0],b=std::abs(p[2])-size[1];
   return std::abs(std::hypot(std::max(a,0.0),std::max(b,0.0))+std::min(std::max(a,b),0.0));
 }
 default: {
   double a=std::abs(p[0])-size[0],b=std::abs(p[1])-size[1],c=std::abs(p[2])-size[2];
   return std::abs(std::hypot(std::max(a,0.0),std::max(b,0.0),std::max(c,0.0))+std::min(std::max({a,b,c}),0.0));
 }
 }
}
bool valid_witnesses(const mjModel *model, const mjData *data, int a, int b, const mjPreContact &c) {
 if(!std::isfinite(c.dist) || !std::isfinite(mju_norm3(c.normal)) || std::abs(mju_norm3(c.normal)-1)>1e-6) return false;
 mjtNum p[3],q[3]; mju_addScl3(p,c.pos,c.normal,-.5*c.dist);mju_addScl3(q,c.pos,c.normal,.5*c.dist);
 const double ea=surface_error(model,data,a,p), eb=surface_error(model,data,b,q);
 return std::isfinite(ea) && std::isfinite(eb) &&
     ea<=(primitive(model->geom_type[a])?1e-6:1e-5)*std::max(1.0,model->geom_rbound[a]) && eb<=(primitive(model->geom_type[b])?1e-6:1e-5)*std::max(1.0,model->geom_rbound[b]);
}
// Deep MPR portal displacements need not equal a target feature normal.
// Derive rest normals from the target's actual surface/normal cone, keeping
// the independently reconstructed witness pair and penetration depth intact.
Vector3 witness_normal(const mjModel *model,const mjData *data,int geom,const mjtNum *point,const mjtNum *hint) {
 mjtNum offset[3],p[3],h[3],n[3]={},world[3];
 const mjtNum *mat=data->geom_xmat+9*geom,*size=model->geom_size+3*geom;
 mju_sub3(offset,point,data->geom_xpos+3*geom);mju_mulMatTVec3(p,mat,offset);mju_mulMatTVec3(h,mat,hint);
 double tolerance=1e-6*std::max(1e-8,model->geom_rbound[geom]);
 int type=model->geom_type[geom];
 if(!primitive(type)){if(!gmj_query::asset_normal(model,data,geom,p,h,n))return Vector3();mju_mulMatVec3(world,mat,n);return mj_to_godot(Vector3(world[0],world[1],world[2])).normalized();}
 if(type==mjGEOM_SPHERE) mju_copy3(n,p);
 else if(type==mjGEOM_CAPSULE) {mju_copy3(n,p);n[2]-=std::clamp(p[2],-size[1],size[1]);}
 else if(type==mjGEOM_PLANE) n[2]=1;
 else if(type==mjGEOM_BOX) {
   int nearest=0;
   for(int i=0;i<3;++i) {
     if(std::abs(std::abs(p[i])-size[i])<std::abs(std::abs(p[nearest])-size[nearest])) nearest=i;
     if(std::abs(std::abs(p[i])-size[i])<=tolerance) n[i]=(p[i]<0?-1:1)*std::max(0.0,h[i]*(p[i]<0?-1:1));
   }
   if(mju_norm3(n)==0)n[nearest]=p[nearest]<0?-1:1;
 } else {
   double radial=std::hypot(p[0],p[1]), side=std::abs(radial-size[0]), cap=std::abs(std::abs(p[2])-size[1]);
   double x=radial?p[0]/radial:1,y=radial?p[1]/radial:0,z=p[2]<0?-1:1;
   if(side<=tolerance) {double weight=std::max(0.0,h[0]*x+h[1]*y);n[0]=weight*x;n[1]=weight*y;}
   if(cap<=tolerance) n[2]=z*std::max(0.0,z*h[2]);
   if(mju_norm3(n)==0) {if(side<=cap){n[0]=x;n[1]=y;}else n[2]=z;}
 }
 mju_normalize3(n);mju_mulMatVec3(world,mat,n);
 return mj_to_godot(Vector3(world[0],world[1],world[2])).normalized();
}
struct SupportGeom { const mjModel *model; const mjData *data; int geom; const mjtNum *origin; };
void primitive_support(const void *object, const ccd_vec3_t *direction, ccd_vec3_t *result) {
 const auto &g=*static_cast<const SupportGeom *>(object);
 auto v=support(g.model->geom_type[g.geom],g.model->geom_size+3*g.geom,g.data->geom_xmat+9*g.geom,
     {direction->v[0],direction->v[1],direction->v[2]});
 const mjtNum *p=g.data->geom_xpos+3*g.geom;
 ccdVec3Set(result,v.x+(p[0]-g.origin[0]),v.y+(p[1]-g.origin[1]),v.z+(p[2]-g.origin[2]));
}
void primitive_center(const void *object, ccd_vec3_t *result) {
 const auto &g=*static_cast<const SupportGeom *>(object);
 mju_sub3(result->v,g.data->geom_xpos+3*g.geom,g.origin);
 if(g.geom==0) {
   // MPR permits any strictly interior reference point. A noncentral query
   // reference avoids the coincident-center segment shortcut without moving
   // either physical shape or any of its support vertices.
   const mjtNum *s=g.model->geom_size;
   mjtNum local[3],offset[3];
   if(g.model->geom_type[0]==mjGEOM_BOX) {local[0]=.1*s[0];local[1]=.2*s[1];local[2]=.15*s[2];}
   else {local[0]=.1*s[0];local[1]=.2*s[0];local[2]=.15*(g.model->geom_type[0]==mjGEOM_SPHERE?s[0]:s[1]);}
   mju_mulMatVec3(offset,g.data->geom_xmat,local);mju_addTo3(result->v,offset);
 }
}
bool primitive_witness(const mjModel *model, const mjData *data, mjPreContact &contact) {
 const mjtNum *origin=data->geom_xpos;
 SupportGeom a{model,data,0,origin},b{model,data,1,origin};
 ccd_t options{}; options.support1=options.support2=primitive_support;
 options.center1=options.center2=primitive_center; options.max_iterations=1000;
 options.mpr_tolerance=1e-10*std::max({1.0,model->geom_rbound[0],model->geom_rbound[1]});
 ccd_real_t depth; ccd_vec3_t normal,position,p,q;
 if(gmj_ccdMPRWitness(&a,&b,&options,&depth,&normal,&position,&p,&q)!=0 || !(depth>0)) return false;
 contact={}; contact.dist=-depth; mju_copy3(contact.normal,normal.v);
 mju_add3(contact.pos,position.v,origin);
 return valid_witnesses(model,data,0,1,contact);
}
struct ConvexQueryObject {
 int type=0,mesh=-1;const mjModel*assets=nullptr;mjtNum size[3]={},matrix[9]={};gmj_sweep::Vec position{};double margin=0;
 std::vector<gmj_sweep::Vec> vertices;
 gmj_sweep::Vec point(gmj_sweep::Vec direction) const {
  using gmj_sweep::Vec;mjtNum n[3]={direction.x,direction.y,direction.z},local[3],p[3]={},world[3];mju_mulMatTVec3(local,matrix,n);
  if(type==mjGEOM_MESH&&!vertices.empty()){double best=-std::numeric_limits<double>::infinity();for(auto v:vertices){double d=local[0]*v.x+local[1]*v.y+local[2]*v.z;if(d>best){best=d;p[0]=v.x;p[1]=v.y;p[2]=v.z;}}}
  else if(type==mjGEOM_MESH){double best=-std::numeric_limits<double>::infinity();for(int i=0;i<assets->mesh_vertnum[mesh];++i){const float*v=assets->mesh_vert+3*(assets->mesh_vertadr[mesh]+i);double d=local[0]*v[0]+local[1]*v[1]+local[2]*v[2];if(d>best){best=d;for(int k=0;k<3;++k)p[k]=v[k];}}}
  else if(type==mjGEOM_ELLIPSOID){double length=std::hypot(size[0]*local[0],size[1]*local[1],size[2]*local[2]);if(length)for(int k=0;k<3;++k)p[k]=size[k]*size[k]*local[k]/length;else p[0]=size[0];}
  else {Vec v=support(type,size,matrix,direction);double len=direction.length();return position+v+(len?direction*(margin/len):Vec{});}
  mju_mulMatVec3(world,matrix,p);Vec result=position+Vec{world[0],world[1],world[2]};double len=direction.length();return result+(len?direction*(margin/len):Vec{});
 }
 gmj_sweep::Vec interior(bool query) const {
  mjtNum local[3]={},world[3];
  if(type==mjGEOM_MESH&&!vertices.empty()){for(auto v:vertices){local[0]+=v.x/vertices.size();local[1]+=v.y/vertices.size();local[2]+=v.z/vertices.size();}}
  else if(type==mjGEOM_MESH){for(int i=0;i<assets->mesh_vertnum[mesh];++i)for(int k=0;k<3;++k)local[k]+=assets->mesh_vert[3*(assets->mesh_vertadr[mesh]+i)+k]/assets->mesh_vertnum[mesh];}
  else if(query){local[0]=.1*size[0];local[1]=.2*(type==mjGEOM_BOX?size[1]:size[0]);local[2]=.15*(type==mjGEOM_SPHERE?size[0]:size[1]);}
  mju_mulMatVec3(world,matrix,local);return position+gmj_sweep::Vec{world[0],world[1],world[2]};
 }
};
struct ConvexMpr {const ConvexQueryObject*object;bool query;};
void convex_mpr_support(const void*ptr,const ccd_vec3_t*direction,ccd_vec3_t*out){
 const auto&o=*static_cast<const ConvexMpr*>(ptr);auto p=o.object->point({direction->v[0],direction->v[1],direction->v[2]});ccdVec3Set(out,p.x,p.y,p.z);
}
void convex_mpr_center(const void*ptr,ccd_vec3_t*out){
 const auto&o=*static_cast<const ConvexMpr*>(ptr);auto p=o.object->interior(o.query);ccdVec3Set(out,p.x,p.y,p.z);
}
gmj_convex::Distance convex_distance(const ConvexQueryObject&a,const ConvexQueryObject&b){
 ConvexMpr ma{&a,true},mb{&b,false};
 auto penetration=[&](){
  ccd_t options{};options.support1=options.support2=convex_mpr_support;options.center1=options.center2=convex_mpr_center;
  options.max_iterations=1000;options.mpr_tolerance=1e-12*std::max({1.0,mju_norm3(a.size),mju_norm3(b.size)});
  ccd_real_t depth=0;ccd_vec3_t normal{},position{},p{},q{};
  int rc=gmj_ccdMPRWitness(&ma,&mb,&options,&depth,&normal,&position,&p,&q);
  gmj_convex::Penetration result;result.valid=true;result.inside=rc==0&&depth>0;
  if(result.inside){result.point={q.v[0],q.v[1],q.v[2]};result.normal={-normal.v[0],-normal.v[1],-normal.v[2]};}
  return result;
 };
 return gmj_convex::distance([&](auto n){return a.point(n);},[&](auto n){return b.point(n);},a.interior(false)-b.interior(false),penetration);
}
ConvexQueryObject convex_object(const mjModel*m,const mjData*d,int geom,gmj_sweep::Vec origin={},double margin=0){
 ConvexQueryObject result;result.type=m->geom_type[geom];result.assets=m;result.mesh=m->geom_dataid[geom];result.margin=margin;
 mju_copy3(result.size,m->geom_size+3*geom);mju_copy(result.matrix,d->geom_xmat+9*geom,9);const mjtNum*p=d->geom_xpos+3*geom;result.position=gmj_sweep::Vec{p[0],p[1],p[2]}-origin;return result;
}
bool convex_mpr_contact(const ConvexQueryObject&a,const ConvexQueryObject&b,gmj_sweep::Vec origin,mjPreContact&out){
 ConvexMpr ma{&a,true},mb{&b,false};ccd_t options{};options.support1=options.support2=convex_mpr_support;options.center1=options.center2=convex_mpr_center;options.max_iterations=1000;options.mpr_tolerance=1e-12;
 ccd_real_t depth=0;ccd_vec3_t normal{},position{},p{},q{};
 if(gmj_ccdMPRWitness(&ma,&mb,&options,&depth,&normal,&position,&p,&q)!=0||!(depth>0))return false;
 out={};out.dist=-depth;mju_copy3(out.normal,normal.v);out.pos[0]=(p.v[0]+q.v[0])*.5+origin.x;out.pos[1]=(p.v[1]+q.v[1])*.5+origin.y;out.pos[2]=(p.v[2]+q.v[2])*.5+origin.z;return true;
}
// -1 unknown, 0 certified clear, 1 physical original-surface witness.
int convex_pair_contact(const ConvexQueryObject&a,const ConvexQueryObject&b,gmj_sweep::Vec origin,double margin,mjPreContact&out){
 if(convex_mpr_contact(a,b,origin,out))return 1;
 auto distance=convex_distance(a,b);if(!distance.valid)return -1;
 if(distance.lower>margin)return 0;
 if(distance.upper>0&&distance.upper<=margin){auto p=distance.query_point+origin,q=distance.point+origin;auto n=(q-p)*(1/distance.upper);out={};out.dist=distance.upper;out.normal[0]=n.x;out.normal[1]=n.y;out.normal[2]=n.z;auto mid=(p+q)*.5;out.pos[0]=mid.x;out.pos[1]=mid.y;out.pos[2]=mid.z;return 1;}
 return -1;
}
std::vector<ConvexQueryObject> hfield_prisms(const ConvexQueryObject&target,const mjModel*m,int geom){
 using gmj_sweep::Vec;std::vector<ConvexQueryObject> result;int id=m->geom_dataid[geom],rows=m->hfield_nrow[id],cols=m->hfield_ncol[id];if((rows-1)*(cols-1)>2048)return result;
 const mjtNum*z=m->hfield_size+4*id;const float*h=m->hfield_data+m->hfield_adr[id];
 for(int row=0;row<rows-1;++row)for(int col=0;col<cols-1;++col){
  Vec v[4];int dc[4]={0,1,1,0},dr[4]={0,0,1,1};
  for(int j=0;j<4;++j)v[j]={-z[0]+2*z[0]*(col+dc[j])/(cols-1),-z[1]+2*z[1]*(row+dr[j])/(rows-1),h[(row+dr[j])*cols+col+dc[j]]*z[2]};
  for(auto triangle:{std::array<int,3>{0,1,2},std::array<int,3>{0,2,3}}){auto prism=target;prism.type=mjGEOM_MESH;prism.assets=nullptr;
   for(int index:triangle)prism.vertices.push_back(v[index]);for(int index:triangle)prism.vertices.push_back({v[index].x,v[index].y,-z[3]});result.push_back(std::move(prism));
  }
 }
 return result;
}
std::shared_ptr<gmj_sdf::Field> sdf_field_for(MjSpace&space,int geom){
 int mesh=space.model->geom_dataid[geom];auto found=space.query_sdf_fields.find(mesh);if(found!=space.query_sdf_fields.end()){if(active_query)active_query->query_details["sdf_cache_hits"]=int(active_query->query_details.get("sdf_cache_hits",0))+1;return found->second;}
 auto field=std::make_shared<gmj_sdf::Field>(space.model,mesh);space.query_sdf_fields[mesh]=field;
 if(active_query){active_query->query_details["sdf_cold_build_seconds"]=double(active_query->query_details.get("sdf_cold_build_seconds",0.0))+field->build_seconds;active_query->query_details["sdf_cache_misses"]=int(active_query->query_details.get("sdf_cache_misses",0))+1;}return field;
}
double sdf_geometry_error(const ConvexQueryObject&q,const mjData*d,int geom,gmj_sweep::Vec motion={},double lo=0,double hi=0){
 using namespace gmj_sdf;Number scale{1,1};
 for(double value:{q.position.x,q.position.y,q.position.z})scale=add(scale,{std::abs(value),std::abs(value)});
 for(int k=0;k<3;++k){double value=std::abs(d->geom_xpos[3*geom+k]),size=std::abs(q.size[k]);scale=add(scale,{value,value});scale=add(scale,mul({4,4},{size,size}));}
 scale=add(scale,mul({3,3},{q.margin,q.margin}));Number travel{0,0};
 for(double v:{motion.x,motion.y,motion.z})travel=add(travel,{std::abs(v),std::abs(v)});
 double time=std::max(std::abs(lo),std::abs(hi));scale=add(scale,mul({time,time},travel));
 const double u=std::numeric_limits<double>::epsilon(),gamma=up((256*u)/down(1-256*u));return mul({gamma,gamma},scale).hi;
}
bool sdf_certification_domain(const ConvexQueryObject&q,const mjData*d,int geom,gmj_sweep::Vec motion={}){
 const double minimum=double(float(1e-5)),world_limit=1048576;
 if(q.type==mjGEOM_PLANE||q.size[0]<minimum||q.margin>1024)return false;
 if(q.type==mjGEOM_BOX&&(q.size[1]<minimum||q.size[2]<minimum))return false;
 if(q.type==mjGEOM_CYLINDER&&q.size[1]<minimum)return false;
 for(double size:q.size)if(!std::isfinite(size)||size<0||size>1024)return false;
 if(q.type==mjGEOM_CAPSULE&&q.size[0]+q.size[1]>1024)return false;
 for(int k=0;k<3;++k)if(!std::isfinite(d->geom_xpos[3*geom+k])||std::abs(d->geom_xpos[3*geom+k])>1024)return false;
 double minimum_feature=q.size[0];if(q.type==mjGEOM_BOX)minimum_feature=std::min({q.size[0],q.size[1],q.size[2]});else if(q.type==mjGEOM_CYLINDER)minimum_feature=std::min(q.size[0],q.size[1]);
 if(4*std::sqrt(3.0)*sdf_geometry_error(q,d,geom,motion,0,1)>=minimum_feature)return false;
 auto end=q.position+motion;
 for(auto p:{q.position,end})if(!std::isfinite(p.x)||!std::isfinite(p.y)||!std::isfinite(p.z)||std::max({std::abs(p.x),std::abs(p.y),std::abs(p.z)})>world_limit)return false;
 return true;
}
gmj_convex::Support sdf_local_support(const ConvexQueryObject&query,const mjData*d,int geom){
 return [&query,d,geom](gmj_sweep::Vec n){mjtNum local[3]={n.x,n.y,n.z},world[3],point[3],result[3];const mjtNum*matrix=d->geom_xmat+9*geom;mju_mulMatVec3(world,matrix,local);
  auto p=query.point({world[0],world[1],world[2]});point[0]=p.x-d->geom_xpos[3*geom];point[1]=p.y-d->geom_xpos[3*geom+1];point[2]=p.z-d->geom_xpos[3*geom+2];mju_mulMatTVec3(result,matrix,point);return gmj_sweep::Vec{result[0],result[1],result[2]};
 };
}
double primitive_distance_to_volume(const ConvexQueryObject&q,gmj_sweep::Vec world){
 mjtNum p[3]={world.x-q.position.x,world.y-q.position.y,world.z-q.position.z},local[3];mju_mulMatTVec3(local,q.matrix,p);
 gmj_sweep::Kind kind=q.type==mjGEOM_SPHERE?gmj_sweep::Kind::sphere:q.type==mjGEOM_BOX?gmj_sweep::Kind::box:q.type==mjGEOM_CAPSULE?gmj_sweep::Kind::capsule:gmj_sweep::Kind::cylinder;
 auto closest=gmj_sweep::closest({kind,{q.size[0],q.size[1],q.size[2]}},{local[0],local[1],local[2]});
 return (gmj_sweep::Vec{local[0],local[1],local[2]}-closest).length();
}
bool far_surface_pair(const ConvexQueryObject&query,gmj_sweep::Vec target,mjPreContact&out){
 using gmj_sweep::Vec;Vec direction=query.position-target;double length=direction.length();if(!(length>0))return false;direction=direction*(1/length);
 mjtNum position[3]={query.position.x,query.position.y,query.position.z},ray[3]={direction.x,direction.y,direction.z},normal[3];
 double distance=mju_rayGeom(position,query.matrix,query.size,position,ray,query.type,normal);if(!(distance>0)||!std::isfinite(distance))return false;
 Vec point=query.position+direction*distance,delta=target-point;double gap=-delta.length();if(!(gap<0))return false;Vec n=delta*(1/gap),mid=(point+target)*.5;
 out={};out.dist=gap;out.pos[0]=mid.x;out.pos[1]=mid.y;out.pos[2]=mid.z;out.normal[0]=n.x;out.normal[1]=n.y;out.normal[2]=n.z;return true;
}
bool hfield_contained_contact(const ConvexQueryObject&query,const mjModel*m,const mjData*d,int geom,mjPreContact&out){
 const mjtNum*matrix=d->geom_xmat+9*geom,*position=d->geom_xpos+3*geom;
 mjtNum offset[3]={query.position.x-position[0],query.position.y-position[1],query.position.z-position[2]},p[3],n[3],top=0;mju_mulMatTVec3(p,matrix,offset);
 int id=m->geom_dataid[geom];if(!gmj_query::hfield_top(m,geom,p,top,n)||!(p[2]>-m->hfield_size[4*id+3]&&p[2]<top))return false;
 p[2]=top;mjtNum world[3];mju_mulMatVec3(world,matrix,p);mju_addTo3(world,position);return far_surface_pair(query,{world[0],world[1],world[2]},out);
}
// Returns only a certified original-surface pair and an actual negative-field
// point inside the (once margin-inflated) query. Local projection cannot certify
// separation or global minimum penetration; interval bounds provide separation.
bool sdf_contact(const ConvexQueryObject&query,const mjModel*m,const mjData*d,int geom,mjPreContact&out,bool&strict,gmj_sweep::Vec*target_normal=nullptr,double geometry_error=0,bool refine_candidate=false){
 refine_candidate=refine_candidate||(active_query&&active_query->sdf_upper_refinement);
 using gmj_sweep::Vec;strict=false;int id=m->geom_dataid[geom];if(id<0||m->geom_plugin[geom]>=0||query.type==mjGEOM_PLANE)return false;
 const mjpPlugin*plugin=nullptr;mjtGeom kind=mjGEOM_SDF;mjSDF sdf{};sdf.plugin=&plugin;sdf.id=&id;sdf.type=mjSDFTYPE_SINGLE;sdf.geomtype=&kind;
 const mjtNum*matrix=d->geom_xmat+9*geom,*position=d->geom_xpos+3*geom;
 mjtNum center_offset[3]={query.position.x-position[0],query.position.y-position[1],query.position.z-position[2]},center_local[3];mju_mulMatTVec3(center_local,matrix,center_offset);
 bool center_negative=std::max({std::abs(center_local[0]),std::abs(center_local[1]),std::abs(center_local[2])})<=4000000&&mjc_distance(m,d,&sdf,center_local)<-1e-11*std::max(1.0,m->geom_rbound[geom]);
 std::vector<Vec> seeds{query.position};for(auto n:{Vec{1,0,0},Vec{-1,0,0},Vec{0,1,0},Vec{0,-1,0},Vec{0,0,1},Vec{0,0,-1}}){auto physical=query;physical.margin=0;seeds.push_back(physical.point(n));}
 double scale=std::max(1.0,m->geom_rbound[geom]),tolerance=1e-11*scale;
 seeds.reserve(32);
 for(size_t seed_index=0;seed_index<seeds.size()&&seed_index<32;++seed_index){auto seed=seeds[seed_index];mjtNum offset[3]={seed.x-position[0],seed.y-position[1],seed.z-position[2]},p[3],gradient[3];mju_mulMatTVec3(p,matrix,offset);
  if(std::max({std::abs(p[0]),std::abs(p[1]),std::abs(p[2])})>4000000)continue;
  bool converged=false;
  for(int i=0;i<64;++i){double value=mjc_distance(m,d,&sdf,p);mjc_gradient(m,d,&sdf,gradient,p);double norm=mju_norm3(gradient);
   if(!std::isfinite(value)||!std::isfinite(norm)||norm<1e-12)break;
   if(std::abs(value)<=tolerance){mju_scl3(gradient,gradient,1/norm);converged=true;break;}
   if(std::abs(value)/norm>4*scale)break;mju_addToScl3(p,gradient,-value/(norm*norm));
  }
  if(!converged)continue;
  // Optional nearest-surface candidate refinement. This is local optimization,
  // never a separation/global-nearest certificate: the ordinary actual-field
  // interior and original-surface witness checks below remain mandatory.
  if(refine_candidate&&query.type==mjGEOM_SPHERE){
   for(int iteration=0;iteration<12;++iteration){
    mjtNum delta[3],tangent[3];mju_sub3(delta,center_local,p);
    double objective=mju_dot3(delta,delta),along=mju_dot3(delta,gradient);
    mju_addScl3(tangent,delta,gradient,-along);
    if(mju_norm3(tangent)<=tolerance)break;bool improved=false;
    for(double step:{1.,.5,.25}){
     mjtNum candidate[3],candidate_gradient[3];mju_addScl3(candidate,p,tangent,step);bool root=false;
     for(int project=0;project<12;++project){
      double value=mjc_distance(m,d,&sdf,candidate);mjc_gradient(m,d,&sdf,candidate_gradient,candidate);
      double norm=mju_norm3(candidate_gradient);if(!std::isfinite(value)||!std::isfinite(norm)||norm<1e-12)break;
      if(std::abs(value)<=tolerance){mju_scl3(candidate_gradient,candidate_gradient,1/norm);root=true;break;}
      if(std::abs(value)/norm>4*scale)break;mju_addToScl3(candidate,candidate_gradient,-value/(norm*norm));
     }
     mjtNum candidate_delta[3];mju_sub3(candidate_delta,center_local,candidate);
     if(root&&mju_dot3(candidate_delta,candidate_delta)<objective-1e-15*std::max(1.,objective)){
      mju_copy3(p,candidate);mju_copy3(gradient,candidate_gradient);improved=true;break;
     }
    }
    if(!improved)break;
   }
  }
  mjtNum target_raw[3],normal_raw[3];mju_mulMatVec3(target_raw,matrix,p);mju_addTo3(target_raw,position);mju_mulMatVec3(normal_raw,matrix,gradient);
  Vec target{target_raw[0],target_raw[1],target_raw[2]},normal{normal_raw[0],normal_raw[1],normal_raw[2]};
  // Seed the actual support feature in the field-gradient direction.
  // Global axes alone miss a tilted cylinder rim at first plane contact.
  auto physical=query;physical.margin=0;Vec feature=physical.point(normal*-1);bool duplicate=false;
  for(auto existing:seeds)if((existing-feature).length()<=tolerance)duplicate=true;
  if(!duplicate&&seeds.size()<32)seeds.push_back(feature);

  if(center_negative&&far_surface_pair(query,target,out)){strict=true;if(target_normal)*target_normal=normal;return true;}
  mjtNum relative[3]={target.x-query.position.x,target.y-query.position.y,target.z-query.position.z},local[3];mju_mulMatTVec3(local,query.matrix,relative);Vec q;double gap=0;
  if(point_inside_geom(query.type,local,query.size)){
   mjtNum query_position[3]={query.position.x,query.position.y,query.position.z},direction[3]={-normal.x,-normal.y,-normal.z},query_normal[3];
   double distance=mju_rayGeom(query_position,query.matrix,query.size,target_raw,direction,query.type,query_normal);
   if(!(distance>0)||!std::isfinite(distance))continue;q=target-normal*distance;gap=-distance;
  }else{
   gmj_sweep::Kind k=query.type==mjGEOM_SPHERE?gmj_sweep::Kind::sphere:query.type==mjGEOM_BOX?gmj_sweep::Kind::box:query.type==mjGEOM_CAPSULE?gmj_sweep::Kind::capsule:gmj_sweep::Kind::cylinder;
   auto closest=gmj_sweep::closest({k,{query.size[0],query.size[1],query.size[2]}},{local[0],local[1],local[2]});mjtNum qp[3]={closest.x,closest.y,closest.z},world[3];mju_mulMatVec3(world,query.matrix,qp);q=query.position+Vec{world[0],world[1],world[2]};gap=(target-q).length();if(gap>query.margin)continue;
  }
  // Existential intersection proof, independent of local nearest-point claims.
  bool proof=false;
  for(double step:{1e-9*scale,1e-8*scale,1e-7*scale}){Vec witness=target-normal*step;double dist=primitive_distance_to_volume(query,witness);
   mjtNum wo[3]={witness.x-position[0],witness.y-position[1],witness.z-position[2]},x[3];mju_mulMatTVec3(x,matrix,wo);
   bool physical_inside=false;
   if(query.margin==0){mjtNum rel[3]={witness.x-query.position.x,witness.y-query.position.y,witness.z-query.position.z},lp[3];mju_mulMatTVec3(lp,query.matrix,rel);mjtNum guarded[3]={query.size[0],query.size[1],query.size[2]};
    double guard=128*std::numeric_limits<double>::epsilon()*std::max({1.0,query.position.length(),witness.length(),mju_norm3(query.size)})+std::sqrt(3.0)*geometry_error;
    guarded[0]-=guard;if(query.type==mjGEOM_BOX){guarded[1]-=guard;guarded[2]-=guard;}else if(query.type==mjGEOM_CYLINDER)guarded[1]-=guard;
    physical_inside=guarded[0]>0&&point_inside_geom(query.type,lp,guarded);}
   else physical_inside=dist<query.margin-tolerance-std::sqrt(3.0)*geometry_error;
   if(physical_inside&&mjc_distance(m,d,&sdf,x)<-tolerance){proof=true;break;}
  }
  if(!proof)continue;
  Vec contact_normal=std::abs(gap)>tolerance?(target-q)*(1/gap):normal*-1;auto mid=(q+target)*.5;
  out={};out.dist=gap;out.pos[0]=mid.x;out.pos[1]=mid.y;out.pos[2]=mid.z;out.normal[0]=contact_normal.x;out.normal[1]=contact_normal.y;out.normal[2]=contact_normal.z;if(target_normal)*target_normal=normal;strict=true;return true;
 }
 return false;
}
// The scratch model has no ownership or dynamics relationship to the live space.
// Dispatching MuJoCo narrowphase directly neither runs forward nor steps live data.
std::vector<Overlap> overlaps(MjDirectSpaceState &state, const RID &rid, const Transform3D &transform,
    const Vector3 &motion, float margin, uint32_t mask, bool bodies, bool areas, const MjBody *moving=nullptr, bool *valid=nullptr) {
 if(valid)*valid=false;bool failed=false;
 if(!mask||(!bodies&&!areas)){if(valid)*valid=true;return {};}
 std::vector<Overlap> hits;
 if (!transform.is_finite() || !transform.basis.is_orthogonal() ||
     !transform.basis.get_scale().is_equal_approx(Vector3(1,1,1)) || transform.basis.determinant() <= 0 ||
     !motion.is_finite() || !std::isfinite(margin) || margin < 0) return hits;
 // Overlap APIs test the supplied pose; motion is intentionally ignored, as in Godot.
 auto *shape = state.server ? state.server->shape(rid) : nullptr;
 if (!shape || state.server->pending_free.count(rid.get_id())) return hits;
 int type; mjtNum size[3] = {0,0,0}; Transform3D pose = transform;
 switch (shape->type) {
 case PhysicsServer3D::SHAPE_BOX: {
   Vector3 v = shape->data; type = mjGEOM_BOX; size[0]=v.x; size[1]=v.z; size[2]=v.y; break;
 }
 case PhysicsServer3D::SHAPE_SPHERE: type=mjGEOM_SPHERE; size[0]=double(shape->data); break;
 case PhysicsServer3D::SHAPE_CYLINDER: {
   Dictionary d=shape->data; type=mjGEOM_CYLINDER; size[0]=double(d["radius"]); size[1]=double(d["height"])*.5; break;
 }
 case PhysicsServer3D::SHAPE_CAPSULE: {
   Dictionary d=shape->data;size[0]=double(d["radius"]);size[1]=double(d["height"])*.5-size[0];
   type=size[1]==0?mjGEOM_SPHERE:mjGEOM_CAPSULE;break;
 }
 case PhysicsServer3D::SHAPE_WORLD_BOUNDARY: {
   Plane p=shape->data;
   if (!std::isfinite(p.normal.length()) || !std::isfinite(p.d)) return hits;
   Vector3 n=p.normal.normalized();
   pose.origin += pose.basis.xform(n*(p.d/p.normal.length()));
   pose.basis = pose.basis*Basis(Quaternion(Vector3(0,1,0),n));
   type=mjGEOM_PLANE; size[2]=.1; break;
 }
 default: query_problem("overlap query shape (only native primitives supported)"); return hits;
 }
 if (!pose.is_finite()) return hits;
 for (mjtNum extent : size) if (!std::isfinite(extent) || extent < 0 || extent > std::numeric_limits<real_t>::max()) return hits;
 auto *space = query_space(state,mask,bodies,areas); if (!space) return hits;
 bool areas_valid=true;std::vector<AreaQueryGeom> area_geoms;if(areas)area_geoms=area_query_geometries(state,mask,false,areas_valid);if(!areas_valid)return hits;

 std::unique_ptr<mjSpec, decltype(&mj_deleteSpec)> spec(mj_makeSpec(),mj_deleteSpec);
 for (int i=0;i<2;++i) { auto *g=mjs_addGeom(mjs_findBody(spec.get(),"world"),nullptr); g->type=mjGEOM_SPHERE; g->size[0]=1; }
 std::unique_ptr<mjModel, decltype(&mj_deleteModel)> model(mj_compile(spec.get(),nullptr),mj_deleteModel);
 if (!model) return hits;
 std::unique_ptr<mjData, decltype(&mj_deleteData)> data(mj_makeData(model.get()),mj_deleteData);
 if (!data) return hits;
 model->geom_type[0]=type; mju_copy3(model->geom_size,size);
 model->geom_rbound[0]=type==mjGEOM_SPHERE?size[0]:type==mjGEOM_CAPSULE?size[0]+size[1]:mju_norm3(size);
 Vector3 pos=godot_to_mj(pose.origin);
 Quaternion rotation=godot_to_mj(pose.basis).get_rotation_quaternion().normalized();
 mjtNum quat[4]={rotation.w,rotation.x,rotation.y,rotation.z};mju_normalize4(quat);mju_quat2Mat(data->geom_xmat,quat);
 for (int a=0;a<3;++a) data->geom_xpos[a]=pos[a];
 for (int geom=0;geom<int(space->model->ngeom)+int(area_geoms.size());++geom) {
   const bool area_target=geom>=space->model->ngeom;
   MjBody *body=nullptr;int target=0,target_shape=0,source_geom=geom;std::shared_ptr<MjBody> area_owner;
   const mjModel*source_model=space->model;const mjData*source_data=space->data;
   if(area_target){const auto &g=area_geoms[geom-space->model->ngeom];area_owner=g.owner;body=area_owner.get();target=g.type;target_shape=g.shape;
    model->geom_type[1]=g.type;mju_copy3(model->geom_size+3,g.size);model->geom_dataid[1]=-1;model->geom_plugin[1]=-1;
    model->geom_rbound[1]=g.type==mjGEOM_SPHERE?g.size[0]:g.type==mjGEOM_CAPSULE?g.size[0]+g.size[1]:mju_norm3(g.size);
    mju_copy3(data->geom_xpos+3,g.position);mju_copy(data->geom_xmat+9,g.matrix,9);
    source_model=model.get();source_data=data.get();source_geom=1;
   }else{if(!bodies)continue;body=query_body(state,*space,geom,mask,false,moving);if(!body)continue;target=space->model->geom_type[geom];target_shape=space->geom_owners[geom].second;}

   if(type==mjGEOM_PLANE&&!primitive(target)){query_problem("unbounded plane query against asset target");failed=true;continue;}
   
   model->geom_type[1]=target;
   model->geom_rbound[1]=source_model->geom_rbound[source_geom];
   mju_copy3(model->geom_size+3,source_model->geom_size+3*source_geom);
   mju_copy3(data->geom_xpos+3,source_data->geom_xpos+3*source_geom);
   mju_copy(data->geom_xmat+9,source_data->geom_xmat+9*source_geom,9);
   // The two-geom scratch owns all writable narrowphase workspace. A model
   // view borrows only immutable mesh/hfield/octree assets from the live model.
   mjModel view=*source_model;view.ngeom=2;view.vis.global.bvactive=0;
#define GMJ_QUERY_FIELD(field,width) view.field=model->field; std::copy_n(source_model->field+width*source_geom,width,model->field+width)
   GMJ_QUERY_FIELD(geom_type,1);GMJ_QUERY_FIELD(geom_contype,1);GMJ_QUERY_FIELD(geom_conaffinity,1);
   GMJ_QUERY_FIELD(geom_condim,1);GMJ_QUERY_FIELD(geom_bodyid,1);GMJ_QUERY_FIELD(geom_dataid,1);
   GMJ_QUERY_FIELD(geom_matid,1);GMJ_QUERY_FIELD(geom_group,1);GMJ_QUERY_FIELD(geom_priority,1);
   GMJ_QUERY_FIELD(geom_plugin,1);GMJ_QUERY_FIELD(geom_sameframe,1);GMJ_QUERY_FIELD(geom_solmix,1);
   GMJ_QUERY_FIELD(geom_solref,mjNREF);GMJ_QUERY_FIELD(geom_solimp,mjNIMP);GMJ_QUERY_FIELD(geom_size,3);
   GMJ_QUERY_FIELD(geom_aabb,6);GMJ_QUERY_FIELD(geom_rbound,1);GMJ_QUERY_FIELD(geom_pos,3);
   GMJ_QUERY_FIELD(geom_quat,4);GMJ_QUERY_FIELD(geom_friction,3);GMJ_QUERY_FIELD(geom_margin,1);
   GMJ_QUERY_FIELD(geom_gap,1);GMJ_QUERY_FIELD(geom_surfacevel,6);GMJ_QUERY_FIELD(geom_adhesion,1);
   GMJ_QUERY_FIELD(geom_fluid,mjNFLUID);GMJ_QUERY_FIELD(geom_rgba,4);
#undef GMJ_QUERY_FIELD
   model->geom_bodyid[0]=model->geom_bodyid[1]=0;
   std::fill_n(model->geom_aabb,6,0.0);
   for(int k=0;k<3;++k)model->geom_aabb[3+k]=type==mjGEOM_BOX?size[k]:type==mjGEOM_SPHERE?size[0]:k==2?size[1]+(type==mjGEOM_CAPSULE?size[0]:0):size[0];
   const double inflation=0;
   model->geom_size[0]=size[0]+inflation;model->geom_rbound[0]+=inflation;
   for(int k=0;k<3;++k)model->geom_aabb[3+k]+=inflation;
   bool reversed=type>target; int a=reversed?1:0,b=reversed?0:1;
   const mjModel*narrow=primitive(target)?model.get():&view;
   auto collision=mjCOLLISIONFUNC[model->geom_type[a]][model->geom_type[b]];
   if (!collision) continue; // In particular, no plane/plane finite manifold.
   mjPreContact contacts[mjMAXCONPAIR]{};
   int count=0;
   if(target==mjGEOM_SDF){
    auto query=convex_object(narrow,data.get(),0,{},margin);
    if(!sdf_certification_domain(query,source_data,source_geom)){query_problem("SDF query exceeds certified coordinate/shape domain");failed=true;continue;}
    auto field=sdf_field_for(*space,source_geom);gmj_sdf::Stats stats;
    double error=sdf_geometry_error(query,source_data,source_geom);
    if(field->separated(sdf_local_support(query,source_data,source_geom),stats,error))count=0;
    else{bool strict=false;if(!sdf_contact(query,source_model,source_data,source_geom,contacts[0],strict,nullptr,error)){query_problem("SDF primitive witness or separation not certified");failed=true;continue;}count=1;reversed=false;a=0;b=1;}
   }else count=collision(narrow,data.get(),contacts,a,b,margin);
   model->geom_size[0]=size[0];model->geom_rbound[0]=type==mjGEOM_SPHERE?size[0]:type==mjGEOM_CAPSULE?size[0]+size[1]:mju_norm3(size);
   if(inflation)for(int i=0;i<count;++i){contacts[i].dist+=inflation;mju_addToScl3(contacts[i].pos,contacts[i].normal,(reversed?1:-1)*.5*inflation);}
   bool invalid=false;
   for(int i=0;i<count;++i) if(!valid_witnesses(narrow,data.get(),a,b,contacts[i])) invalid=true;
   if((target==mjGEOM_MESH||target==mjGEOM_ELLIPSOID)&&(invalid||!count)){
    gmj_sweep::Vec origin{data->geom_xpos[0],data->geom_xpos[1],data->geom_xpos[2]};
    auto qa=convex_object(narrow,data.get(),0,origin),qb=convex_object(narrow,data.get(),1,origin);
    int result=convex_pair_contact(qa,qb,origin,margin,contacts[0]);
    if(result==1&&valid_witnesses(narrow,data.get(),0,1,contacts[0])){count=1;reversed=false;invalid=false;}
    else if(result==0){count=0;invalid=false;}
    else{query_problem("convex asset surface pair not certified");failed=true;continue;}
   }
   if(target==mjGEOM_HFIELD&&(invalid||!count)){
    gmj_sweep::Vec origin{data->geom_xpos[0],data->geom_xpos[1],data->geom_xpos[2]};
    auto qa=convex_object(narrow,data.get(),0,origin),qb=convex_object(narrow,data.get(),1,origin);auto prisms=hfield_prisms(qb,narrow,1);bool unresolved=prisms.empty();bool found=false;
    auto query_world=convex_object(narrow,data.get(),0);
    if(hfield_contained_contact(query_world,narrow,data.get(),1,contacts[0])&&valid_witnesses(narrow,data.get(),0,1,contacts[0]))found=true;
    for(auto&prism:prisms){if(found)break;mjPreContact c{};int result=convex_pair_contact(qa,prism,origin,margin,c);
     if(result==1&&valid_witnesses(narrow,data.get(),0,1,c)){contacts[0]=c;found=true;break;}if(result!=0)unresolved=true;
    }
    if(found){count=1;reversed=false;invalid=false;}
    else if(!unresolved){count=0;invalid=false;}
    else{query_problem("hfield original surface witness not certified");failed=true;continue;}
   }
   // Raw contact positions are not universally witness midpoints. In
   // particular, cylinder normal correction and perturbed manifolds break
   // that assumption. Retain original support vertices and portal barycentric
   // witnesses instead of swapping/projecting points or perturbing geometry.
   bool finite_pair=primitive(target) && type!=mjGEOM_PLANE && target!=mjGEOM_PLANE;
   if(finite_pair && (invalid || (!count && (type==mjGEOM_CYLINDER || target==mjGEOM_CYLINDER || type==mjGEOM_CAPSULE || target==mjGEOM_CAPSULE)))) {
     mjPreContact repaired{};
     if(primitive_witness(model.get(),data.get(),repaired)) {
       contacts[0]=repaired; count=1; reversed=false;
     } else if(invalid) {
       // Positive-margin separated witnesses come directly from the distance
       // interface, never from a penetration midpoint estimate.
       mjtNum pair[6];double distance=mj_geomDistance(model.get(),data.get(),0,1,margin+1e-8,pair);
       repaired.dist=distance;
       mju_add3(repaired.pos,pair,pair+3);mju_scl3(repaired.pos,repaired.pos,.5);
       mju_sub3(repaired.normal,pair+3,pair);mju_normalize3(repaired.normal);
       if(distance>=0 && distance<=margin && valid_witnesses(narrow,data.get(),0,1,repaired)) {
         contacts[0]=repaired;count=1;reversed=false;
       } else {failed=true;query_problem("primitive contact witness could not be validated");count=0;}
     }
   }
   for(int i=0;i<count;++i) {
     const auto &c=contacts[i];
     Overlap hit{body,target_shape,c,reversed,{},area_owner};
     mjtNum target_point[3],hint[3];
     mju_addScl3(target_point,c.pos,c.normal,(reversed?-1:1)*.5*c.dist);
     mju_scl3(hint,c.normal,reversed?1:-1);
     hit.target_normal=witness_normal(narrow,data.get(),1,target_point,hint);
     if(!valid_witnesses(narrow,data.get(),reversed?1:0,reversed?0:1,c) ||
         !hit.target_normal.is_finite() || Math::abs(hit.target_normal.length_squared()-1)>1e-5) {
       failed=true;query_problem("primitive contact witness could not be validated");
       continue;
     }
     if(!contact_point(hit,true).is_finite() || !contact_point(hit,false).is_finite()) {failed=true;continue;}
     if(std::isfinite(c.dist) && c.dist<=margin &&
         Vector3(c.normal[0],c.normal[1],c.normal[2]).is_finite() &&
         contact_point(hit,true).is_finite() && contact_point(hit,false).is_finite()) hits.push_back(hit);
   }
 }
 std::stable_sort(hits.begin(),hits.end(),[](const Overlap &a,const Overlap &b) {
   if(a.body->rid!=b.body->rid) return a.body->rid.get_id()<b.body->rid.get_id();
   return a.shape<b.shape;
 });
 if(valid)*valid=!failed;
 return hits;
}
Vector3 contact_point(const Overlap &hit, bool query) {
 const auto &c=hit.contact;
 double sign=(query != hit.reversed)?-1:1;
 return mj_to_godot(Vector3(c.pos[0]+sign*.5*c.dist*c.normal[0],c.pos[1]+sign*.5*c.dist*c.normal[1],c.pos[2]+sign*.5*c.dist*c.normal[2]));
}

void rest_result(MjSpace &space, MjBody &body, int shape, const Vector3 &point,
    const Vector3 &normal, PhysicsServer3DExtensionShapeRestInfo &info) {
 info={}; info.rid=body.rid; info.collider_id=ObjectID(body.object_id); info.shape=shape;
 info.point=point; info.normal=normal;
 if(body.mj_body>=0 && body.mode==PhysicsServer3D::BODY_MODE_RIGID) {
   mjtNum velocity[6]; mj_objectVelocity(space.model,space.data,mjOBJ_BODY,body.mj_body,velocity,0);
   Vector3 angular=mj_to_godot(Vector3(velocity[0],velocity[1],velocity[2]));
   Vector3 linear=mj_to_godot(Vector3(velocity[3],velocity[4],velocity[5]));
   const mjtNum *com=space.data->xipos+3*body.mj_body;
   info.linear_velocity=linear+angular.cross(point-mj_to_godot(Vector3(com[0],com[1],com[2])));
 } else if(body.mj_body>=0 && body.mode==PhysicsServer3D::BODY_MODE_KINEMATIC) {
   const mjtNum *com=space.data->xipos+3*body.mj_body;
   info.linear_velocity=body.linear_velocity+body.angular_velocity.cross(point-mj_to_godot(Vector3(com[0],com[1],com[2])));
 }
}
// Support of a primitive in world direction, with sizes/axes in MuJoCo order.
gmj_sweep::Vec support(int type, const mjtNum *size, const mjtNum *matrix, gmj_sweep::Vec n) {
 double direction_scale=std::max({std::abs(n.x),std::abs(n.y),std::abs(n.z)});
 mjtNum direction[3]={direction_scale?n.x/direction_scale:0,direction_scale?n.y/direction_scale:0,direction_scale?n.z/direction_scale:0},local[3],v[3],world[3];
 mju_mulMatTVec3(local,matrix,direction);
 if(type==mjGEOM_SPHERE || type==mjGEOM_CAPSULE) { double length=std::hypot(local[0],local[1],local[2]); for(int i=0;i<3;++i) v[i]=length?size[0]*local[i]/length:0; if(type==mjGEOM_CAPSULE) v[2]+=local[2]>=0?size[1]:-size[1]; }
 else if(type==mjGEOM_BOX) { for(int i=0;i<3;++i) v[i]=local[i]>=0?size[i]:-size[i]; }
 else { double radial=std::hypot(local[0],local[1]); v[0]=radial?size[0]*local[0]/radial:0; v[1]=radial?size[0]*local[1]/radial:0; v[2]=local[2]>=0?size[1]:-size[1]; }
 mju_mulMatVec3(world,matrix,v); return {world[0],world[1],world[2]};
}

// The float ABI can have no representable pose inside a very short collision
// interval. Verify the rounded unsafe pose; never claim it actually contacts
// when it has already crossed an entire thin obstacle or a grazing point.
double sweep_gap(int type, const mjtNum *size, const mjtNum *matrix,
    gmj_sweep::Vec origin, gmj_sweep::Vec velocity, int target, const mjtNum *ts,
    const mjtNum *mat, gmj_sweep::Vec center, double margin, double fraction) {
 using gmj_sweep::Vec;
 Vec p=origin+velocity*fraction;
 if(target==mjGEOM_PLANE) {
   Vec n{mat[2],mat[5],mat[8]};
   return (p+support(type,size,matrix,n*-1)-center).dot(n)-margin;
 }
 if(type==mjGEOM_PLANE) {
   Vec n{matrix[2],matrix[5],matrix[8]};
   return (center+support(target,ts,mat,n*-1)-p).dot(n)-margin;
 }
 Vec offset=p-center; mjtNum w[3]={offset.x,offset.y,offset.z}, local[3];
 mju_mulMatTVec3(local,mat,w); Vec point{local[0],local[1],local[2]};
 auto kind=target==mjGEOM_SPHERE?gmj_sweep::Kind::sphere:target==mjGEOM_BOX?gmj_sweep::Kind::box:target==mjGEOM_CAPSULE?gmj_sweep::Kind::capsule:gmj_sweep::Kind::cylinder;
 mjtNum axis_world[3]={},axis_local[3];
 if(type==mjGEOM_CAPSULE) for(int k=0;k<3;++k)axis_world[k]=matrix[3*k+2]*size[1];
 mju_mulMatTVec3(axis_local,mat,axis_world);
 return gmj_sweep::segment_closest({kind,{ts[0],ts[1],ts[2]}},point,
     {axis_local[0],axis_local[1],axis_local[2]}).delta().length()-size[0]-margin;
}
} // namespace

bool MjDirectSpaceState::_intersect_ray(const Vector3 &p_from, const Vector3 &p_to,
		uint32_t p_collision_mask, bool p_collide_with_bodies, bool p_collide_with_areas,
		bool p_hit_from_inside, bool p_hit_back_faces, bool p_pick_ray,
		PhysicsServer3DExtensionRayResult *p_result) {
 QueryScope query_scope(*this,"ray");
	if (!p_result) {
		return false;
	}
	*p_result = {};
	p_result->shape = -1;
	p_result->face_index = -1;
	// Primitive rays are two-sided; heightfield back faces obey the query flag.
	if (!server || (!p_collide_with_bodies&&!p_collide_with_areas) || !p_collision_mask ||
			!p_from.is_finite() || !p_to.is_finite()) {
        if(!server||!p_from.is_finite()||!p_to.is_finite())query_problem("ray input is invalid or non-finite");
		return false;
	}
	MjSpace *query_space = server->space(rid);
	if (!query_space || !server->rebuild(*query_space) ||
			!query_space->model || !query_space->data) {
		// In particular, do not query stale geometry after a failed rebuild.
        query_problem("ray query space rebuild failed");
		return false;
	}
	const mjModel *model = query_space->model;
	const mjData *data = query_space->data;
	if (query_space->geom_owners.size() != static_cast<size_t>(model->ngeom)) {
		query_problem("ray query with inconsistent geom ownership");
		return false;
	}

	const Vector3 mj_from = godot_to_mj(p_from);
	const Vector3 mj_to = godot_to_mj(p_to);
	const mjtNum origin[3] = { mj_from.x, mj_from.y, mj_from.z };
	// Subtract in MuJoCo precision, avoiding an intermediate float overflow.
	mjtNum direction[3] = {
		static_cast<mjtNum>(mj_to.x) - origin[0],
		static_cast<mjtNum>(mj_to.y) - origin[1],
		static_cast<mjtNum>(mj_to.z) - origin[2]
	};
	const mjtNum length = std::hypot(direction[0], direction[1], direction[2]);
	if (!std::isfinite(length)) {
		return false;
	}
	if (length > 0) {
		for (int axis = 0; axis < 3; ++axis) {
			direction[axis] /= length;
		}
	} else if (!p_hit_from_inside) {
		return false;
	}

	mjtNum nearest = length;
	mjtNum nearest_normal[3] = {};
	MjBody *nearest_body = nullptr;
	int nearest_shape = -1;
	bool nearest_inside = false;
	// Permit only floating-point roundoff at the segment endpoint, not an
	// arbitrary world-space ray margin. Clamp accepted endpoint hits below.
	const mjtNum endpoint_tolerance = 32 * std::numeric_limits<mjtNum>::epsilon() *
			std::max<mjtNum>(1, length);

 bool areas_valid=true;std::vector<AreaQueryGeom> area_geoms;if(p_collide_with_areas)area_geoms=area_query_geometries(*this,p_collision_mask,p_pick_ray,areas_valid);if(!areas_valid)return false;
	if(p_collide_with_bodies)for (int geom = 0; geom < model->ngeom; ++geom) {
		const auto &owner = query_space->geom_owners[geom];
		MjBody *body = query_body(*this, *query_space, geom, p_collision_mask, p_pick_ray);
		if (!body) continue;
		// A query's mask is matched against the body's layer. The body's own
		// collision mask controls body/body contacts, not visibility to rays.
		const int type = model->geom_type[geom];
		const mjtNum *position = data->geom_xpos + 3 * geom;
		const mjtNum *matrix = data->geom_xmat + 9 * geom;
		const mjtNum *size = model->geom_size + 3 * geom;
		mjtNum offset[3], local_from[3];
		mju_sub3(offset, origin, position);
		mju_mulMatTVec3(local_from, matrix, offset);
		bool inside = point_inside_geom(type, local_from, size);
		if(type==mjGEOM_MESH||type==mjGEOM_SDF||type==mjGEOM_ELLIPSOID){bool valid=false;inside=gmj_query::inside(model,data,geom,local_from,valid);if(!valid){query_problem("asset point classification unavailable");return false;}}

		if (type == mjGEOM_HFIELD) {
			const int id = model->geom_dataid[geom];
			const mjtNum *extent = model->hfield_size + 4*id;
			const int cols = model->hfield_ncol[id], rows = model->hfield_nrow[id];
			if (std::abs(local_from[0]) < extent[0] && std::abs(local_from[1]) < extent[1] && local_from[2] > -extent[3]) {
				double x = (local_from[0]/extent[0]+1)*.5*(cols-1);
				double y = (local_from[1]/extent[1]+1)*.5*(rows-1);
				int col = std::clamp(int(x),0,cols-2), row = std::clamp(int(y),0,rows-2);
				x -= col; y -= row;
				const float *h = model->hfield_data + model->hfield_adr[id] + row*cols + col;
				double top = y <= x ? h[0]+x*(h[1]-h[0])+y*(h[cols+1]-h[1]) : h[0]+x*(h[cols+1]-h[cols])+y*(h[cols]-h[0]);
				inside = local_from[2] < top*extent[2];
			}
		}
		if (inside) {
			if (!p_hit_from_inside) {
				// MuJoCo returns the exit surface for solid primitives. Godot
				// instead skips a shape entirely when starting inside it.
				continue;
			}
			if(nearest_body&&nearest==0&&std::make_pair(body->rid.get_id(),owner.second)>=std::make_pair(nearest_body->rid.get_id(),nearest_shape))continue;
			nearest = 0;
			nearest_body = body;
			nearest_shape = owner.second;
			nearest_inside = true;
			continue;
		}
		if (length == 0) {
			continue;
		}
		mjtNum normal[3] = {};
		mjtNum distance;
		if(type==mjGEOM_MESH||type==mjGEOM_SDF){bool valid=false;distance=gmj_query::ray(model,data,geom,origin,direction,local_from,normal,valid);if(!valid){query_problem("asset collision ray unavailable");return false;}}
		else distance=type==mjGEOM_HFIELD?mj_rayHfield(model,data,geom,origin,direction,normal):intersect_geom(type,position,matrix,size,origin,direction,local_from,normal);
		if (!std::isfinite(distance) || distance < 0 || distance > length + endpoint_tolerance ||
				!std::isfinite(normal[0]) || !std::isfinite(normal[1]) || !std::isfinite(normal[2])) {
			continue;
		}
		if (type == mjGEOM_HFIELD && !p_hit_back_faces && mju_dot3(normal,direction) > 0) continue;
		distance = std::min(distance, length);
		if (nearest_body && (distance>nearest || (distance==nearest && std::make_pair(body->rid.get_id(),owner.second)>=std::make_pair(nearest_body->rid.get_id(),nearest_shape)))) {
			continue;
		}
		nearest = distance;
		nearest_body = body;
		nearest_shape = owner.second;
		nearest_inside = false;
		mju_copy3(nearest_normal, normal);
	}
 for(const auto &geom:area_geoms){
  mjtNum offset[3],local[3],normal[3]={};mju_sub3(offset,origin,geom.position);mju_mulMatTVec3(local,geom.matrix,offset);
  const bool inside=point_inside_geom(geom.type,local,geom.size);if(inside&&!p_hit_from_inside)continue;if(length==0&&!inside)continue;
  const mjtNum distance=inside?0:mju_rayGeom(geom.position,geom.matrix,geom.size,origin,direction,geom.type,normal);
  if(!std::isfinite(distance)||distance<0||distance>length+endpoint_tolerance)continue;
  auto*body=geom.owner.get();
  if(nearest_body&&(distance>nearest||(distance==nearest&&std::make_pair(body->rid.get_id(),geom.shape)>=std::make_pair(nearest_body->rid.get_id(),nearest_shape))))continue;
  nearest=std::min(distance,length);nearest_body=body;nearest_shape=geom.shape;nearest_inside=inside;mju_copy3(nearest_normal,normal);
 }
	if (!nearest_body) {
		return false;
	}

	p_result->rid = nearest_body->rid;
	p_result->collider_id = ObjectID(nearest_body->object_id);
	// Native result structs cross the ABI without Variant/PtrToArg conversion.
	// Godot expects its engine Object*, not the godot-cpp wrapper Object*.
	Object *collider = nearest_body->object_id ? ObjectDB::get_instance(nearest_body->object_id) : nullptr;
	p_result->collider = collider ? reinterpret_cast<Object *>(collider->_owner) : nullptr;
	p_result->shape = nearest_shape;
	if (nearest_inside) {
		p_result->position = p_from;
		p_result->normal = Vector3();
	} else {
		p_result->position = mj_to_godot(Vector3(origin[0] + direction[0] * nearest,
				origin[1] + direction[1] * nearest, origin[2] + direction[2] * nearest));
		p_result->normal = mj_to_godot(Vector3(nearest_normal[0], nearest_normal[1],
				nearest_normal[2])).normalized();
	}
	return true;
}

int32_t MjDirectSpaceState::_intersect_point(const Vector3 &position, uint32_t mask, bool bodies, bool areas,
    PhysicsServer3DExtensionShapeResult *results, int32_t max_results) {
 QueryScope query_scope(*this,"point");
 if(!position.is_finite()){query_problem("point input is non-finite");return 0;}
 if (!results || max_results<=0) return 0;
 auto *space=query_space(*this,mask,bodies,areas); if(!space) return 0;
 std::vector<PhysicsServer3DExtensionShapeResult> hits;
 Vector3 p=godot_to_mj(position); mjtNum point[3]={p.x,p.y,p.z};
 if(bodies)for(int geom=0;geom<space->model->ngeom;++geom) {
   auto *body=query_body(*this,*space,geom,mask); if(!body) continue;
   int type=space->model->geom_type[geom];
   mjtNum offset[3],local[3]; mju_sub3(offset,point,space->data->geom_xpos+3*geom);
   mju_mulMatTVec3(local,space->data->geom_xmat+9*geom,offset);
   bool inside=point_inside_geom(type,local,space->model->geom_size+3*geom);
   if(type==mjGEOM_MESH||type==mjGEOM_SDF||type==mjGEOM_ELLIPSOID||type==mjGEOM_HFIELD){bool valid=false;inside=gmj_query::inside(space->model,space->data,geom,local,valid);if(!valid){query_problem("asset point classification unavailable");return 0;}}
   else if(!primitive(type)){query_problem("heightfield point target not yet supported");return 0;}
   if(inside)hits.push_back(shape_result(*body,space->geom_owners[geom].second));
 }
 bool areas_valid=true;if(areas)for(const auto &geom:area_query_geometries(*this,mask,false,areas_valid)){
  mjtNum offset[3],local[3];mju_sub3(offset,point,geom.position);mju_mulMatTVec3(local,geom.matrix,offset);
  if(point_inside_geom(geom.type,local,geom.size))hits.push_back(shape_result(*geom.owner,geom.shape));
 }
 if(!areas_valid)return 0;
 std::sort(hits.begin(),hits.end(),[](const auto &a,const auto &b){return a.rid==b.rid?a.shape<b.shape:a.rid.get_id()<b.rid.get_id();});
 int count=std::min(max_results,int(hits.size())); std::copy_n(hits.begin(),count,results); return count;
}

int32_t MjDirectSpaceState::_intersect_shape(const RID &shape, const Transform3D &pose, const Vector3 &motion,
    float margin, uint32_t mask, bool bodies, bool areas, PhysicsServer3DExtensionShapeResult *results, int32_t max_results) {
 QueryScope query_scope(*this,"shape");
 if(!results || max_results<=0) return 0;
 bool valid=false;auto hits=overlaps(*this,shape,pose,motion,margin,mask,bodies,areas,nullptr,&valid); if(!valid){if(query_error.is_empty())query_problem("overlap input or witness was not certified");return 0;}int count=0;
 for(const auto &hit:hits) {
   if(count && results[count-1].rid==hit.body->rid && results[count-1].shape==hit.shape) continue;
   results[count++]=shape_result(*hit.body,hit.shape); if(count==max_results) break;
 }
 return count;
}

static bool cast_motion_impl(MjDirectSpaceState &state, const RID &shape_rid, const Transform3D &transform, const Vector3 &motion,
    float margin, uint32_t mask, bool bodies, bool areas, float *safe, float *unsafe,
    PhysicsServer3DExtensionShapeRestInfo *info, const MjBody *moving=nullptr) {
 auto *server=state.server;auto rid=state.rid;
 if(safe) *safe=0; if(unsafe) *unsafe=0; if(info) *info={};
 if(!safe || !unsafe || !server || !transform.is_finite() || !motion.is_finite() ||
     !transform.basis.is_orthogonal() || !transform.basis.get_scale().is_equal_approx(Vector3(1,1,1)) ||
     transform.basis.determinant()<=0 || !std::isfinite(margin) || margin<0) return false;
 auto *shape=server->shape(shape_rid);
 if(!shape || server->pending_free.count(shape_rid.get_id())) return false;
 if(areas) { query_problem("continuous sweep of Area3D"); return false; }
 int type; mjtNum size[3]={}; Transform3D pose=transform;
 switch(shape->type) {
 case PhysicsServer3D::SHAPE_SPHERE: type=mjGEOM_SPHERE; size[0]=double(shape->data); break;
 case PhysicsServer3D::SHAPE_BOX: { type=mjGEOM_BOX; Vector3 v=shape->data; size[0]=v.x; size[1]=v.z; size[2]=v.y; break; }
 case PhysicsServer3D::SHAPE_CYLINDER: { type=mjGEOM_CYLINDER; Dictionary d=shape->data; size[0]=double(d["radius"]); size[1]=double(d["height"])*.5; break; }
 case PhysicsServer3D::SHAPE_CAPSULE: {
   Dictionary d=shape->data;size[0]=double(d["radius"]);size[1]=double(d["height"])*.5-size[0];
   type=size[1]==0?mjGEOM_SPHERE:mjGEOM_CAPSULE;break;
 }
 case PhysicsServer3D::SHAPE_WORLD_BOUNDARY: {
   type=mjGEOM_PLANE; Plane p=shape->data;
   if(!std::isfinite(p.normal.length()) || !std::isfinite(p.d)) return false;
   Vector3 n=p.normal.normalized(); pose.origin+=pose.basis.xform(n*(p.d/p.normal.length()));
   pose.basis=pose.basis*Basis(Quaternion(Vector3(0,1,0),n)); break;
 }
 default: query_problem("continuous sweep query shape"); return false;
 }
 for(double extent:size) if(!std::isfinite(extent) || extent<0 || extent>std::numeric_limits<real_t>::max()) return false;
 if(!pose.is_finite()) return false;
 if(!bodies || !mask) { *safe=*unsafe=1; return true; }
 auto *space=query_space(state,mask,bodies,false); if(!space) return false;
 // Validate the complete candidate set first: never report a clear sweep by
 // silently ignoring an unsupported native obstacle, even beyond a closer hit.
 for(int geom=0;geom<space->model->ngeom;++geom) {
   if(!query_body(state,*space,geom,mask,false,moving)) continue;
   int target=space->model->geom_type[geom];
   if(!primitive(target) || (type==mjGEOM_PLANE && target==mjGEOM_PLANE) ||
       (type!=mjGEOM_SPHERE && type!=mjGEOM_CAPSULE && type!=mjGEOM_PLANE && target!=mjGEOM_PLANE)) {
     query_problem("continuous sweep pair (sphere/capsule to primitive or finite/plane only)"); return false;
   }
 }
 using gmj_sweep::Vec;
 Vector3 p=godot_to_mj(pose.origin), m=godot_to_mj(motion);
 Vec origin{p.x,p.y,p.z}, velocity{m.x,m.y,m.z};
 if(velocity.length()==0 && !moving) { *safe=*unsafe=1; return true; }
 Quaternion rotation=godot_to_mj(pose.basis).get_rotation_quaternion().normalized();
 mjtNum quat[4]={rotation.w,rotation.x,rotation.y,rotation.z}, matrix[9];
 mju_normalize4(quat); mju_quat2Mat(matrix,quat);
 std::vector<int> sweep_targets;
 double first=2, lower=1, minimum=1; MjBody *nearest=nullptr; int nearest_shape=-1, nearest_geom=-1; Vec witness{},normal{};
 for(int geom=0;geom<space->model->ngeom;++geom) {
   auto *body=query_body(state,*space,geom,mask,false,moving); if(!body) continue;
   int target=space->model->geom_type[geom];
   const mjtNum *pos=space->data->geom_xpos+3*geom, *mat=space->data->geom_xmat+9*geom, *ts=space->model->geom_size+3*geom;
   Vec center{pos[0],pos[1],pos[2]}, point{}, n{};
   gmj_sweep::Result hit;
   if(target==mjGEOM_PLANE) {
     n={mat[2],mat[5],mat[8]};
     Vec offset=support(type,size,matrix,n*-1);
     double gap=(origin+offset-center).dot(n)-margin;
     hit=gmj_sweep::plane(gap,velocity.dot(n));
     if(hit.hit) { point=origin+offset+velocity*hit.unsafe; point=point-n*((point-center).dot(n)); }
   } else if(type==mjGEOM_PLANE) {
     Vec plane_normal{matrix[2],matrix[5],matrix[8]};
     point=center+support(target,ts,mat,plane_normal*-1); n=plane_normal*-1;
     hit=gmj_sweep::plane((point-origin).dot(plane_normal)-margin,-velocity.dot(plane_normal));
   } else {
     Vec rel=origin-center; mjtNum r[3]={rel.x,rel.y,rel.z}, v[3]={velocity.x,velocity.y,velocity.z}, local[3], direction[3];
     mju_mulMatTVec3(local,mat,r); mju_mulMatTVec3(direction,mat,v);
     auto kind=target==mjGEOM_SPHERE?gmj_sweep::Kind::sphere:target==mjGEOM_BOX?gmj_sweep::Kind::box:target==mjGEOM_CAPSULE?gmj_sweep::Kind::capsule:gmj_sweep::Kind::cylinder;
     mjtNum axis_world[3]={},axis_local[3];
     if(type==mjGEOM_CAPSULE) for(int k=0;k<3;++k)axis_world[k]=matrix[3*k+2]*size[1];
     mju_mulMatTVec3(axis_local,mat,axis_world);
     hit=gmj_sweep::capsule({kind,{ts[0],ts[1],ts[2]}},{local[0],local[1],local[2]},
         {direction[0],direction[1],direction[2]},size[0]+double(margin),
         {axis_local[0],axis_local[1],axis_local[2]});
     mjtNum wp[3],wn[3],lp[3]={hit.point.x,hit.point.y,hit.point.z},ln[3]={hit.normal.x,hit.normal.y,hit.normal.z};
     mju_mulMatVec3(wp,mat,lp); mju_mulMatVec3(wn,mat,ln);
     point=center+Vec{wp[0],wp[1],wp[2]}; n={wn[0],wn[1],wn[2]};
   }
   if(!hit.valid) { query_problem("continuous sweep numerical bracket could not be certified"); return false; }
   // Recovery is mandatory for body motion: never inherit the public shape
   // query's initial-overlap ignore policy if narrowphase recovery missed one.
   if(moving && hit.initial_overlap) {
     query_problem("body motion initial penetration remains after recovery");return false;
   }
   if(!hit.initial_overlap) sweep_targets.push_back(geom);
   if(!hit.hit) continue;
   lower=std::min(lower,hit.safe);
   auto owner=space->geom_owners[geom];
   bool earlier=hit.unsafe<first;
   bool tie=hit.unsafe==first && nearest && (body->rid.get_id()<nearest->rid.get_id() || (body->rid==nearest->rid && owner.second<nearest_shape));
   if(earlier || tie) { first=hit.unsafe; minimum=hit.minimum; nearest=body; nearest_shape=owner.second; nearest_geom=geom; witness=point; normal=n; }
 }
 if(!nearest) { *safe=*unsafe=1; return true; }
 Vector3 point=mj_to_godot(Vector3(witness.x,witness.y,witness.z));
 Vector3 n=mj_to_godot(Vector3(normal.x,normal.y,normal.z)).normalized();
 if(!point.is_finite() || !n.is_finite()) return false;
 // Round outward, then independently verify the unsafe ABI pose below.
 float lo=float(lower), hi=float(first);
 if(double(lo)>lower) lo=std::nextafter(lo,0.0f);
 if(double(hi)<first) hi=std::nextafter(hi,1.0f);
 // Godot applies the fraction to real_t vectors, not double vectors. Verify
 // those poses too: cancellation at large coordinates can consume the entire
 // collision interval even when the fraction itself is representable.
 lo=std::nextafter(lo,0.0f);
 auto rounded_origin=[&](float fraction) {
   Vector3 position=transform.origin+motion*fraction;
   if(type==mjGEOM_PLANE) {
     Plane plane=shape->data;
     position+=transform.basis.xform(plane.normal.normalized()*(plane.d/plane.normal.length()));
   }
   Vector3 local=godot_to_mj(position); return Vec{local.x,local.y,local.z};
 };
 const mjtNum *target_pos=space->data->geom_xpos+3*nearest_geom;
 auto abi_gap=[&](float fraction) { return sweep_gap(type,size,matrix,rounded_origin(fraction),{},
     space->model->geom_type[nearest_geom],space->model->geom_size+3*nearest_geom,
     space->data->geom_xmat+9*nearest_geom,{target_pos[0],target_pos[1],target_pos[2]},margin,0); };
 auto continuous_gap=[&](float fraction) { return sweep_gap(type,size,matrix,origin,velocity,
     space->model->geom_type[nearest_geom],space->model->geom_size+3*nearest_geom,
     space->data->geom_xmat+9*nearest_geom,{target_pos[0],target_pos[1],target_pos[2]},margin,fraction); };
 // Fraction rounding and vector arithmetic round independently. A single
 // nextafter can leave an otherwise ordinary rotated face just outside at
 // unsafe (or inside at safe). Search adjacent representable fractions only
 // AFTER the continuous solver has established the first-contact bracket.
 // These probes certify ABI outputs; they never discover or classify a sweep.
 // Keep the continuous and float-pose predicates independent and exact: no
 // penetration/gap tolerance can turn a miss into a certified contact.
 auto safe_at=[&](float f) {
   for(int geom:sweep_targets) {
     const mjtNum *tp=space->data->geom_xpos+3*geom;
     int target=space->model->geom_type[geom];
     const mjtNum *ts=space->model->geom_size+3*geom,*mat=space->data->geom_xmat+9*geom;
     Vec center{tp[0],tp[1],tp[2]};
     double continuous=sweep_gap(type,size,matrix,origin,velocity,target,ts,mat,center,margin,f);
     double actual=sweep_gap(type,size,matrix,rounded_origin(f),{},target,ts,mat,center,margin,0);
     if(!std::isfinite(continuous) || !std::isfinite(actual) || continuous<0 || actual<0)return false;
   }
   return true;
 };
 auto unsafe_at=[&](float f) {
   double continuous=continuous_gap(f),actual=abi_gap(f);
   return std::isfinite(continuous) && std::isfinite(actual) && continuous<=0 && actual<=0;
 };
 bool safe_ok=safe_at(lo),unsafe_ok=unsafe_at(hi);
 constexpr int max_fraction_neighbors=8;
 for(int i=0;!safe_ok && lo>0 && i<max_fraction_neighbors;++i) {
   lo=std::nextafter(lo,0.0f);safe_ok=safe_at(lo);
 }
 for(int i=0;!unsafe_ok && hi<1 && i<max_fraction_neighbors;++i) {
   hi=std::nextafter(hi,1.0f);unsafe_ok=unsafe_at(hi);
 }
 // Near t=0, many fraction ULPs can fit inside one world-position ULP.
 // If neighboring fractions do not suffice, use known continuous bounds:
 // t=0 is a candidate safe endpoint and the convex solver's minimizer is a
 // candidate interior point. Certification is still mandatory at both poses.
 // Refine only a certified bracket, never replace failure with a tolerance.
 if(!safe_ok && safe_at(0)) {
   float a=0,b=lo;
   for(int i=0;i<64;++i) {float mid=a+(b-a)*.5f;if(mid<=a||mid>=b)break;if(safe_at(mid))a=mid;else b=mid;}
   lo=a;safe_ok=true;
 }
 if(!unsafe_ok) {
   float middle=float(minimum);
   for(float candidate:{middle,std::nextafter(middle,0.0f),std::nextafter(middle,1.0f)}) {
     if(candidate<first || candidate>1 || !unsafe_at(candidate))continue;
     float a=float(first),b=candidate;
     for(int i=0;i<64;++i) {float mid=a+(b-a)*.5f;if(mid<=a||mid>=b)break;if(unsafe_at(mid))b=mid;else a=mid;}
     hi=b;unsafe_ok=true;break;
   }
 }
 if(!safe_ok || !unsafe_ok) {
   query_problem("continuous sweep contact has no certified float safe/unsafe poses"); return false;
 }
 *safe=std::clamp(lo,0.0f,1.0f); *unsafe=std::clamp(hi,0.0f,1.0f);
 if(info) rest_result(*space,*nearest,nearest_shape,point,n,*info);
 return true;
}


namespace {
struct GeneralCastTarget {
 ConvexQueryObject object;MjBody*owner=nullptr;std::shared_ptr<MjBody> area_owner;int shape=0,geom=-1;bool ignored=false;
 std::shared_ptr<gmj_sdf::Field> sdf_field;std::shared_ptr<gmj_sdf::Stats> sdf_stats;const mjData*sdf_data=nullptr;gmj_sweep::Vec world_base{};double sdf_geometry_envelope=0;
};
struct GeneralCastEvaluation {
 bool valid=false,inside=false,boundary=false;double lower=0;gmj_sweep::Vec point{},normal{};double signed_gap=0;
};
GeneralCastEvaluation general_evaluate(const ConvexQueryObject&query,const GeneralCastTarget&target,gmj_sweep::Vec origin){
 using gmj_sweep::Vec;auto a=query;a.position=origin;const auto&b=target.object;
 if(target.sdf_field){
  auto world=a;world.position=world.position+target.world_base;mjPreContact c{};bool strict=false;Vec normal{};
  if(sdf_contact(world,b.assets,target.sdf_data,target.geom,c,strict,&normal,target.sdf_geometry_envelope)){
   Vec point{c.pos[0]+.5*c.dist*c.normal[0],c.pos[1]+.5*c.dist*c.normal[1],c.pos[2]+.5*c.dist*c.normal[2]};
   return {true,strict,false,0,point-target.world_base,normal};
  }
  auto&stats=*target.sdf_stats;if(target.sdf_field->separated(sdf_local_support(world,target.sdf_data,target.geom),stats,target.sdf_geometry_envelope))return {true,false,false,1,{},{}};return {};
 }

 if(b.type==mjGEOM_PLANE){
  Vec n{b.matrix[2],b.matrix[5],b.matrix[8]},point=a.point(n*-1);
  double gap=(point-b.position).dot(n);
  // query.point includes one Minkowski margin; keep the physical target point.
  return {true,gap<0,gap==0,std::max(0.0,gap),point-n*gap,n,gap};
 }
 if(a.type==mjGEOM_PLANE){
  Vec n{a.matrix[2],a.matrix[5],a.matrix[8]},point=b.point(n*-1);double gap=(point-origin).dot(n)-a.margin;
  return {true,gap<0,gap==0,std::max(0.0,gap),point,n*-1,gap};
 }
 auto d=convex_distance(a,b);return {d.valid,d.inside,d.boundary,d.lower,d.point,d.normal};
}
struct SdfPrecisionBudget {double path=0,coordinate_lower=0,coordinate_upper=0,arithmetic=0,total=0;};
double norm_upper(gmj_sweep::Vec p){
 using namespace gmj_sdf;Number sum{0,0};for(double value:{p.x,p.y,p.z})sum=add(sum,mul({value,value},{value,value}));return up(std::sqrt(std::max(0.0,sum.hi)));
}
double pose_coordinate_error(const Transform3D&pose,const Vector3&motion,float fraction){
 using namespace gmj_sdf;Vector3 actual=pose.origin+motion*fraction;Number sum{0,0};
 for(int k=0;k<3;++k){double base=pose.origin[k],travel=motion[k];auto exact=add({base,base},mul({travel,travel},{double(fraction),double(fraction)}));auto error=sub({actual[k],actual[k]},exact);double bound=std::max(std::abs(error.lo),std::abs(error.hi));sum=add(sum,mul({bound,bound},{bound,bound}));}
 return up(std::sqrt(std::max(0.0,sum.hi)));
}
SdfPrecisionBudget sdf_precision_budget(const Transform3D&pose,const Vector3&motion,float lo,float hi,double geometry_error){
 using namespace gmj_sdf;SdfPrecisionBudget result;auto gap=sub({double(hi),double(hi)},{double(lo),double(lo)});
 result.path=mul({norm_upper({motion.x,motion.y,motion.z}),norm_upper({motion.x,motion.y,motion.z})},{gap.hi,gap.hi}).hi;
 result.coordinate_lower=pose_coordinate_error(pose,motion,lo);result.coordinate_upper=pose_coordinate_error(pose,motion,hi);result.arithmetic=norm_upper({geometry_error,geometry_error,geometry_error});
 Number total=add({result.path,result.path},add({result.coordinate_lower,result.coordinate_lower},{result.coordinate_upper,result.coordinate_upper}));total=add(total,mul({2,2},{result.arithmetic,result.arithmetic}));result.total=total.hi;return result;
}
bool general_cast(MjDirectSpaceState&state,const RID&shape_rid,const Transform3D&transform,const Vector3&motion,float margin,uint32_t mask,bool bodies,bool areas,float*safe,float*unsafe,PhysicsServer3DExtensionShapeRestInfo*info){
 using gmj_sweep::Vec;if(safe)*safe=0;if(unsafe)*unsafe=0;if(info)*info={};
 auto*server=state.server;if(!server||!safe||!unsafe||!transform.is_finite()||!motion.is_finite()||!transform.basis.is_orthogonal()||!transform.basis.get_scale().is_equal_approx(Vector3(1,1,1))||transform.basis.determinant()<=0||!std::isfinite(margin)||margin<0)return false;
 auto*shape=server->shape(shape_rid);if(!shape||server->pending_free.count(shape_rid.get_id()))return false;
 ConvexQueryObject query;Transform3D pose=transform;
 if(shape->type==PhysicsServer3D::SHAPE_BOX){Vector3 size=shape->data;query.type=mjGEOM_BOX;query.size[0]=size.x;query.size[1]=size.z;query.size[2]=size.y;}
 else if(shape->type==PhysicsServer3D::SHAPE_SPHERE){query.type=mjGEOM_SPHERE;query.size[0]=double(shape->data);}
 else if(shape->type==PhysicsServer3D::SHAPE_CYLINDER||shape->type==PhysicsServer3D::SHAPE_CAPSULE){Dictionary sizes=shape->data;query.size[0]=double(sizes["radius"]);query.size[1]=double(sizes["height"])*.5;
  if(shape->type==PhysicsServer3D::SHAPE_CAPSULE){query.size[1]-=query.size[0];query.type=query.size[1]==0?mjGEOM_SPHERE:mjGEOM_CAPSULE;}else query.type=mjGEOM_CYLINDER;
 }else if(shape->type==PhysicsServer3D::SHAPE_WORLD_BOUNDARY){query.type=mjGEOM_PLANE;Plane plane=shape->data;Vector3 n=plane.normal.normalized();pose.origin+=pose.basis.xform(n*(plane.d/plane.normal.length()));pose.basis=pose.basis*Basis(Quaternion(Vector3(0,1,0),n));}
 else{query_problem("continuous convex query shape");return false;}
 for(double extent:query.size)if(!std::isfinite(extent)||extent<0||extent>std::numeric_limits<real_t>::max())return false;
 query.margin=margin;Quaternion rotation=godot_to_mj(pose.basis).get_rotation_quaternion().normalized();
 mjtNum quaternion[4]={rotation.w,rotation.x,rotation.y,rotation.z};mju_normalize4(quaternion);mju_quat2Mat(query.matrix,quaternion);
 if(!mask||(!bodies&&!areas)){*safe=*unsafe=1;return true;}
 auto*space=query_space(state,mask,bodies,areas);if(!space)return false;
 bool area_valid=true;std::vector<AreaQueryGeom> area_geoms;if(areas)area_geoms=area_query_geometries(state,mask,false,area_valid);if(!area_valid)return false;
 Vector3 base_g=godot_to_mj(pose.origin),velocity_g=godot_to_mj(motion);Vec base{base_g.x,base_g.y,base_g.z},velocity{velocity_g.x,velocity_g.y,velocity_g.z};
 std::vector<GeneralCastTarget> targets;
 if(bodies)for(int geom=0;geom<space->model->ngeom;++geom){auto*owner=query_body(state,*space,geom,mask);if(!owner)continue;
  int type=space->model->geom_type[geom];
  if(type==mjGEOM_SDF&&(query.type==mjGEOM_PLANE||space->model->geom_plugin[geom]>=0)){query_problem("continuous SDF requires a finite primitive and native plugin-free octree");return false;}
  if(type==mjGEOM_HFIELD&&query.type==mjGEOM_PLANE){query_problem("continuous unbounded plane versus hfield");return false;}
  if(type==mjGEOM_PLANE&&query.type==mjGEOM_PLANE){query_problem("continuous plane/plane sweep");return false;}
  if(type==mjGEOM_MESH&&(space->model->geom_dataid[geom]<0||space->model->mesh_polynum[space->model->geom_dataid[geom]]<=0)){query_problem("continuous convex mesh has no compiled hull");return false;}
  GeneralCastTarget target;target.owner=owner;
  if(type==mjGEOM_SDF){target.sdf_field=sdf_field_for(*space,geom);target.sdf_data=space->data;target.world_base=base;if(!target.sdf_field->valid){query_problem("SDF octree interval representation is invalid or exceeds budget");return false;}}
target.shape=space->geom_owners[geom].second;target.geom=geom;target.object.type=type;target.object.assets=space->model;target.object.mesh=space->model->geom_dataid[geom];
  mju_copy3(target.object.size,space->model->geom_size+3*geom);mju_copy(target.object.matrix,space->data->geom_xmat+9*geom,9);
  const mjtNum*p=space->data->geom_xpos+3*geom;target.object.position=Vec{p[0],p[1],p[2]}-base;
  if(type==mjGEOM_HFIELD){
   int id=space->model->geom_dataid[geom],rows=space->model->hfield_nrow[id],cols=space->model->hfield_ncol[id];
   if((rows-1)*(cols-1)>2048){query_problem("continuous hfield exceeds 2048-cell query budget");return false;}
   const mjtNum*z=space->model->hfield_size+4*id;const float*h=space->model->hfield_data+space->model->hfield_adr[id];
   // The heightfield solid is exactly the union of its triangular prisms:
   // no convex hull over a depression and no temporal/discrete sampling.
   for(int row=0;row<rows-1;++row)for(int col=0;col<cols-1;++col){
    Vec v[4];int dc[4]={0,1,1,0},dr[4]={0,0,1,1};
    for(int j=0;j<4;++j)v[j]={-z[0]+2*z[0]*(col+dc[j])/(cols-1),-z[1]+2*z[1]*(row+dr[j])/(rows-1),h[(row+dr[j])*cols+col+dc[j]]*z[2]};
    for(auto triangle: {std::array<int,3>{0,1,2},std::array<int,3>{0,2,3}}){auto prism=target;prism.object.type=mjGEOM_MESH;prism.object.assets=nullptr;
     for(int index:triangle)prism.object.vertices.push_back(v[index]);
     for(int index:triangle)prism.object.vertices.push_back({v[index].x,v[index].y,-z[3]});
     targets.push_back(std::move(prism));
    }
   }
  }else targets.push_back(std::move(target));
 }
 for(const auto&geom:area_geoms){GeneralCastTarget target;target.owner=geom.owner.get();target.area_owner=geom.owner;target.shape=geom.shape;target.object.type=geom.type;mju_copy3(target.object.size,geom.size);mju_copy(target.object.matrix,geom.matrix,9);target.object.position=Vec{geom.position[0],geom.position[1],geom.position[2]}-base;targets.push_back(std::move(target));}
 for(auto&target:targets)if(target.sdf_field)target.sdf_stats=std::make_shared<gmj_sdf::Stats>();
 auto record_sdf_stats=[&](){
  int intervals=0,boxes=0,nodes=0,geoms=0;bool exhausted=false;double lipschitz=0;
  for(const auto&t:targets)if(t.sdf_stats){++geoms;intervals+=t.sdf_stats->intervals;boxes+=t.sdf_stats->boxes;nodes+=t.sdf_stats->field_nodes;exhausted|=t.sdf_stats->exhausted;lipschitz=std::max(lipschitz,t.sdf_field->local_lipschitz_bound);}
  Array per_geom;for(const auto&t:targets)if(t.sdf_stats){Dictionary row;row["geom"]=t.geom;row["mesh"]=t.object.mesh;row["field_nodes"]=t.sdf_stats->field_nodes;row["boxes"]=t.sdf_stats->boxes;row["precision_candidate"]=t.sdf_stats->precision_candidate;row["proven_safe_fraction"]=t.sdf_stats->proven_safe;row["best_hit_upper_fraction"]=t.sdf_stats->best_upper;row["upper_candidate_tests"]=t.sdf_stats->upper_candidate_tests;row["intervals"]=t.sdf_stats->intervals;row["geometry_error_per_axis_m"]=t.sdf_geometry_envelope;row["exhausted"]=t.sdf_stats->exhausted;per_geom.push_back(row);}
  if(geoms){state.query_details["sdf_per_geom"]=per_geom;state.query_details["sdf_geoms"]=geoms;state.query_details["sdf_interval_nodes"]=intervals;state.query_details["sdf_spatial_boxes"]=boxes;state.query_details["sdf_field_nodes"]=nodes;state.query_details["sdf_budget_exhausted"]=exhausted;state.query_details["sdf_max_leaf_lipschitz_bound"]=lipschitz;state.query_details["sdf_budget_seconds"]=2;state.query_details["sdf_requested_spatial_bracket_m"]=state.sdf_query_precision_m>0?state.sdf_query_precision_m:4e-6;state.query_details["sdf_realtime_recommended"]=false;state.query_details["sdf_query_precision_m"]=state.sdf_query_precision_m;state.query_details["sdf_upper_refinement"]=state.sdf_upper_refinement;state.query_details["sdf_precision_scope"]="compiled native SDF path-event bracket; not source mesh approximation";state.query_details["sdf_stats_scope"]="all SDF path searches and final pose checks";}
 };
 std::set<std::pair<uint64_t,int>> initial_shapes;
 for(const auto&target:targets)if(!target.object.vertices.empty()){auto d=general_evaluate(query,target,{});if(!d.valid){query_problem("initial hfield overlap not certified");return false;}if(d.inside)initial_shapes.insert({target.owner->rid.get_id(),target.shape});}
 double first=2,lower=1;int nearest=-1;Vec point{},normal{};std::vector<size_t> deferred_prisms;
 for(size_t index=0;index<targets.size();++index){auto&target=targets[index];gmj_sweep::Result hit;
  if(initial_shapes.count({target.owner->rid.get_id(),target.shape})){target.ignored=true;continue;}
  if(target.sdf_field){
   auto world=query;world.position=base;
   if(!sdf_certification_domain(world,target.sdf_data,target.geom,velocity)){query_problem("SDF cast exceeds certified coordinate/shape domain");return false;}
   target.sdf_geometry_envelope=sdf_geometry_error(world,target.sdf_data,target.geom,velocity,0,1);
   auto local_support=sdf_local_support(world,target.sdf_data,target.geom);
   mjtNum v[3]={velocity.x,velocity.y,velocity.z},local[3];mju_mulMatTVec3(local,target.sdf_data->geom_xmat+9*target.geom,v);
   auto contact=[&](double t){auto q=world;q.position=base+velocity*t;mjPreContact c{};bool strict=false;Vec normal{};gmj_convex::Distance d;d.valid=true;
    if(sdf_contact(q,target.object.assets,target.sdf_data,target.geom,c,strict,&normal,target.sdf_geometry_envelope)){
     d.inside=strict;d.point=Vec{c.pos[0]+.5*c.dist*c.normal[0],c.pos[1]+.5*c.dist*c.normal[1],c.pos[2]+.5*c.dist*c.normal[2]}-base;d.normal=normal;
     if(state.sdf_query_precision_m>0&&strict){
      Vector3 actual_position=godot_to_mj(pose.origin+motion*float(t));auto actual=q;actual.position={actual_position.x,actual_position.y,actual_position.z};mjPreContact actual_contact{};bool actual_strict=false;
      if(!sdf_contact(actual,target.object.assets,target.sdf_data,target.geom,actual_contact,actual_strict,nullptr,target.sdf_geometry_envelope)||!actual_strict)d.inside=false;
     }
    }return d;
   };
   gmj_sdf::PrecisionBracket finite_bracket;
   if(state.sdf_query_precision_m>0)finite_bracket=[&](double proven_safe,double hit_upper,double&return_safe,double&return_unsafe){
    double candidate=std::max(0.0,proven_safe-.05*state.sdf_query_precision_m/std::max(1e-30,velocity.length()));
    float lo=float(candidate);if(double(lo)>candidate)lo=std::nextafter(lo,0.f);
    float hi=float(hit_upper);if(double(hi)<hit_upper)hi=std::nextafter(hi,1.f);
    auto budget=sdf_precision_budget(pose,motion,lo,hi,target.sdf_geometry_envelope);
    if(!std::isfinite(budget.total)||budget.total>state.sdf_query_precision_m)return false;
    return_safe=lo;return_unsafe=hi;return true;
   };
   auto&stats=*target.sdf_stats;hit=gmj_sdf::cast(*target.sdf_field,local_support,{local[0],local[1],local[2]},contact,stats,[&](double,double){return target.sdf_geometry_envelope;},state.sdf_query_precision_m,finite_bracket,state.sdf_upper_refinement);
   record_sdf_stats();
  }else if(query.type==mjGEOM_PLANE||target.object.type==mjGEOM_PLANE){auto initial=general_evaluate(query,target,{});
   hit=gmj_sweep::plane(initial.signed_gap,velocity.dot(initial.normal));auto at=general_evaluate(query,target,velocity*hit.unsafe);hit.point=at.point;hit.normal=at.normal;
  }else{
   auto evaluate=[&](double t){auto a=query;a.position=velocity*t;return convex_distance(a,target.object);};
   hit=gmj_convex::cast(evaluate,velocity);
  }
  if(!hit.valid){if(target.sdf_field){query_problem("continuous SDF interval proof remained unresolved or exceeded budget");return false;}if(!target.object.vertices.empty()){deferred_prisms.push_back(index);continue;}query_problem("continuous convex numerical bounds not certified");return false;}
  target.ignored=hit.initial_overlap;if(!hit.hit)continue;lower=std::min(lower,hit.safe);
  bool tie=hit.unsafe==first&&nearest>=0&&std::make_pair(target.owner->rid.get_id(),target.shape)<std::make_pair(targets[nearest].owner->rid.get_id(),targets[nearest].shape);
  if(hit.unsafe<first||tie){first=hit.unsafe;nearest=int(index);point=hit.point;normal=hit.normal;}
 }
 // Shared prism faces can be tangent after the union's actual first hit.
 // For such a prism, certify only the prefix before the already established
 // union bracket. A clear endpoint alone is never used as that certificate.
 for(size_t index:deferred_prisms){auto&target=targets[index];
  if(nearest<0||target.geom!=targets[nearest].geom){query_problem("continuous hfield prism bounds not certified");return false;}
  double cap=lower;auto evaluate=[&](double t){auto a=query;a.position=velocity*(t*cap);return convex_distance(a,target.object);};
  auto hit=gmj_convex::cast(evaluate,velocity*cap);
  if(!hit.valid){query_problem("continuous hfield safe prefix not certified");return false;}
  if(hit.hit){lower=std::min(lower,hit.safe*cap);if(hit.unsafe*cap<first){first=hit.unsafe*cap;nearest=int(index);point=hit.point;normal=hit.normal;}}
 }
 if(nearest<0){record_sdf_stats();*safe=*unsafe=1;return true;}
 auto rounded=[&](float t){Vector3 p=transform.origin+motion*t;if(query.type==mjGEOM_PLANE){Plane plane=shape->data;p+=transform.basis.xform(plane.normal.normalized()*(plane.d/plane.normal.length()));}Vector3 q=godot_to_mj(p);return Vec{q.x,q.y,q.z}-base;};
 auto safe_at=[&](float t){for(const auto&target:targets)if(!target.ignored){auto continuous=general_evaluate(query,target,velocity*t),actual=general_evaluate(query,target,rounded(t));if(!continuous.valid||!actual.valid||continuous.inside||actual.inside||(!continuous.boundary&&continuous.lower<=0)||(!actual.boundary&&actual.lower<=0))return false;}return true;};
 auto unsafe_at=[&](float t){auto c=general_evaluate(query,targets[nearest],velocity*t),a=general_evaluate(query,targets[nearest],rounded(t));return c.valid&&a.valid&&(c.inside||c.boundary)&&(a.inside||a.boundary);};
 float lo=float(lower),hi=float(first);if(double(lo)>lower)lo=std::nextafter(lo,0.f);if(double(hi)<first)hi=std::nextafter(hi,1.f);lo=std::nextafter(lo,0.f);
 // Leave a few API fraction ULPs for the independently rounded Godot pose.
 // This widens only the safe side; every returned pose is still certified.
 if(std::any_of(targets.begin(),targets.end(),[](const auto&t){return bool(t.sdf_field);}))for(int i=0;i<8&&lo>0;++i)lo=std::nextafter(lo,0.f);
 bool lo_ok=safe_at(lo),hi_ok=unsafe_at(hi);for(int i=0;!lo_ok&&lo>0&&i<8;++i){lo=std::nextafter(lo,0.f);lo_ok=safe_at(lo);}for(int i=0;!hi_ok&&hi<1&&i<8;++i){hi=std::nextafter(hi,1.f);hi_ok=unsafe_at(hi);}
 // Fraction ULPs alone do not bound a Float32 world pose after adding a
 // large origin. Derive a wider bracket from each position/product ULP.
 // These are only candidate endpoints: both actual poses must still pass.
 if(!lo_ok||!hi_ok){
  double quantum=0;
  for(int k=0;k<3;++k){float p=(transform.origin+motion*hi)[k],travel=motion[k]*hi;
   auto ulp=[](float x){return double(std::nextafter(x,std::numeric_limits<float>::infinity()))-double(x);};
   if(motion[k]!=0)quantum=std::max(quantum,2*(ulp(p)+ulp(travel))/std::abs(double(motion[k])));
  }
  for(int attempt=0;attempt<4&&(!lo_ok||!hi_ok);++attempt){double step=quantum*(1<<attempt);
   if(!lo_ok){lo=float(std::max(0.0,double(lo)-step));lo_ok=safe_at(lo);}
   if(!hi_ok){hi=float(std::min(1.0,double(hi)+step));hi_ok=unsafe_at(hi);}
  }
  state.query_details["float_pose_fraction_quantum"]=quantum;
 }
 record_sdf_stats();
 state.query_details["safe_pose_verified"]=lo_ok;state.query_details["unsafe_pose_verified"]=hi_ok;
 state.query_details["safe_fraction"]=lo;state.query_details["unsafe_fraction"]=hi;state.query_details["returned_bracket_path_length_m"]=(double(hi)-double(lo))*velocity.length();
 double maximum_geometry_error=0;bool has_sdf=false;for(const auto&t:targets)if(t.sdf_field){has_sdf=true;maximum_geometry_error=std::max(maximum_geometry_error,t.sdf_geometry_envelope);}
 if(has_sdf&&state.sdf_query_precision_m>0){
  auto budget=sdf_precision_budget(pose,motion,lo,hi,maximum_geometry_error);
  state.query_details["sdf_path_bracket_m"]=budget.path;state.query_details["sdf_coordinate_error_lower_m"]=budget.coordinate_lower;state.query_details["sdf_coordinate_error_upper_m"]=budget.coordinate_upper;state.query_details["sdf_arithmetic_error_per_endpoint_m"]=budget.arithmetic;state.query_details["sdf_total_uncertainty_m"]=budget.total;state.query_details["sdf_precision_met"]=budget.total<=state.sdf_query_precision_m;
  if(!std::isfinite(budget.total)||budget.total>state.sdf_query_precision_m){query_problem("SDF cast total spatial uncertainty exceeds requested precision");return false;}
 }
 if(!lo_ok||!hi_ok){query_problem("continuous convex contact has no certified float safe/unsafe poses");return false;}
 if(info){auto&target=targets[nearest];Vec global=point+base;mjtNum p_mj[3]={global.x,global.y,global.z},hint[3]={normal.x,normal.y,normal.z};
  Vector3 p=mj_to_godot(Vector3(global.x,global.y,global.z)),n;
  if(target.geom>=0){
   if(surface_error(space->model,space->data,target.geom,p_mj)>1e-5*std::max(1.0,space->model->geom_rbound[target.geom])){query_problem("continuous target surface witness not certified");return false;}
   n=witness_normal(space->model,space->data,target.geom,p_mj,hint);
  }else{
   mjModel view{};mjData poses{};int kind=target.object.type;mjtNum rbound=std::max(1.0,mju_norm3(target.object.size)),position[3]={target.object.position.x+base.x,target.object.position.y+base.y,target.object.position.z+base.z};
   view.geom_type=&kind;view.geom_size=target.object.size;view.geom_rbound=&rbound;poses.geom_xpos=position;poses.geom_xmat=target.object.matrix;
   if(surface_error(&view,&poses,0,p_mj)>1e-5*rbound){query_problem("continuous Area surface witness not certified");return false;}n=witness_normal(&view,&poses,0,p_mj,hint);
  }
  if(!p.is_finite()||!n.is_finite()||std::abs(n.length_squared()-1)>1e-5){query_problem("continuous target normal not certified");return false;}
  rest_result(*space,*target.owner,target.shape,p,n,*info);
 }
 *safe=std::clamp(lo,0.f,1.f);*unsafe=std::clamp(hi,0.f,1.f);return true;
}
} // namespace
bool MjDirectSpaceState::_cast_motion(const RID &shape, const Transform3D &pose, const Vector3 &motion,
    float margin,uint32_t mask,bool bodies,bool areas,float *safe,float *unsafe,PhysicsServer3DExtensionShapeRestInfo *info) {
 QueryScope query_scope(*this,"cast");
 bool general=areas;auto*query_shape=server?server->shape(shape):nullptr;
 if(query_shape&&(query_shape->type==PhysicsServer3D::SHAPE_BOX||query_shape->type==PhysicsServer3D::SHAPE_CYLINDER))general=true;
 if(!general&&server){auto*space=server->space(rid);if(space&&server->rebuild(*space)&&space->model)for(int g=0;g<space->model->ngeom;++g)if(query_body(*this,*space,g,mask)&&!primitive(space->model->geom_type[g])){general=true;break;}}
 bool ok=general?general_cast(*this,shape,pose,motion,margin,mask,bodies,areas,safe,unsafe,info):cast_motion_impl(*this,shape,pose,motion,margin,mask,bodies,areas,safe,unsafe,info);
 if(!ok&&query_error.is_empty())query_problem("continuous cast input or numerical bounds were not certified");return ok;
}

bool MjDirectSpaceState::_collide_shape(const RID &shape, const Transform3D &pose, const Vector3 &motion,
    float margin, uint32_t mask, bool bodies, bool areas, void *results, int32_t max_results, int32_t *count) {
 QueryScope query_scope(*this,"collide");
 if(count) *count=0;
 if(!count || !results || max_results<=0) return false;
 bool valid=false;auto hits=overlaps(*this,shape,pose,motion,margin,mask,bodies,areas,nullptr,&valid);if(!valid){if(query_error.is_empty())query_problem("overlap input or witness was not certified");return false;}
 auto *points=static_cast<Vector3 *>(results);
 for(const auto &hit:hits) {
   points[2*(*count)]=contact_point(hit,true); points[2*(*count)+1]=contact_point(hit,false);
   if(++(*count)==max_results) break;
 }
 return *count>0;
}

bool MjDirectSpaceState::_rest_info(const RID &shape, const Transform3D &pose, const Vector3 &motion,
    float margin, uint32_t mask, bool bodies, bool areas, PhysicsServer3DExtensionShapeRestInfo *info) {
 QueryScope query_scope(*this,"rest");
 if(!info) return false; *info={};
 bool valid=false;auto hits=overlaps(*this,shape,pose,motion,margin,mask,bodies,areas,nullptr,&valid); if(!valid){if(query_error.is_empty())query_problem("overlap input or witness was not certified");return false;}if(hits.empty())return false;
 const auto &hit=*std::min_element(hits.begin(),hits.end(),[](const Overlap &a,const Overlap &b){return a.contact.dist<b.contact.dist;});
 rest_result(*server->space(rid),*hit.body,hit.shape,contact_point(hit,false),hit.target_normal,*info);
 return true;
}

Vector3 MjDirectSpaceState::_get_closest_point_to_object_volume(const RID &, const Vector3 &) const {
 QueryScope query_scope(*this,"closest_point");
	query_problem("direct-space get_closest_point_to_object_volume");
	return Vector3();
}


bool MjPhysicsServer3D::_body_test_motion(const RID &body_rid,const Transform3D &from,const Vector3 &motion,
    float margin,int32_t max_collisions,bool collide_separation_ray,bool recovery_as_collision,
    PhysicsServer3DExtensionMotionResult *output) const {
 PhysicsServer3DExtensionMotionResult local{};auto &result=output?*output:local;result={};
 result.travel=motion;result.collision_safe_fraction=result.collision_unsafe_fraction=1;
 auto *moving=body(body_rid);auto *world=moving?space(moving->space):nullptr;
 auto blocked=[&](const char *reason) {
   query_problem(reason);result={};result.remainder=motion;return false;
 };
 if(!moving || !world || pending_free.count(body_rid.get_id()) || !from.is_finite() || !motion.is_finite() ||
     !from.basis.is_orthogonal() || !from.basis.get_scale().is_equal_approx(Vector3(1,1,1)) || from.basis.determinant()<=0 ||
     !std::isfinite(margin) || margin<0 || max_collisions<1 || max_collisions>32)
   return blocked("body motion invalid input or missing space");
 std::vector<int> shapes;
 for(int i=0;i<int(moving->shapes.size());++i) {
   const auto &instance=moving->shapes[i];if(instance.disabled)continue;
   auto*s=shape(instance.shape);
   if(!s || pending_free.count(instance.shape.get_id()))continue;
   if(s->type!=SHAPE_SPHERE && s->type!=SHAPE_CAPSULE)
     return blocked("body motion moving shapes (sphere/capsule only)");
   shapes.push_back(i);
 }
 // Separation-ray shapes cannot be created in this stage. The flag only
 // selects such shapes if present; it does not change sphere/capsule behavior.
 (void)collide_separation_ray;
 if(shapes.empty() || !moving->mask)return false;
 auto &state=*world->direct;
 if(!query_space(state,moving->mask,true,false))return blocked("body motion space rebuild failed");
 std::vector<PhysicsServer3DExtensionMotionCollision> recovered,collisions;
 auto collision=[&](const Overlap &hit,int index,double depth) {
   PhysicsServer3DExtensionMotionCollision c{};PhysicsServer3DExtensionShapeRestInfo rest;
   rest_result(*world,*hit.body,hit.shape,contact_point(hit,false),hit.target_normal,rest);
   c.position=rest.point;c.normal=rest.normal;c.collider_velocity=rest.linear_velocity;
   c.collider_angular_velocity=hit.body->angular_velocity;c.depth=std::max(0.0,depth);
   c.local_shape=index;c.collider_id=rest.collider_id;c.collider=rest.rid;c.collider_shape=rest.shape;return c;
 };
 auto remember=[](auto &items,const auto &c) {
   for(auto &old:items)if(old.collider==c.collider && old.collider_shape==c.collider_shape && old.local_shape==c.local_shape) {
     if(c.depth>old.depth)old=c;return;
   }
   items.push_back(c);
 };
 Transform3D pose=from;
 // Recovery must leave every shape outside the margin before cast_motion,
 // whose separate public contract ignores initial penetrations. A bounded
 // failure stops travel explicitly instead of silently ignoring a wall.
 // Slop is geometric, not proportional to unrelated world coordinates.
 // Certify actual per-shape displacement below instead of inflating recovery
 // by the largest body-origin ULP (e.g. huge X must not inflate floor Y).
 constexpr double epsilon=1e-6;
 struct RecoveryConstraint {Vector3 normal;double depth;int shape;};
 bool clear=false;
 for(int iteration=0;iteration<16;++iteration) {
   std::vector<RecoveryConstraint> constraints;Vector3 correction;
   for(int index:shapes) {
     const auto &instance=moving->shapes[index];bool valid;
     auto hits=overlaps(state,instance.shape,pose*instance.transform,{},margin,moving->mask,true,false,moving,&valid);
     if(!valid)return blocked("body motion recovery witness unavailable");
     for(const auto &hit:hits) {
       double depth=double(margin)-hit.contact.dist;
       if(depth>0) {
         remember(recovered,collision(hit,index,depth));
         constraints.push_back({hit.target_normal,depth,index});
       }
     }
   }
   if(constraints.empty()) {clear=true;break;}
   // Solve all current contact half-spaces together. Recomputing just the
   // deepest contact after each push can change its side and teleport a wedged
   // body through one of two opposing obstacles.
   bool feasible=false;
   for(int pass=0;pass<32;++pass) {
     for(const auto &c:constraints) {
       double deficit=c.depth-c.normal.dot(correction);
       if(deficit>0)correction+=c.normal*(deficit+epsilon);
     }
     feasible=true;for(const auto &c:constraints)if(c.normal.dot(correction)<c.depth){feasible=false;break;}
     if(feasible)break;
   }
   if(!feasible)return blocked("body motion recovery did not converge");
   if(!correction.is_finite() || pose.origin+correction==pose.origin)return blocked("body motion recovery has no representable displacement");
   Transform3D next=pose;next.origin+=correction;
   for(const auto &c:constraints) {
     const auto &instance=moving->shapes[c.shape];
     Vector3 actual=(next*instance.transform).origin-(pose*instance.transform).origin;
     if(!actual.is_finite() || double(c.normal.dot(actual))<c.depth)
       return blocked("body motion recovery has no certified directional displacement");
   }
   pose=next;
 }
 if(!clear)return blocked("body motion recovery did not converge");
 float safe=1,unsafe=1;PhysicsServer3DExtensionShapeRestInfo nearest{};int local_shape=-1;
 for(int index:shapes) {
   const auto &instance=moving->shapes[index];float lo,hi;PhysicsServer3DExtensionShapeRestInfo rest{};
   if(!cast_motion_impl(state,instance.shape,pose*instance.transform,motion,margin,moving->mask,true,false,&lo,&hi,&rest,moving))
     return blocked("body motion continuous sweep could not be certified");
   safe=std::min(safe,lo);
   if(rest.rid.is_valid() && (local_shape<0 || hi<unsafe)) {unsafe=hi;nearest=rest;local_shape=index;}
 }
 // Certify the actual BODY application order, including local-shape offsets.
 // (from.origin + travel) * local is not necessarily shape_origin + motion*f
 // in float. Endpoint overlap alone cannot detect jumping across a thin wall,
 // so re-sweep every shape along its actual resulting displacement.
 auto body_travel=[&](float fraction,Vector3 &travel,Vector3 &progress) {
   // Report requested vector arithmetic, as Godot does, rather than the
   // subtraction of two large rounded origins (which can exceed the request).
   progress=motion*fraction;travel=pose.origin-from.origin+progress;
   Transform3D end=from;end.origin+=travel;
   if(!travel.is_finite() || !end.is_finite())return false;
   for(int index:shapes) {
     const auto &instance=moving->shapes[index];Transform3D start=pose*instance.transform,finish=end*instance.transform;
     Vector3 actual=finish.origin-start.origin;float lo,hi;PhysicsServer3DExtensionShapeRestInfo hit{};
     if(!cast_motion_impl(state,instance.shape,start,actual,margin,moving->mask,true,false,&lo,&hi,&hit,moving))return false;
     if(hit.rid.is_valid()) {
       // Rounding can introduce an endpoint contact absent from the ideal
       // path. Retain it only when the actual endpoint has a valid witness;
       // then fraction itself is a certified unsafe body pose. A jump past
       // an obstacle without such an endpoint remains an explicit rejection.
       if(local_shape<0) {
         bool valid;auto endpoint=overlaps(state,instance.shape,finish,{},margin,moving->mask,true,false,moving,&valid);
         if(valid)for(const auto &contact:endpoint)if(contact.body->rid==hit.rid && contact.shape==hit.shape) {
           nearest=hit;local_shape=index;unsafe=fraction;break;
         }
       }
       return false;
     }
   }
   if(end.origin==pose.origin) {progress={};travel=pose.origin-from.origin;}
   return true;
 };
 Vector3 travel,progress;
 if(!body_travel(safe,travel,progress)) {
   // A rounded path can hit a target absent from the ideal path. Do not
   // silently shorten a supposedly clear motion without collision metadata.
   if(local_shape<0)return blocked("body motion rounded path introduced an uncertified collision");
   Vector3 fallback,ignored;
   if(!body_travel(0,fallback,ignored))return blocked("body motion final body pose could not be certified");
   float a=0,b=safe;
   for(int i=0;i<64;++i) {float mid=a+(b-a)*.5f;if(mid<=a||mid>=b)break;
     Vector3 candidate,advance;if(body_travel(mid,candidate,advance))a=mid;else b=mid;
   }
   safe=a;
   if(!body_travel(safe,travel,progress))return blocked("body motion final body pose could not be certified");
 }
 result.travel=travel;result.remainder=motion-progress;
 if(motion.length_squared()>0)safe=std::min(safe,float(std::clamp(double(progress.dot(motion))/motion.length_squared(),0.0,1.0)));

 if(local_shape>=0) {
   // Certify unsafe using the same BODY + travel + local transform order as
   // the caller. Shape-space contact alone cannot certify this float pose.
   auto unsafe_contacts=[&](float fraction) {
     collisions.clear();bool matched=false;
     Transform3D contact_pose=from;contact_pose.origin+=pose.origin-from.origin+motion*fraction;
     for(int index:shapes) {
       const auto &instance=moving->shapes[index];bool valid;
       auto hits=overlaps(state,instance.shape,contact_pose*instance.transform,{},margin,moving->mask,true,false,moving,&valid);
       if(!valid)return false;
       for(const auto &hit:hits) {
         bool selected=index==local_shape && hit.body->rid==nearest.rid && hit.shape==nearest.shape;
         if(selected || hit.target_normal.dot(motion)<0)
           remember(collisions,collision(hit,index,double(margin)-hit.contact.dist));
         matched|=selected;
       }
     }
     return matched;
   };
   bool certified=unsafe_contacts(unsafe);
   for(int i=0;!certified && unsafe<1 && i<256;++i) {
     unsafe=std::nextafter(unsafe,1.0f);certified=unsafe_contacts(unsafe);
   }
   // Near zero, fraction ULPs can be much smaller than a body-position ULP.
   // A certified endpoint can bound refinement after continuous detection;
   // never infer a contact from an uncertified endpoint or sparse samples.
   if(!certified && unsafe_contacts(1)) {
     float a=unsafe,b=1;
     for(int i=0;i<64;++i) {float mid=a+(b-a)*.5f;if(mid<=a||mid>=b)break;
       if(unsafe_contacts(mid))b=mid;else a=mid;
     }
     unsafe=b;certified=unsafe_contacts(unsafe);
   }
   if(!certified)return blocked("body motion unsafe body pose has no certified contact");
 } else if(recovery_as_collision)collisions=recovered;
 result.collision_safe_fraction=safe;result.collision_unsafe_fraction=unsafe;
 std::stable_sort(collisions.begin(),collisions.end(),[](const auto &a,const auto &b) {
   if(a.depth!=b.depth)return a.depth>b.depth;
   if(a.collider!=b.collider)return a.collider.get_id()<b.collider.get_id();
   if(a.collider_shape!=b.collider_shape)return a.collider_shape<b.collider_shape;
   return a.local_shape<b.local_shape;
 });
 result.collision_count=std::min(max_collisions,int(collisions.size()));
 for(int i=0;i<result.collision_count;++i){result.collisions[i]=collisions[i];result.collision_depth=std::max(result.collision_depth,collisions[i].depth);}
 return result.collision_count>0;
}

} // namespace godot
