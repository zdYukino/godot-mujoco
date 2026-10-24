#pragma once
#define CCD_DOUBLE
#define CCD_STATIC_DEFINE
// Private symbols: never interpose on MuJoCo's independent libccd copy.
#define ccdVec3PointTriDist2 gmj_ccdVec3PointTriDist2
#define ccdVec3PointSegmentDist2 gmj_ccdVec3PointSegmentDist2
#define ccd_vec3_origin gmj_ccd_vec3_origin
#define ccd_points_on_sphere gmj_ccd_points_on_sphere
#define ccd_points_on_sphere_len gmj_ccd_points_on_sphere_len
#define __ccdSupport gmj_ccdSupport
