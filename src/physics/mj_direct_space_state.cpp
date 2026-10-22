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
		MjBody *body = server->body(owner.first);
		if (!body || body->space != rid || owner.second < 0 ||
				static_cast<size_t>(owner.second) >= body->shapes.size() ||
				body->shapes[owner.second].disabled || !(body->layer & p_collision_mask) ||
				(p_pick_ray && !body->ray_pickable) || is_body_excluded_from_query(owner.first)) {
			continue;
		}
		// A query's mask is matched against the body's layer. The body's own
		// collision mask controls body/body contacts, not visibility to rays.
		const int type = model->geom_type[geom];
		if (type != mjGEOM_BOX && type != mjGEOM_SPHERE && type != mjGEOM_PLANE && type != mjGEOM_HFIELD) {
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

int32_t MjDirectSpaceState::_intersect_point(const Vector3 &, uint32_t, bool, bool,
		PhysicsServer3DExtensionShapeResult *, int32_t) {
	mj_unsupported("direct-space intersect_point");
	return 0;
}

int32_t MjDirectSpaceState::_intersect_shape(const RID &, const Transform3D &, const Vector3 &,
		float, uint32_t, bool, bool, PhysicsServer3DExtensionShapeResult *, int32_t) {
	mj_unsupported("direct-space intersect_shape");
	return 0;
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

bool MjDirectSpaceState::_collide_shape(const RID &, const Transform3D &, const Vector3 &,
		float, uint32_t, bool, bool, void *, int32_t, int32_t *p_result_count) {
	if (p_result_count) {
		*p_result_count = 0;
	}
	mj_unsupported("direct-space collide_shape");
	return false;
}

bool MjDirectSpaceState::_rest_info(const RID &, const Transform3D &, const Vector3 &,
		float, uint32_t, bool, bool, PhysicsServer3DExtensionShapeRestInfo *p_rest_info) {
	if (p_rest_info) {
		*p_rest_info = {};
	}
	mj_unsupported("direct-space rest_info");
	return false;
}

Vector3 MjDirectSpaceState::_get_closest_point_to_object_volume(const RID &, const Vector3 &) const {
	mj_unsupported("direct-space get_closest_point_to_object_volume");
	return Vector3();
}

} // namespace godot
