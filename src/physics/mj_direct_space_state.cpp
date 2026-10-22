#include "mj_physics_server.h"
#include "mj_sweep.h"
#include "query_ccd/witness.h"

#include <godot_cpp/core/object.hpp>

#include <algorithm>
#include <cmath>
#include <limits>

namespace godot {
namespace {

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
MjBody *query_body(MjDirectSpaceState &state, MjSpace &space, int geom, uint32_t mask, bool pick = false) {
 const auto &owner = space.geom_owners[geom];
 auto *body = state.server->body(owner.first);
 if (!body || state.server->pending_free.count(owner.first.get_id()) || body->space != state.rid || owner.second < 0 ||
     size_t(owner.second) >= body->shapes.size() || body->shapes[owner.second].disabled ||
     !state.server->shape(body->shapes[owner.second].shape) ||
     state.server->pending_free.count(body->shapes[owner.second].shape.get_id()) ||
     !(body->layer & mask) || (pick && !body->ray_pickable) ||
     state.is_body_excluded_from_query(owner.first)) return nullptr;
 return body;
}
MjSpace *query_space(MjDirectSpaceState &state, uint32_t mask, bool bodies, bool areas) {
 if (areas) mj_unsupported("Area3D overlap queries");
 if (!state.server || state.server->pending_free.count(state.rid.get_id()) || !bodies || !mask) return nullptr;
 auto *space = state.server->space(state.rid);
 if (!space || !state.server->rebuild(*space) || !space->model || !space->data ||
     space->geom_owners.size() != size_t(space->model->ngeom)) return nullptr;
 return space;
}
bool primitive(int type) {
 return type == mjGEOM_BOX || type == mjGEOM_SPHERE || type == mjGEOM_CYLINDER || type == mjGEOM_PLANE;
}
PhysicsServer3DExtensionShapeResult shape_result(MjBody &body, int shape) {
 PhysicsServer3DExtensionShapeResult result{};
 result.rid = body.rid; result.collider_id = ObjectID(body.object_id); result.shape = shape;
 Object *object = body.object_id ? ObjectDB::get_instance(body.object_id) : nullptr;
 result.collider = object ? reinterpret_cast<Object *>(object->_owner) : nullptr;
 return result;
}
struct Overlap {
 MjBody *body; int shape; mjPreContact contact; bool reversed; Vector3 target_normal;
};
Vector3 contact_point(const Overlap &hit, bool query);

gmj_sweep::Vec support(int type, const mjtNum *size, const mjtNum *matrix, gmj_sweep::Vec n);
// Analytic signed-distance magnitude to the original primitive surface. This
// checks actual ownership, not just whether a narrowphase produced a contact.
double surface_error(const mjModel *model, const mjData *data, int geom, const mjtNum *point) {
 mjtNum offset[3],p[3]; mju_sub3(offset,point,data->geom_xpos+3*geom);
 mju_mulMatTVec3(p,data->geom_xmat+9*geom,offset);
 const mjtNum *size=model->geom_size+3*geom;
 switch(model->geom_type[geom]) {
 case mjGEOM_SPHERE:return std::abs(mju_norm3(p)-size[0]);
 case mjGEOM_PLANE:return std::abs(p[2]);
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
     ea<=1e-6*std::max(1.0,model->geom_rbound[a]) && eb<=1e-6*std::max(1.0,model->geom_rbound[b]);
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
 if(type==mjGEOM_SPHERE) mju_copy3(n,p);
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
// The scratch model has no ownership or dynamics relationship to the live space.
// Dispatching MuJoCo narrowphase directly neither runs forward nor steps live data.
std::vector<Overlap> overlaps(MjDirectSpaceState &state, const RID &rid, const Transform3D &transform,
    const Vector3 &motion, float margin, uint32_t mask, bool bodies, bool areas) {
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
 case PhysicsServer3D::SHAPE_WORLD_BOUNDARY: {
   Plane p=shape->data;
   if (!std::isfinite(p.normal.length()) || !std::isfinite(p.d)) return hits;
   Vector3 n=p.normal.normalized();
   pose.origin += pose.basis.xform(n*(p.d/p.normal.length()));
   pose.basis = pose.basis*Basis(Quaternion(Vector3(0,1,0),n));
   type=mjGEOM_PLANE; size[2]=.1; break;
 }
 default: mj_unsupported("overlap query shape (only native primitives supported)"); return hits;
 }
 if (!pose.is_finite()) return hits;
 for (mjtNum extent : size) if (!std::isfinite(extent) || extent < 0 || extent > std::numeric_limits<real_t>::max()) return hits;
 auto *space = query_space(state,mask,bodies,areas); if (!space) return hits;
 std::unique_ptr<mjSpec, decltype(&mj_deleteSpec)> spec(mj_makeSpec(),mj_deleteSpec);
 for (int i=0;i<2;++i) { auto *g=mjs_addGeom(mjs_findBody(spec.get(),"world"),nullptr); g->type=mjGEOM_SPHERE; g->size[0]=1; }
 std::unique_ptr<mjModel, decltype(&mj_deleteModel)> model(mj_compile(spec.get(),nullptr),mj_deleteModel);
 if (!model) return hits;
 std::unique_ptr<mjData, decltype(&mj_deleteData)> data(mj_makeData(model.get()),mj_deleteData);
 if (!data) return hits;
 model->geom_type[0]=type; mju_copy3(model->geom_size,size);
 model->geom_rbound[0]=type==mjGEOM_SPHERE?size[0]:mju_norm3(size);
 Vector3 pos=godot_to_mj(pose.origin);
 Quaternion rotation=godot_to_mj(pose.basis).get_rotation_quaternion().normalized();
 mjtNum quat[4]={rotation.w,rotation.x,rotation.y,rotation.z};mju_normalize4(quat);mju_quat2Mat(data->geom_xmat,quat);
 for (int a=0;a<3;++a) data->geom_xpos[a]=pos[a];
 for (int geom=0;geom<space->model->ngeom;++geom) {
   auto *body=query_body(state,*space,geom,mask); if (!body) continue;
   int target=space->model->geom_type[geom];
   // Heightfields need their own asset-aware path; imported geoms have no native owner.
   if (!primitive(target)) { mj_unsupported("heightfield/nonprimitive overlap target"); continue; }
   model->geom_type[1]=target;
   model->geom_rbound[1]=space->model->geom_rbound[geom];
   mju_copy3(model->geom_size+3,space->model->geom_size+3*geom);
   mju_copy3(data->geom_xpos+3,space->data->geom_xpos+3*geom);
   mju_copy(data->geom_xmat+9,space->data->geom_xmat+9*geom,9);
   bool reversed=type>target; int a=reversed?1:0,b=reversed?0:1;
   auto collision=mjCOLLISIONFUNC[model->geom_type[a]][model->geom_type[b]];
   if (!collision) continue; // In particular, no plane/plane finite manifold.
   mjPreContact contacts[mjMAXCONPAIR]{};
   int count=collision(model.get(),data.get(),contacts,a,b,margin);
   bool invalid=false;
   for(int i=0;i<count;++i) if(!valid_witnesses(model.get(),data.get(),a,b,contacts[i])) invalid=true;
   // Raw contact positions are not universally witness midpoints. In
   // particular, cylinder normal correction and perturbed manifolds break
   // that assumption. Retain original support vertices and portal barycentric
   // witnesses instead of swapping/projecting points or perturbing geometry.
   bool finite_pair=type!=mjGEOM_PLANE && target!=mjGEOM_PLANE;
   if(finite_pair && (invalid || (!count && (type==mjGEOM_CYLINDER || target==mjGEOM_CYLINDER)))) {
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
       if(distance>=0 && distance<=margin && valid_witnesses(model.get(),data.get(),0,1,repaired)) {
         contacts[0]=repaired;count=1;reversed=false;
       } else {mj_unsupported("primitive contact witness could not be validated");count=0;}
     }
   }
   for(int i=0;i<count;++i) {
     const auto &c=contacts[i];
     Overlap hit{body,space->geom_owners[geom].second,c,reversed,{}};
     mjtNum target_point[3],hint[3];
     mju_addScl3(target_point,c.pos,c.normal,(reversed?-1:1)*.5*c.dist);
     mju_scl3(hint,c.normal,reversed?1:-1);
     hit.target_normal=witness_normal(model.get(),data.get(),1,target_point,hint);
     if(!valid_witnesses(model.get(),data.get(),reversed?1:0,reversed?0:1,c) ||
         !hit.target_normal.is_finite() || Math::abs(hit.target_normal.length_squared()-1)>1e-5) {
       mj_unsupported("primitive contact witness could not be validated");
       continue;
     }
     if(std::isfinite(c.dist) && c.dist<=margin &&
         Vector3(c.normal[0],c.normal[1],c.normal[2]).is_finite() &&
         contact_point(hit,true).is_finite() && contact_point(hit,false).is_finite()) hits.push_back(hit);
   }
 }
 std::stable_sort(hits.begin(),hits.end(),[](const Overlap &a,const Overlap &b) {
   if(a.body->rid!=b.body->rid) return a.body->rid.get_id()<b.body->rid.get_id();
   return a.shape<b.shape;
 });
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
 }
}
// Support of a primitive in world direction, with sizes/axes in MuJoCo order.
gmj_sweep::Vec support(int type, const mjtNum *size, const mjtNum *matrix, gmj_sweep::Vec n) {
 mjtNum direction[3]={n.x,n.y,n.z}, local[3], v[3], world[3];
 mju_mulMatTVec3(local,matrix,direction);
 if(type==mjGEOM_SPHERE) { double length=mju_norm3(local); for(int i=0;i<3;++i) v[i]=size[0]*local[i]/length; }
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
 auto kind=target==mjGEOM_SPHERE?gmj_sweep::Kind::sphere:target==mjGEOM_BOX?gmj_sweep::Kind::box:gmj_sweep::Kind::cylinder;
 return (point-gmj_sweep::closest({kind,{ts[0],ts[1],ts[2]}},point)).length()-size[0]-margin;
}
} // namespace

bool MjDirectSpaceState::_intersect_ray(const Vector3 &p_from, const Vector3 &p_to,
		uint32_t p_collision_mask, bool p_collide_with_bodies, bool p_collide_with_areas,
		bool p_hit_from_inside, bool p_hit_back_faces, bool p_pick_ray,
		PhysicsServer3DExtensionRayResult *p_result) {
	if (!p_result) {
		return false;
	}
	*p_result = {};
	p_result->shape = -1;
	p_result->face_index = -1;
	if (p_collide_with_areas) {
		mj_unsupported("Area3D ray queries");
	}
	// Primitive rays are two-sided; heightfield back faces obey the query flag.
	if (!server || !p_collide_with_bodies || !p_collision_mask ||
			!p_from.is_finite() || !p_to.is_finite()) {
		return false;
	}
	MjSpace *query_space = server->space(rid);
	if (!query_space || !server->rebuild(*query_space) ||
			!query_space->model || !query_space->data) {
		// In particular, do not query stale geometry after a failed rebuild.
		return false;
	}
	const mjModel *model = query_space->model;
	const mjData *data = query_space->data;
	if (query_space->geom_owners.size() != static_cast<size_t>(model->ngeom)) {
		mj_unsupported("ray query with inconsistent geom ownership");
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

	for (int geom = 0; geom < model->ngeom; ++geom) {
		const auto &owner = query_space->geom_owners[geom];
		MjBody *body = query_body(*this, *query_space, geom, p_collision_mask, p_pick_ray);
		if (!body) continue;
		// A query's mask is matched against the body's layer. The body's own
		// collision mask controls body/body contacts, not visibility to rays.
		const int type = model->geom_type[geom];
		if (type != mjGEOM_BOX && type != mjGEOM_SPHERE && type != mjGEOM_PLANE && type != mjGEOM_CYLINDER && type != mjGEOM_HFIELD) {
			mj_unsupported("ray queries for non-box/sphere/world-boundary shapes");
			continue;
		}
		const mjtNum *position = data->geom_xpos + 3 * geom;
		const mjtNum *matrix = data->geom_xmat + 9 * geom;
		const mjtNum *size = model->geom_size + 3 * geom;
		mjtNum offset[3], local_from[3];
		mju_sub3(offset, origin, position);
		mju_mulMatTVec3(local_from, matrix, offset);
		bool inside = point_inside_geom(type, local_from, size);
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
			nearest = 0;
			nearest_body = body;
			nearest_shape = owner.second;
			nearest_inside = true;
			break;
		}
		if (length == 0) {
			continue;
		}
		mjtNum normal[3] = {};
		mjtNum distance = type == mjGEOM_HFIELD ? mj_rayHfield(model, data, geom, origin, direction, normal) : intersect_geom(type, position, matrix, size, origin, direction,
				local_from, normal);
		if (!std::isfinite(distance) || distance < 0 || distance > length + endpoint_tolerance ||
				!std::isfinite(normal[0]) || !std::isfinite(normal[1]) || !std::isfinite(normal[2])) {
			continue;
		}
		if (type == mjGEOM_HFIELD && !p_hit_back_faces && mju_dot3(normal,direction) > 0) continue;
		distance = std::min(distance, length);
		if (nearest_body && distance >= nearest) {
			continue;
		}
		nearest = distance;
		nearest_body = body;
		nearest_shape = owner.second;
		mju_copy3(nearest_normal, normal);
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
 if (!results || max_results<=0 || !position.is_finite()) return 0;
 auto *space=query_space(*this,mask,bodies,areas); if(!space) return 0;
 std::vector<PhysicsServer3DExtensionShapeResult> hits;
 Vector3 p=godot_to_mj(position); mjtNum point[3]={p.x,p.y,p.z};
 for(int geom=0;geom<space->model->ngeom;++geom) {
   auto *body=query_body(*this,*space,geom,mask); if(!body) continue;
   int type=space->model->geom_type[geom];
   if(!primitive(type)) { mj_unsupported("heightfield/nonprimitive point target"); continue; }
   mjtNum offset[3],local[3]; mju_sub3(offset,point,space->data->geom_xpos+3*geom);
   mju_mulMatTVec3(local,space->data->geom_xmat+9*geom,offset);
   if(point_inside_geom(type,local,space->model->geom_size+3*geom)) hits.push_back(shape_result(*body,space->geom_owners[geom].second));
 }
 std::sort(hits.begin(),hits.end(),[](const auto &a,const auto &b){return a.rid==b.rid?a.shape<b.shape:a.rid.get_id()<b.rid.get_id();});
 int count=std::min(max_results,int(hits.size())); std::copy_n(hits.begin(),count,results); return count;
}

int32_t MjDirectSpaceState::_intersect_shape(const RID &shape, const Transform3D &pose, const Vector3 &motion,
    float margin, uint32_t mask, bool bodies, bool areas, PhysicsServer3DExtensionShapeResult *results, int32_t max_results) {
 if(!results || max_results<=0) return 0;
 auto hits=overlaps(*this,shape,pose,motion,margin,mask,bodies,areas); int count=0;
 for(const auto &hit:hits) {
   if(count && results[count-1].rid==hit.body->rid && results[count-1].shape==hit.shape) continue;
   results[count++]=shape_result(*hit.body,hit.shape); if(count==max_results) break;
 }
 return count;
}

bool MjDirectSpaceState::_cast_motion(const RID &shape_rid, const Transform3D &transform, const Vector3 &motion,
    float margin, uint32_t mask, bool bodies, bool areas, float *safe, float *unsafe,
    PhysicsServer3DExtensionShapeRestInfo *info) {
 if(safe) *safe=0; if(unsafe) *unsafe=0; if(info) *info={};
 if(!safe || !unsafe || !server || !transform.is_finite() || !motion.is_finite() ||
     !transform.basis.is_orthogonal() || !transform.basis.get_scale().is_equal_approx(Vector3(1,1,1)) ||
     transform.basis.determinant()<=0 || !std::isfinite(margin) || margin<0) return false;
 auto *shape=server->shape(shape_rid);
 if(!shape || server->pending_free.count(shape_rid.get_id())) return false;
 if(areas) { mj_unsupported("continuous sweep of Area3D"); return false; }
 int type; mjtNum size[3]={}; Transform3D pose=transform;
 switch(shape->type) {
 case PhysicsServer3D::SHAPE_SPHERE: type=mjGEOM_SPHERE; size[0]=double(shape->data); break;
 case PhysicsServer3D::SHAPE_BOX: { type=mjGEOM_BOX; Vector3 v=shape->data; size[0]=v.x; size[1]=v.z; size[2]=v.y; break; }
 case PhysicsServer3D::SHAPE_CYLINDER: { type=mjGEOM_CYLINDER; Dictionary d=shape->data; size[0]=double(d["radius"]); size[1]=double(d["height"])*.5; break; }
 case PhysicsServer3D::SHAPE_WORLD_BOUNDARY: {
   type=mjGEOM_PLANE; Plane p=shape->data;
   if(!std::isfinite(p.normal.length()) || !std::isfinite(p.d)) return false;
   Vector3 n=p.normal.normalized(); pose.origin+=pose.basis.xform(n*(p.d/p.normal.length()));
   pose.basis=pose.basis*Basis(Quaternion(Vector3(0,1,0),n)); break;
 }
 default: mj_unsupported("continuous sweep query shape"); return false;
 }
 for(double extent:size) if(!std::isfinite(extent) || extent<0 || extent>std::numeric_limits<real_t>::max()) return false;
 if(!pose.is_finite()) return false;
 if(!bodies || !mask) { *safe=*unsafe=1; return true; }
 auto *space=query_space(*this,mask,bodies,false); if(!space) return false;
 // Validate the complete candidate set first: never report a clear sweep by
 // silently ignoring an unsupported native obstacle, even beyond a closer hit.
 for(int geom=0;geom<space->model->ngeom;++geom) {
   if(!query_body(*this,*space,geom,mask)) continue;
   int target=space->model->geom_type[geom];
   if(!primitive(target) || (type==mjGEOM_PLANE && target==mjGEOM_PLANE) ||
       (type!=mjGEOM_SPHERE && type!=mjGEOM_PLANE && target!=mjGEOM_PLANE)) {
     mj_unsupported("continuous sweep pair (sphere/primitive or finite/plane only)"); return false;
   }
 }
 using gmj_sweep::Vec;
 Vector3 p=godot_to_mj(pose.origin), m=godot_to_mj(motion);
 Vec origin{p.x,p.y,p.z}, velocity{m.x,m.y,m.z};
 if(velocity.length()==0) { *safe=*unsafe=1; return true; }
 Quaternion rotation=godot_to_mj(pose.basis).get_rotation_quaternion().normalized();
 mjtNum quat[4]={rotation.w,rotation.x,rotation.y,rotation.z}, matrix[9];
 mju_normalize4(quat); mju_quat2Mat(matrix,quat);
 double first=2, lower=1; MjBody *nearest=nullptr; int nearest_shape=-1, nearest_geom=-1; Vec witness{},normal{};
 for(int geom=0;geom<space->model->ngeom;++geom) {
   auto *body=query_body(*this,*space,geom,mask); if(!body) continue;
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
     auto kind=target==mjGEOM_SPHERE?gmj_sweep::Kind::sphere:target==mjGEOM_BOX?gmj_sweep::Kind::box:gmj_sweep::Kind::cylinder;
     hit=gmj_sweep::sphere({kind,{ts[0],ts[1],ts[2]}},{local[0],local[1],local[2]},
         {direction[0],direction[1],direction[2]},size[0]+double(margin));
     mjtNum wp[3],wn[3],lp[3]={hit.point.x,hit.point.y,hit.point.z},ln[3]={hit.normal.x,hit.normal.y,hit.normal.z};
     mju_mulMatVec3(wp,mat,lp); mju_mulMatVec3(wn,mat,ln);
     point=center+Vec{wp[0],wp[1],wp[2]}; n={wn[0],wn[1],wn[2]};
   }
   if(!hit.valid) { mj_unsupported("continuous sweep numerical bracket could not be certified"); return false; }
   if(!hit.hit) continue;
   lower=std::min(lower,hit.safe);
   auto owner=space->geom_owners[geom];
   bool earlier=hit.unsafe<first;
   bool tie=hit.unsafe==first && nearest && (body->rid.get_id()<nearest->rid.get_id() || (body->rid==nearest->rid && owner.second<nearest_shape));
   if(earlier || tie) { first=hit.unsafe; nearest=body; nearest_shape=owner.second; nearest_geom=geom; witness=point; normal=n; }
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
 double safe_gap=abi_gap(lo), unsafe_gap=abi_gap(hi);
 double continuous_safe=continuous_gap(lo), continuous_unsafe=continuous_gap(hi);
 if(!std::isfinite(safe_gap) || !std::isfinite(unsafe_gap) || !std::isfinite(continuous_safe) ||
     !std::isfinite(continuous_unsafe) || safe_gap<0 || unsafe_gap>0 || continuous_safe<0 || continuous_unsafe>0) {
   mj_unsupported("continuous sweep contact has no certified float safe/unsafe poses"); return false;
 }
 *safe=std::clamp(lo,0.0f,1.0f); *unsafe=std::clamp(hi,0.0f,1.0f);
 if(info) rest_result(*space,*nearest,nearest_shape,point,n,*info);
 return true;
}

bool MjDirectSpaceState::_collide_shape(const RID &shape, const Transform3D &pose, const Vector3 &motion,
    float margin, uint32_t mask, bool bodies, bool areas, void *results, int32_t max_results, int32_t *count) {
 if(count) *count=0;
 if(!count || !results || max_results<=0) return false;
 auto hits=overlaps(*this,shape,pose,motion,margin,mask,bodies,areas);
 auto *points=static_cast<Vector3 *>(results);
 for(const auto &hit:hits) {
   points[2*(*count)]=contact_point(hit,true); points[2*(*count)+1]=contact_point(hit,false);
   if(++(*count)==max_results) break;
 }
 return *count>0;
}

bool MjDirectSpaceState::_rest_info(const RID &shape, const Transform3D &pose, const Vector3 &motion,
    float margin, uint32_t mask, bool bodies, bool areas, PhysicsServer3DExtensionShapeRestInfo *info) {
 if(!info) return false; *info={};
 auto hits=overlaps(*this,shape,pose,motion,margin,mask,bodies,areas); if(hits.empty()) return false;
 const auto &hit=*std::min_element(hits.begin(),hits.end(),[](const Overlap &a,const Overlap &b){return a.contact.dist<b.contact.dist;});
 rest_result(*server->space(rid),*hit.body,hit.shape,contact_point(hit,false),hit.target_normal,*info);
 return true;
}

Vector3 MjDirectSpaceState::_get_closest_point_to_object_volume(const RID &, const Vector3 &) const {
	mj_unsupported("direct-space get_closest_point_to_object_volume");
	return Vector3();
}

} // namespace godot
