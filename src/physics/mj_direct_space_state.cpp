#include "mj_physics_server.h"

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
 MjBody *body; int shape; mjPreContact contact; bool reversed;
};
Vector3 contact_point(const Overlap &hit, bool query);
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
 Vector3 pos=godot_to_mj(pose.origin); Basis basis=godot_to_mj(pose.basis);
 for (int a=0;a<3;++a) { data->geom_xpos[a]=pos[a]; for(int b=0;b<3;++b) data->geom_xmat[3*a+b]=basis[a][b]; }
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
   // MuJoCo 3.16 native GJK can return no witness for concentric cylinder
   // pairs (also cylinder/box). Its independent MPR narrowphase resolves
   // these degeneracies without perturbing geometry or sampling motion.
   if (!count && (type==mjGEOM_CYLINDER || target==mjGEOM_CYLINDER)) {
     model->opt.disableflags |= mjDSBL_NATIVECCD;
     count=collision(model.get(),data.get(),contacts,a,b,margin);
     model->opt.disableflags &= ~mjDSBL_NATIVECCD;
   }
   for(int i=0;i<count;++i) {
     const auto &c=contacts[i];
     Overlap hit{body,space->geom_owners[geom].second,c,reversed};
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

bool MjDirectSpaceState::_cast_motion(const RID &, const Transform3D &, const Vector3 &,
		float, uint32_t, bool, bool, float *p_closest_safe, float *p_closest_unsafe,
		PhysicsServer3DExtensionShapeRestInfo *p_info) {
	if (p_closest_safe) {
		*p_closest_safe = 0;
	}
	if (p_closest_unsafe) {
		*p_closest_unsafe = 0;
	}
	if (p_info) {
		*p_info = {};
	}
	mj_unsupported("direct-space cast_motion");
	return false;
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
 info->rid=hit.body->rid; info->collider_id=ObjectID(hit.body->object_id); info->shape=hit.shape;
 info->point=contact_point(hit,false);
 double sign=hit.reversed?1:-1;
 info->normal=mj_to_godot(Vector3(hit.contact.normal[0],hit.contact.normal[1],hit.contact.normal[2]))*sign;
 // MuJoCo object velocity is COM based; point velocity must include angular motion.
 auto *space=server->space(rid);
 int id=hit.body->mj_body;
 if(id>=0 && hit.body->mode==PhysicsServer3D::BODY_MODE_RIGID) {
   mjtNum velocity[6]; mj_objectVelocity(space->model,space->data,mjOBJ_BODY,id,velocity,0);
   Vector3 angular=mj_to_godot(Vector3(velocity[0],velocity[1],velocity[2]));
   Vector3 linear=mj_to_godot(Vector3(velocity[3],velocity[4],velocity[5]));
   const mjtNum *com=space->data->xipos+3*id;
   info->linear_velocity=linear+angular.cross(info->point-mj_to_godot(Vector3(com[0],com[1],com[2])));
 }
 return true;
}

Vector3 MjDirectSpaceState::_get_closest_point_to_object_volume(const RID &, const Vector3 &) const {
	mj_unsupported("direct-space get_closest_point_to_object_volume");
	return Vector3();
}

} // namespace godot
