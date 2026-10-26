# Spatial query contract and executable matrix (MuJoCo 3.16.0)

Branch: codex/spatial-query-sdf-terrain-gtr, based on
49258c705a25049fccab75274f6bfd14c38e350e. This is **not a claim that every
Godot query/shape combination is complete**. Exact versions: MuJoCo 3.16.0,
Godot 4.7.2 .NET. All engineering and acceptance execute on GTR.

## Public API and errors

Use Godot PhysicsDirectSpaceState3D intersect_ray, intersect_point,
intersect_shape, collide_shape, get_rest_info, and cast_motion.
Read state.call("get_query_status") **immediately after each query**:

~~~gdscript
var hits = state.intersect_shape(parameters)
var status: Dictionary = state.call("get_query_status")
if not status.ok:
    push_error(status.error) # unknown/unsupported, never interpret as clear
    return
# Empty hits now means a supported, completed miss.
~~~

Status {ok, error, kind, sequence, details} belongs to the last request on this space state.
A failed overlap discards partial results. Godot's standard empty collection
alone cannot distinguish failure from a miss. Warnings are additional
diagnostics, not a reliable status API; status updates on every call.
cast_motion failure returns an empty array; successful clear returns [1,1].
Inspecting status does not change its sequence.

Queries use the target layer against the query mask, not its collision mask;
support excludes, disabled/freed shapes and bodies, compound shape indices and
actual imported RIDs. Imported model/map nodes register their Godot owner.
Areas use the same mask/exclude rules; monitoring/monitorable do not disable
queries. Ray pickability is honored only for pick-ray requests. Sorting/ties
use RID and shape index. Only rigid, finite, positive-handed unit transforms
are accepted. Overlap APIs ignore supplied motion, as Godot does.
Queries do not run mj_step/mj_forward on live simulation data.

## Coverage and remaining work

| Query | Targets/implementation | Evidence / boundary |
| --- | --- | --- |
| Ray | native primitives, imported MJCF primitives/ellipsoid, compiled mesh hull, hfield, plugin-free mesh SDF, native primitive Areas | Original native ray suites; area.gd; terrain checks SDF floor, alpha=0, filtering, identity and convex hull control. Imported ellipsoid/mesh combinations need broader matrix coverage. |
| Point | the same targets, closed-volume membership | Areas and terrain; hull uses compiled hull planes; hfield uses closed base and triangle surface. Boundaries are not inside. |
| Overlap/collide/rest | native primitive queries against primitives/Areas; immutable asset-backed narrowphase view for mesh, ellipsoid, hfield/SDF | Original overlap/witness suites; area.gd; sphere/SDF suite. asset_pair_matrix.gd tests all four finite query primitives against hull, ellipsoid, hfield and SDF at separated/margin/penetrating/contained poses in identity and rigidly transformed scenes (128 cases). Unverified witnesses fail the whole request with observable status; this is not exhaustive certification of every possible asset. |
| Sphere/SDF overlap | native field zero-level contact witness; interval subdivision proves separation | asset_overlap.gd: original sphere/target surface points, target normal, positive margin once, separated proof, repeated errors/status reset. Local stationarity is not treated as global nearest distance; no claimed globally minimal penetration depth. |
| Continuous sphere/capsule to primitive | original analytic convex-distance path | Original sweep, capsule, sweep_precision; independent float safe/unsafe pose checks. |
| Continuous box/cylinder, Areas, imported convex mesh/ellipsoid | support-plane conservative advancement + GJK bounds and MPR penetration certificates | convex_cast.gd, convex_numerics.cpp, independent continuous SAT oracle convex_sat.cpp. Fixed orientation during translation, not angular interpolation. |
| Continuous hfield | exact union of engine triangular vertical prisms down to the base | hfield_cast.gd: four shapes, transforms/margin, fast crossing, zero motion, initial overlap/exclude/disabled. 2048-cell budget; larger fields reject. Internal prism tangency after a union hit is handled by certifying the preceding path. |
| Continuous SDF | **bounded actual-octree interval certification**, finite sphere/box/cylinder/capsule, fixed orientation | sdf_cast.gd 50 checks; native-field and ULP probes. Thin high-speed crossing succeeds. Extended stair-edge now passes including the actual SDF contact/normal; rough-oblique now has a certified <=0.5mm total bracket in the combined mode; its legacy/0.1mm modes remain unresolved. Exact initial-touch/graze cases remain unknown. The full requested boundary scope is **not complete**. No source-triangle substitute or temporal sampling miss proof. |
| Unbounded plane/asset combinations | limited; plane/hfield and plane/SDF sweeps reject | No invented finite manifold. |
| ConvexPolygon/ConcavePolygon, arbitrary mesh/hfield as query shapes | **not implemented as query shapes** | Native shape creation contract remains separate. No silent boxes/hulls. |
| Character/body_test_motion and dynamic rigid-body CCD | original sphere/capsule path only | Not expanded by public convex cast. A shape cast is not dynamic CCD. |
| Closest point to arbitrary object volume | **unsupported** | Every call starts a new status/sequence; repeated unsupported calls and later success reset are tested. |

Continuous results require a certified safe prefix and actual contact upper
bound, including float fraction and float-transformed Godot pose.
Numerically unrepresentable cases reject. No temporal grid discovers a hit;
a clear upper candidate never proves a path clear. Convex-pair intersection
times form one connected interval, supporting contact bracket refinement.
For nonconvex SDF the lower prefix instead comes from whole swept-volume interval separation; a clear pose never advances it. The actual hit upper is separately certified.

## Exact 3.16 details

- Public mj_ray includes normal[3]. Internal mj_raySdf is static and reached
  through the dispatcher (40 marching steps, 1e-7 threshold).
- Native alpha/material filtering removes hidden geometry. Queries use a
  shallow private model view with private group/rgba/material arrays,
  preserving live physics when collision visuals are hidden.
- Mesh collision uses the compiled convex hull. Mesh rays/points use hull
  planes, not visual source triangles through a doorway or depression.
- mj_geomDistance is not universal: unsupported collision table pairs can
  return distmax.
- Native SDF contacts are optimization points, not guaranteed original
  shape surface witness pairs. Witnesses are validated independently.
- Finite-primitive separation bounds the actual trilinear octree field over boxes
  intersecting the primitive or its entire translated swept convex volume. Unknown boundary/budget cases fail. Projection alone
  never reports a miss. Contact projection provides a local physical witness,
  not a globally closest-distance proof.
- nativeccd means convex narrowphase, not continuous time of impact.
- mjsMesh.octree_maxdepth exists; the 3.16 XML reader does not accept that XML
  attribute. Version-2 snapshots preserve explicit native per-mesh options.
  Old binaries reject version 2 instead of silently dropping options;
  version-1 snapshots remain readable. Explicit defaults are preserved.

Fixed upstream sources:
[mujoco.h](https://github.com/google-deepmind/mujoco/blob/3.16.0/include/mujoco/mujoco.h),
[ray](https://github.com/google-deepmind/mujoco/blob/3.16.0/src/engine/engine_ray.c),
[SDF](https://github.com/google-deepmind/mujoco/blob/3.16.0/src/engine/engine_collision_sdf.c),
[mesh](https://github.com/google-deepmind/mujoco/blob/3.16.0/src/user/user_mesh.cc).

## SDF numeric, error and resource contract

See [actual-field interval derivation and remaining work](sdf-interval-certification.md).
The field uses native oct_aabb/oct_coeff/oct_child data, not source mesh triangles.
Each leaf polynomial is bounded outward; native leaf selection EPS and the exterior
1e-6 projection are included. An arbitrary affine plane plus its interval residual
can tighten the support-volume lower bound inside the root. Piecewise root
projection is handled separately; no global unit-Lipschitz assumption is used.

Geometry operations use a propagated per-axis gamma_256 bound E. The support
AABB expands by E; separating planes require an extra sqrt(3)E; strict inside
proofs shrink by that guard. The bound includes the original world origin plus
the full motion magnitude, avoiding cancellation when a large start and travel
produce a small endpoint.

The explicit accepted numeric domain is:
- target world reference components <=1024m and abs(local root center)+half <=1024m;
- query start/end components <=2^20m, primitive half extents/radius in [10um,1024m];
- a capsule may have a zero spine; its radius+spine-half <=1024m;
- cylinder half-height and every box half-extent >=10um; nonnegative margin <=1024m;
- minimum feature >4sqrt(3)E; other invalid fields/plugins/transforms reject.

Target translation (512,256,-128) is tested, as are explicit out-of-domain
coordinates, tiny shapes, nonrigid transforms and subsequent successful reset.
The native test includes 80 offset-root one-ULP-inside probes with another axis
outside; its earlier 1e-12 probes alone were insufficient.

Search and final pose certification share a **2-second checkpoint deadline**, 160000
spatial boxes, 8000000 visited field nodes and 160 time intervals (depth 48).
Deadline checks occur at bounded-loop checkpoints; GJK/contact calls are not interrupted internally, so this is not a strict wall-clock or real-time upper bound. Cache preprocessing is outside that deadline and reported separately.
Per-target counts, cold cache time, cache hits and exhausted status are visible.
The default combined mode requests a **0.5mm total spatial budget**:
path length of the returned fraction bracket + each endpoint's Float32 pose
error + the propagated arithmetic/transform envelope at both endpoints.
The final combined budget is checked again after all float endpoint adjustments.
A successful hit requires a certified collision-free prefix and an actual
negative-field interior witness at the upper pose, including the independently
rounded Godot pose. A narrow unresolved candidate is never reported as a hit.

Per-space APIs:
- set_sdf_query_precision_m(value) returns false without changing the setting
  for nonfinite/out-of-range values. Valid finite budgets are [1e-6,1e-3]m.
- get_sdf_query_precision_m(); default 0.0005m.
- set_sdf_upper_refinement(bool); get_sdf_upper_refinement(); default true.
- value 0 explicitly selects the old nominal 4um/eight-fraction-ULP mode.
  It is a diagnostic compatibility mode, without the finite total-error cap.

Status details expose sdf_total_uncertainty_m, its path/coordinate/arithmetic
components, sdf_precision_met, per-geom counts and candidate statistics.
The scope is the **actual compiled native SDF**, not distance to the source
triangle mesh. No certified source-mesh approximation error is available.
The old (512,256,-128)m probe had a ~38.9um path bracket; the explicit 1e6m
start/full-motion cancellation case had a ~1.49m legacy bracket. The finite
mode rejects the latter with a visible precision error.

Rough-oblique A/B/C comparison and precision findings are reproduced by
sdf_precision.gd --compare. A old mode and B 1mm without candidate refinement
remain Unknown. With real-field local candidate refinement, C returned:
- 0.1mm: Unknown, not a miss;
- 0.5mm: total ~0.471173mm, cold ~0.178s / warm ~0.0298s, 12945 field nodes;
- 1mm: total ~0.656234mm, cold ~0.160s / warm ~0.0155s, 8875 field nodes.
These initial measurements used binary 2638918e; final-build logs supersede
timings. C only improves true-hit candidates; its clear samples never change
the certified safe prefix. The final implementation also refines thin-wall
uppers before accepting the finite bracket, retaining first-entry-side normal
checks in the high-speed regression.

Observed margin-box timing on GTR:
- unoptimized c2bdaec2: cold 0.837s (cache 0.445s), warm 0.387..0.390s, 366169 nodes;
- -O2 f56e4cce: cold 0.242s (cache 0.144s), warm 0.096..0.098s, 366169 nodes;
- final joint-cell bound: cold 0.171s (cache 0.146s), warm 0.02549..0.02554s, 48472 nodes.

CMake optimizes only mj_direct_space_state.cpp and explicitly uses
-fno-fast-math -ffp-contract=off. The interval header rejects fast-math builds.
Resource budgets and geometric witness assertions were retained. The user explicitly changed the spatial precision contract to <=1mm; strict legacy regressions are separately retained. These are measurements,
**not high-frequency real-time performance acceptance**: cold construction and
worst-case search still matter. The default finite mode closes rough_oblique; its strict legacy/0.1mm paths remain unresolved. Exact touch_inward/touch_away/graze are three separately reported unknown contract cases, including in finite mode.

The final improvement clips each possible nonpositive leaf region by an
outward-bounded affine halfspace and proves joint separation from the query.
It passes a native analytic cell counterexample and 20809 random joint-domain
samples (100 sign-positive cases), in addition to the scalar/root probes.
These independent numeric tests are not native end-to-end query counts.
See the derivation and remaining boundary below.

## Reproduce and evidence

~~~bash
. ~/.config/godot-mujoco/gtr-env.sh
python3 tests/spatial_queries/run.py --out /absolute/new/output --godot "$GODOT_BIN" --sdk "$MUJOCO_SDK_DIR"
~~~

Add --extended for the unchanged seeded random numerical probes, multi-depth convergence and reproducible A/B/C cold/warm comparison. Core runs retain deterministic ULP/root/native-branch/joint-cell counterexamples and all essential end-to-end checks. See [test retention rationale](spatial-test-retention.md).

Every group has independent .log, .resources.json and monitor log.
results.json records results/return codes; provenance.json includes host,
base commit/branch, individual source hashes and tested native binary hash (including unstaged continuation changes).
Failed output directories are retained and never reused. RSS samples cover
the directly monitored process; shell preparation/import RSS does not
represent child-process peak. Global available-memory limits still apply.
Existing regression runners retain separate logs.
